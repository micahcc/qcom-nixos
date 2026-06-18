# Qualcomm IQ-9075 EVK board defaults.
#
# Selects the SA8775P platform and adds board-specific kernel modules
# (PCIe ethernet switch, WCN6855 WiFi, EVK audio).
{ config, lib, ... }:
let
  cfg = config.hardware.qualcomm;
in
{
  config = lib.mkIf (cfg.device == "iq-9075-evk") {
    hardware.qualcomm.enable = lib.mkDefault true;
    hardware.qualcomm.platform = "sa8775p";

    boot.kernelModules = [
      # Ethernet (QPS615 PCIe switch + STMMAC)
      "tc956x_pcie_eth"
      "dwmac_qcom_ethqos"
      # WiFi (ath11k WCN6855)
      "ath11k"
      "ath11k_pci"
      # Audio
      "snd_soc_qcom_common"
      "soundwire_qcom"
    ];
  };
}
