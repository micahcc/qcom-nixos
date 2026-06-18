# SA8775P SoC platform defaults.
#
# Activated when `hardware.qualcomm.platform = "sa8775p"`. Pulls in:
#   - Ubuntu's linux-qcom kernel (with Qualcomm patches and our CONFIG fixes
#     for FW_DEVLINK_SYNC_STATE_TIMEOUT, REGULATOR_PROXY_CONSUMER, DEVFREQ
#     governors, CMA_AREAS=7).
#   - dragonwing-firmware as the platformPackage for runtime DSP firmware.
#   - qairt-dsp-binaries v73 + dragonwing DSP shells as the FastRPC dspPaths.
#   - Drop gpdsp `.jsn` locator files (Ubuntu's pd-mapper does not serve them).
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm;
  isSa8775p = cfg.platform == "sa8775p";
  ride = "share/qcom/sa8775p/Qualcomm/SA8775P-RIDE/dsp/cdsp";
in
{
  config = lib.mkIf isSa8775p {
    boot.kernelPackages = pkgs.linuxPackagesFor pkgs.qualcomm.linux-qcom;

    boot.initrd.availableKernelModules = lib.mkDefault [
      "ufs_qcom"
      "phy_qcom_qmp_ufs"
      "usb_storage"
      "usbhid"
    ];

    boot.kernelModules = [
      # GPU (Adreno 663 — DRM MSM)
      "msm"
      # USB
      "dwc3_qcom"
    ];

    hardware.qualcomm.firmware = {
      platformPackage = lib.mkDefault pkgs.qualcomm.dragonwing-firmware;
      # Ubuntu's pd-mapper does NOT serve gpdsp PDs (only adsp, cdsp).
      # Including gpdspr.jsn / gpdsp1r.jsn causes CDSPs to attempt registration
      # with PDs that no DSP firmware registers, leaving CDSP1 stuck.
      dropFiles = lib.mkDefault [ "gpdspr.jsn" "gpdsp1r.jsn" ];
    };

    hardware.qualcomm.fastrpc.dspPaths = lib.mkDefault [
      "${pkgs.qualcomm.dragonwing-firmware}/${ride}"
      "${pkgs.qualcomm.qairt-dsp-binaries}/${ride}"
    ];
  };
}
