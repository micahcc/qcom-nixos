# Builds a raw disk image suitable for flashing to the IQ-9075 EVK via qdl.
# The image has:
#   - GPT partition table (4096-byte sectors to match UFS)
#   - EFI System Partition (512MB, FAT32)
#   - Root partition (ext4, remaining space)
#
# Enable with: hardware.qualcomm.iq-9075-evk.diskImage.enable = true;
# Exposes:     config.system.build.diskImage
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.iq-9075-evk.diskImage;
  hostname = config.networking.hostName;

  rootfsImage = pkgs.callPackage (
    { runCommand, dosfstools, e2fsprogs, util-linux, mtools, coreutils, python3, fakeroot, closureInfo }:
    let
      closure = closureInfo { rootPaths = [ config.system.build.toplevel ]; };
    in
    runCommand "${hostname}-disk-image" {
      nativeBuildInputs = [ dosfstools e2fsprogs util-linux mtools coreutils python3 fakeroot ];
    } ''
      # Build root filesystem contents
      mkdir -p rootfs/nix/store
      mkdir -p rootfs/boot
      mkdir -p rootfs/etc
      mkdir -p rootfs/sbin
      mkdir -p rootfs/run
      mkdir -p rootfs/tmp
      mkdir -p rootfs/var
      mkdir -p rootfs/nix/var/nix/profiles
      mkdir -p rootfs/nix/var/nix/gcroots
      mkdir -p rootfs/nix/var/nix/daemon-socket

      # Copy all store paths
      while IFS= read -r path; do
        cp -a "$path" rootfs/nix/store/
      done < ${closure}/store-paths

      # Include registration file for first-boot DB population
      cp ${closure}/registration rootfs/nix/var/nix/registration

      # Set up system profile
      ln -s ${config.system.build.toplevel} rootfs/nix/var/nix/profiles/system

      # Create init symlink
      ln -s ${config.system.build.toplevel}/init rootfs/sbin/init

      # NixOS markers
      touch rootfs/etc/NIXOS
      echo "${hostname}" > rootfs/etc/hostname

      # Build root ext4 image (sized to closure + 512MB headroom)
      closure_size_mb=$(( $(du -sm rootfs | cut -f1) + 512 ))
      # Use at least rootMinSizeMB to avoid ext4 overhead issues
      root_mb=$(( closure_size_mb > ${toString cfg.rootMinSizeMB} ? closure_size_mb : ${toString cfg.rootMinSizeMB} ))
      echo "Root filesystem size: ''${root_mb}MB (closure + headroom)"
      truncate -s ''${root_mb}M rootfs.img
      # Use fakeroot so mkfs.ext4 -d records root ownership for all files
      fakeroot -- mkfs.ext4 -L nixos -d rootfs rootfs.img

      # Create EFI partition with GRUB
      truncate -s ${toString cfg.espSizeMB}M efi.img
      mkfs.vfat -F 32 -S ${toString cfg.sectorSize} -n ESP efi.img
      mmd -i efi.img ::EFI
      mmd -i efi.img ::EFI/BOOT
      mmd -i efi.img ::EFI/nixos
      mmd -i efi.img ::grub

      # Create GRUB config
      cat > grub.cfg <<EOF
insmod part_gpt
insmod fat
insmod search
set timeout=3
set default=0

search --file --set=root /EFI/nixos/kernel

menuentry "NixOS" {
  linux /EFI/nixos/kernel init=${config.system.build.toplevel}/init console=ttyMSM0,115200n8 earlycon pcie_pme=nomsi
  initrd /EFI/nixos/initrd
}
EOF

      # Build standalone GRUB EFI binary with embedded config
      ${pkgs.grub2_efi}/bin/grub-mkstandalone \
        --format=arm64-efi \
        --modules="part_gpt fat search" \
        --output=BOOTAA64.EFI \
        "boot/grub/grub.cfg=grub.cfg"

      mcopy -i efi.img BOOTAA64.EFI ::EFI/BOOT/BOOTAA64.EFI
      mcopy -i efi.img grub.cfg ::grub/grub.cfg

      # Copy kernel and initrd
      mcopy -i efi.img ${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile} ::EFI/nixos/kernel
      mcopy -i efi.img ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} ::EFI/nixos/initrd

      # Assemble final GPT disk image with configured sector size
      # The IQ-9075 UFS uses 4096-byte physical sectors; UEFI reads GPT at LBA1 = byte 4096
      efi_sectors=$(( ${toString cfg.espSizeMB} * 1024 * 1024 / ${toString cfg.sectorSize} ))
      root_sectors=$(( root_mb * 1024 * 1024 / ${toString cfg.sectorSize} ))
      # GPT: LBA0=MBR, LBA1=header, LBA2-5=entries, LBA6+=data, last 5 LBAs=backup
      total_sectors=$(( 256 + efi_sectors + root_sectors + 5 ))

      truncate -s $(( total_sectors * ${toString cfg.sectorSize} )) $out

      # Use python to write a proper 4096-byte sector GPT
      # sfdisk ignores sector-size on regular files, so we must construct it manually
      python3 ${../../pkgs/gpt4k.py} $out ${toString cfg.sectorSize} \
        "256:$efi_sectors:C12A7328-F81F-11D2-BA4B-00A0C93EC93B:efi" \
        "$(( 256 + efi_sectors )):$root_sectors:B921B045-1DF0-41C3-AF44-4C6F280D3FAE:writable"

      # Write partition contents
      dd if=efi.img of=$out bs=${toString cfg.sectorSize} seek=256 conv=notrunc
      dd if=rootfs.img of=$out bs=${toString cfg.sectorSize} seek=$(( 256 + efi_sectors )) conv=notrunc
    ''
  ) {};
in
{
  options.hardware.qualcomm.iq-9075-evk.diskImage = {
    enable = lib.mkEnableOption "IQ-9075 EVK disk image builder (system.build.diskImage)";

    sectorSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Sector size in bytes for the GPT partition table (must match UFS physical sector size).";
    };

    espSizeMB = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = "Size of the EFI System Partition in megabytes.";
    };

    rootMinSizeMB = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "Minimum root partition size in megabytes (actual size may be larger to fit the nix store closure).";
    };
  };

  config = lib.mkIf cfg.enable {
    system.build.diskImage = rootfsImage;
  };
}
