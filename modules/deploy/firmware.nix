# IQ-9075 EVK flashable-image firmware (qdl bundle).
#
# Assembles the bootloader / NHLOS / CDT / DTB / UFS-provision blobs that qdl
# needs to flash the EVK in EDL mode.  Runtime DSP firmware is handled
# separately by the hardware.qualcomm.firmware module.
#
# Enable with: hardware.qualcomm.iq-9075-evk.firmware.enable = true;
# Exposes:     config.system.build.firmware
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.iq-9075-evk.firmware;

  provision-xml = pkgs.writeText "provision_1_1.xml" ''
    <?xml version="1.0" ?>
    <data>
        <ufs bNumberLU="0" bBootEnable="1" bDescrAccessEn="1" bInitPowerMode="1" bHighPriorityLUN="0x5" bSecureRemovalType="0" bInitActiveICCLevel="0" wPeriodicRTCUpdate="0" bConfigDescrLock="0" bWriteBoosterBufferPreserveUserSpaceEn="1" bWriteBoosterBufferType="1" shared_wb_buffer_size_in_kb="4194304" />

        <ufs LUNum="0" bLUEnable="1" bBootLunID="0" size_in_kb="4096"       bDataReliability="0" bLUWriteProtect="0" bMemoryType="0" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 0 - HLOS (NixOS) - grows to fill" />
        <ufs LUNum="1" bLUEnable="1" bBootLunID="1" size_in_kb="16416"    bDataReliability="0" bLUWriteProtect="1" bMemoryType="3" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 1 - Boot LUN A, 16MB" />
        <ufs LUNum="2" bLUEnable="1" bBootLunID="2" size_in_kb="16416"    bDataReliability="0" bLUWriteProtect="1" bMemoryType="3" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 2 - Boot LUN B, 16MB" />
        <ufs LUNum="3" bLUEnable="1" bBootLunID="0" size_in_kb="32768"    bDataReliability="0" bLUWriteProtect="1" bMemoryType="0" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 3 - OTP LUN, 32MB" />
        <ufs LUNum="4" bLUEnable="1" bBootLunID="0" size_in_kb="35000000"  bDataReliability="0" bLUWriteProtect="1" bMemoryType="0" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 4 - NHLOS firmware" />
        <ufs LUNum="5" bLUEnable="1" bBootLunID="0" size_in_kb="4096"       bDataReliability="0" bLUWriteProtect="0" bMemoryType="0" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 5 - unused (minimal)" />
        <ufs LUNum="6" bLUEnable="1" bBootLunID="0" size_in_kb="4096"       bDataReliability="0" bLUWriteProtect="0" bMemoryType="0" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 6 - unused (minimal)" />
        <ufs LUNum="7" bLUEnable="1" bBootLunID="0" size_in_kb="4096"       bDataReliability="0" bLUWriteProtect="0" bMemoryType="0" bLogicalBlockSize="0x0c" bProvisioningType="2" wContextCapabilities="0" wb_buffer_size_in_kb="0" desc="LU 7 - unused (minimal)" />

        <ufs LUNtoGrow="0" commit="1"/>

    </data>
  '';

  firmware = pkgs.runCommand "evk-firmware" { } ''
    mkdir -p $out $out/sail_nor

    # === UFS firmware (main flash) ===
    cp ${cfg.nhlosBins}/prog_firehose_ddr.elf $out/
    cp ${cfg.nhlosBins}/*.mbn $out/
    cp ${cfg.nhlosBins}/*.elf $out/ 2>/dev/null || true
    cp ${cfg.nhlosBins}/tools.fv $out/
    cp ${cfg.nhlosBins}/gpt_*.bin $out/

    # Flash descriptors for LUN 1-4 (Boot A, Boot B, OTP, NHLOS)
    cp ${cfg.nhlosBins}/rawprogram1.xml $out/
    cp ${cfg.nhlosBins}/rawprogram2.xml $out/
    cp ${cfg.nhlosBins}/rawprogram3.xml $out/
    cp ${cfg.nhlosBins}/rawprogram4.xml $out/
    cp ${cfg.nhlosBins}/patch1.xml $out/
    cp ${cfg.nhlosBins}/patch2.xml $out/
    cp ${cfg.nhlosBins}/patch3.xml $out/
    cp ${cfg.nhlosBins}/patch4.xml $out/
    cp ${cfg.nhlosBins}/zeros_*.bin $out/

    # Device tree partition image (goes to dtb_a and dtb_b on NHLOS LUN 4)
    cp ${cfg.dtbBin} $out/dtb.bin

    # CDT (Configuration Data Table) for IQ-9075 EVK board identification
    cp ${cfg.cdtZip}/LEMANSAU_IOT_0.1.0.bin $out/
    rm -f $out/rawprogram3.xml $out/patch3.xml $out/gpt_main3.bin $out/gpt_backup3.bin
    cp ${cfg.cdtZip}/rawprogram3.xml $out/
    cp ${cfg.cdtZip}/patch3.xml $out/
    cp ${cfg.cdtZip}/gpt_main3.bin $out/
    cp ${cfg.cdtZip}/gpt_backup3.bin $out/

    # === SPI-NOR firmware (RTSS / Safety Island) ===
    cp ${cfg.nhlosBins}/sail_nor/prog_firehose_ddr.elf $out/sail_nor/
    cp ${cfg.nhlosBins}/sail_nor/rawprogram0.xml $out/sail_nor/
    cp ${cfg.nhlosBins}/sail_nor/patch0.xml $out/sail_nor/
    cp ${cfg.nhlosBins}/sail_nor/*.elf $out/sail_nor/ 2>/dev/null || true
    cp ${cfg.nhlosBins}/sail_nor/gpt_*.bin $out/sail_nor/
    cp ${cfg.nhlosBins}/sail_nor/zeros_*.bin $out/sail_nor/

    # UFS provisioning
    cp ${provision-xml} $out/provision_1_1.xml
  '';
in
{
  options.hardware.qualcomm.iq-9075-evk.firmware = {
    enable = lib.mkEnableOption "IQ-9075 EVK qdl firmware bundle (system.build.firmware)";

    nhlosBins = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchzip {
        url = "https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/ubuntu-fw/QCS9100/QLI.1.7-Ver.1.1/QLI.1.7-Ver.1.1-ubuntu-QCS9100-nhlos-bins.tar.gz";
        hash = "sha256-rr/yKcFS9Lc2aASeOx/OVuEEelfTFbRrj8T30H6a4Is=";
      };
      description = "NHLOS firmware archive (bootloader, TZ, hypervisor, etc.) for qdl flashing.";
    };

    cdtZip = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchzip {
        url = "https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS9100/cdt/qcs9075-iq-9075-evk.zip";
        hash = "sha256-HfYBWVb4xRZLuPwXqzWEsJMwMOIYWJhekcrColQKjJY=";
        stripRoot = false;
      };
      description = "CDT (Configuration Data Table) zip for IQ-9075 EVK board identification.";
    };

    dtbBin = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "https://people.canonical.com/~platform/images/qualcomm-iot/ubuntu-24.04/ubuntu-24.04-x10/ubuntu-desktop-24.04/dtb.bin";
        hash = "sha256-8oUR+oB9pMNMU4238QPq5e76Nr3lZawjn2QqiSRHAoY=";
      };
      description = "Device tree partition image (FAT16 containing combined-dtb.dtb).";
    };
  };

  config = lib.mkIf cfg.enable {
    system.build.firmware = firmware;
  };
}
