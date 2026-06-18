# Kernel command-line knobs for Qualcomm platforms.
#
# `pd_ignore_unused` keeps power domains the bootloader left ON until a real
# consumer registers a vote. Without it (and the matching `clk_ignore_unused`),
# the SA8775P CDSP NSP rail can brown out during the bootloader→driver
# handoff, leaving the DSP firmware in a state where sysmon/ssctl never
# register.
{ config, lib, ... }:
let
  cfg = config.hardware.qualcomm.kernel;
in
{
  options.hardware.qualcomm.kernel = {
    ignoreUnusedPd = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.qualcomm.enable;
      description = "Pass `pd_ignore_unused` on the kernel cmdline.";
    };

    ignoreUnusedClk = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.qualcomm.enable;
      description = "Pass `clk_ignore_unused` on the kernel cmdline.";
    };
  };

  config = lib.mkIf config.hardware.qualcomm.enable {
    boot.kernelParams =
      lib.optional cfg.ignoreUnusedPd "pd_ignore_unused"
      ++ lib.optional cfg.ignoreUnusedClk "clk_ignore_unused";

    boot.kernelModules = [
      # Core Qualcomm platform
      "qcom_scm"
      "qcom_tsens"
      "qcom_spmi_pmic"
      # IPC
      "qrtr"
      "qrtr_smd"
      # Interconnect
      "llcc_qcom"
    ];
  };
}
