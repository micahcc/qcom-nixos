# IQ-9075 EVK base NixOS configuration.
#
# EVK-generic config that any IQ-9075 NixOS install needs: boot params,
# GRUB config, filesystem declarations, growPartition, nix-register-paths
# service, QNN environment variables, allowUnfree for Qualcomm packages.
#
# Automatically activated when hardware.qualcomm.device = "iq-9075-evk".
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm;
in
{
  options.hardware.qualcomm.iq-9075-evk.qnnEnvironment = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether to set QNN environment variables (ADSP_LIBRARY_PATH, QNN_SDK_ROOT).
      Disable if you want to manage these yourself.
    '';
  };

  config = lib.mkIf (cfg.device == "iq-9075-evk") {
    # Allow unfree Qualcomm packages
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "qnn-sdk"
      "hexagon-sdk"
      "qcom-vendor-libs"
      "qcom-fastrpc"
      "qairt-dsp-binaries"
      "qai-hub-beit-w8a16"
    ];

    # GRUB bootloader (UEFI, no EFI vars — UFS firmware handles boot order)
    boot.loader.grub.enable = true;
    boot.loader.grub.efiSupport = true;
    boot.loader.grub.efiInstallAsRemovable = true;
    boot.loader.grub.device = "nodev";
    boot.loader.efi.canTouchEfiVariables = false;

    # Filesystems (UFS LUN 0 layout: GPT with ESP + root)
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      autoResize = true;
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [ "nofail" ];
    };

    # Grow the root partition to fill the LUN on first boot
    boot.growPartition = true;

    # UFS + USB modules needed in initrd for root mount
    boot.initrd.availableKernelModules = lib.mkForce [
      "ufs_qcom"
      "phy_qcom_qmp_ufs"
      "usb_storage"
      "usbhid"
    ];

    # Serial console + UFS wait
    boot.kernelParams = [
      "console=ttyMSM0,115200n8"
      "earlycon"
      "pcie_pme=nomsi"
      "rootwait"  # UFS PHY init is slow on cold boot; without this, initrd fails to mount root
    ];

    # Make /nix/store writable so nix-daemon can create .links and write store paths
    boot.nixStoreMountOpts = [ "rw" ];

    # Register nix store paths on first boot (image ships paths without DB registration)
    systemd.services.nix-register-paths = {
      description = "Register store paths in nix DB on first boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "nix-daemon.service" ];
      unitConfig.ConditionPathExists = "/nix/var/nix/registration";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "nix-register" ''
          ${config.nix.package}/bin/nix-store --load-db < /nix/var/nix/registration
          rm /nix/var/nix/registration
        ''}";
      };
    };

    # QNN runtime environment - tells HTP backend where to find Hexagon skel libs
    environment.variables = lib.mkIf config.hardware.qualcomm.iq-9075-evk.qnnEnvironment {
      ADSP_LIBRARY_PATH = "/run/qcom-dsp:${pkgs.qualcomm.qnn-sdk}/lib/dsp";
      QNN_SDK_ROOT = "${pkgs.qualcomm.qnn-sdk}";
    };
  };
}
