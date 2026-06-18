# FastRPC: udev rules + DSP library path.
#
# `libcdsprpc.so` falls back to /usr/lib/dsp/cdsp/ for DSP shells and skel
# libraries. We populate `/run/qcom-dsp` with a buildEnv merge of
# `dspPaths` and symlink it into `/usr/lib/dsp/cdsp` so that path is real.
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.fastrpc;
  qcom-dsp = pkgs.buildEnv {
    name = "qcom-dsp-cdsp";
    paths = cfg.dspPaths;
  };
in
{
  options.hardware.qualcomm.fastrpc = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.qualcomm.enable;
      description = "Enable FastRPC userspace (udev rules and DSP library path).";
    };

    dspPaths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = ''
        Directories to merge into `/run/qcom-dsp` (via `pkgs.buildEnv`).
        Should contain DSP shells (`fastrpc_shell_3`) and skel libraries
        (e.g. `libQnnHtpV73Skel.so`). Typically the platform-specific
        sub-directories of `dragonwing-firmware` and `qairt-dsp-binaries`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "fastrpc" ];

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="dma_heap", KERNEL=="system", MODE="0660", GROUP="video"
      ACTION=="add", SUBSYSTEM=="dma_heap", KERNEL=="qcom,system", MODE="0660", GROUP="video"
      ACTION=="bind", DRIVER=="qcom_rng", RUN+="${pkgs.bash}/bin/sh -c 'echo qcom_hwrng > /sys/class/misc/hw_random/rng_current'"
      ACTION=="add", SUBSYSTEM=="misc", KERNEL=="fastrpc-*", MODE="0666", TAG+="systemd"
    '';

    system.activationScripts.qcom-dsp = lib.mkIf (cfg.dspPaths != []) ''
      ln -sfn ${qcom-dsp} /run/qcom-dsp
      mkdir -p /usr/lib/dsp
      ln -sfn /run/qcom-dsp /usr/lib/dsp/cdsp
    '';
  };
}
