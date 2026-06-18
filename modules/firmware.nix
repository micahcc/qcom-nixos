# DSP runtime firmware delivery.
#
# Two responsibilities:
#  1. Override `pkgs.linux-firmware` so files our platform firmware also
#     ships are removed from upstream linux-firmware (otherwise upstream's
#     compressed `.zst` variants can shadow our working uncompressed ones).
#  2. Build a pre-merged firmware tree referenced via kernel cmdline
#     `firmware_class.path=...` so the kernel firmware loader finds DSP /
#     SerDes / qupv3fw firmware at module probe time (~t=1.4s, before any
#     user-space init has run).
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.firmware;
  platformDir = config.hardware.qualcomm.firmwarePath;

  # Pre-merged firmware tree referenced by kernel cmdline `firmware_class.path`.
  # Real (uncompressed) files at $out/<platformDir>/<file> so the kernel finds
  # firmware at module probe time, before user-space init.
  initrdFirmware = pkgs.runCommand "qcom-initrd-firmware"
    { nativeBuildInputs = [ pkgs.zstd ]; } ''
    mkdir -p $out/${platformDir}

    if [ -d ${pkgs.linux-firmware}/lib/firmware/${platformDir} ]; then
      for f in ${pkgs.linux-firmware}/lib/firmware/${platformDir}/*; do
        name=$(basename "$f")
        case "$name" in
          *.zst) zstd -d "$f" -o "$out/${platformDir}/''${name%.zst}" ;;
          *)     cp "$f" "$out/${platformDir}/$name" ;;
        esac
      done
    fi

    ${lib.optionalString (cfg.platformPackage != null) ''
    if [ -d ${cfg.platformPackage}/lib/firmware/${platformDir} ]; then
      for f in ${cfg.platformPackage}/lib/firmware/${platformDir}/*; do
        name=$(basename "$f")
        cp -f "$f" "$out/${platformDir}/$name"
      done
    fi
    ''}

    ${lib.concatMapStringsSep "\n"
      (f: ''rm -f $out/${platformDir}/${f}'')
      cfg.dropFiles}
  '';
in
{
  options.hardware.qualcomm.firmware = {
    platformPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package providing platform-specific DSP firmware (e.g.
        `dragonwing-firmware`). Files in this package's
        `lib/firmware/<firmwarePath>/` shadow upstream linux-firmware.
      '';
    };

    dropFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "gpdspr.jsn" "gpdsp1r.jsn" ];
      description = ''
        File names (basename only, under `<firmwarePath>/`) to drop from the
        merged firmware tree. Use to suppress upstream files that confuse
        the platform (e.g. SA8775P does not actually serve gpdsp PDs).
      '';
    };

    overlayLinuxFirmware = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.qualcomm.platform != null;
      description = ''
        Whether to apply an overlay that strips files our platformPackage
        also ships from `pkgs.linux-firmware` (and disables compression so
        pd-mapper can read `.jsn` files directly). Required when both
        upstream and platform firmware ship the same path — otherwise
        upstream's compressed `.zst` may shadow our uncompressed file.
      '';
    };
  };

  config = lib.mkIf (config.hardware.qualcomm.enable && config.hardware.qualcomm.platform != null) {
    nixpkgs.overlays = lib.mkIf cfg.overlayLinuxFirmware [
      (final: prev: {
        linux-firmware = prev.linux-firmware.overrideAttrs (old: {
          # pd-mapper reads .jsn files directly — they must stay uncompressed.
          compressFirmware = false;
          postInstall = (old.postInstall or "") + lib.optionalString
            (cfg.platformPackage != null) ''
            # Remove upstream files our platformPackage also ships, matching on
            # stem so .zst/.xz/.gz compressed variants are caught too.
            strip_compress() { echo "''${1%.zst}" | sed 's/\.\(xz\|gz\|zst\)$//'; }
            if [ -d $out/lib/firmware/${platformDir} ] && \
               [ -d ${cfg.platformPackage}/lib/firmware/${platformDir} ]; then
              for f in ${cfg.platformPackage}/lib/firmware/${platformDir}/*; do
                stem=$(strip_compress "$(basename "$f")")
                for victim in \
                  $out/lib/firmware/${platformDir}/"$stem" \
                  $out/lib/firmware/${platformDir}/"$stem".zst \
                  $out/lib/firmware/${platformDir}/"$stem".xz \
                  $out/lib/firmware/${platformDir}/"$stem".gz; do
                  [ -e "$victim" ] && rm -fv "$victim"
                done
              done
            fi
          '' + lib.concatMapStringsSep "\n"
            (f: ''rm -fv $out/lib/firmware/${platformDir}/${f}{,.zst,.xz,.gz} 2>/dev/null || true'')
            cfg.dropFiles + ''
            find $out/lib/firmware -xtype l -delete
          '';
        });
      })
    ];

    hardware.firmware = lib.mkIf (cfg.platformPackage != null) [ cfg.platformPackage ];

    boot.initrd.systemd.storePaths = [ "${initrdFirmware}" ];
    boot.kernelParams = [ "firmware_class.path=${initrdFirmware}" ];
  };
}
