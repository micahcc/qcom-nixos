# Top-level NixOS module for Qualcomm platform support.
#
# Imports per-subsystem modules (qrtr, pd-mapper, fastrpc, firmware, kernel)
# and per-device modules (devices/iq-9075-evk.nix). Setting
# `hardware.qualcomm.device` is the typical entry point — it pulls in the
# right SoC + board defaults.
{ config, lib, pkgs, ... }:
{
  imports = [
    ./qrtr.nix
    ./pd-mapper.nix
    ./fastrpc.nix
    ./firmware.nix
    ./kernel.nix
    ./llama-server.nix
    ./sa8775p
    ./devices/iq-9075-evk.nix
    ./deploy
  ];

  options.hardware.qualcomm = {
    enable = lib.mkEnableOption "Qualcomm platform support (QRTR, FastRPC, pd-mapper)";

    device = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "iq-9075-evk" ]);
      default = null;
      example = "iq-9075-evk";
      description = ''
        Convenience device selector. Pulls in matching SoC + board defaults
        (kernel CONFIG, kernel cmdline, DSP firmware, fastrpc DSP libraries,
        platform-specific kernel modules).
      '';
    };

    platform = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "sa8775p" ]);
      default = null;
      example = "sa8775p";
      description = ''
        Qualcomm SoC platform. Set automatically by `device` selectors;
        can also be set directly for board-less SoC bring-up.
      '';
    };

    firmwarePath = lib.mkOption {
      type = lib.types.str;
      default = if config.hardware.qualcomm.platform != null
                then "qcom/${config.hardware.qualcomm.platform}"
                else "";
      description = ''
        Subdirectory under `/lib/firmware` where DSP firmware lives
        (e.g. "qcom/sa8775p"). Used by pd-mapper for `.jsn` lookup.
      '';
    };
  };
}
