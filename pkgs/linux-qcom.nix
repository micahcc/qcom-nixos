# Ubuntu's linux-qcom kernel for Qualcomm QCS9100/IQ-9075 platforms
# Source: https://ppa.launchpadcontent.net/ubuntu-qcom-iot/qcom-ppa/ubuntu
#
# Uses Ubuntu's annotations system to generate the exact .config they ship.
# Must build with GCC 13 to match Ubuntu's toolchain.
{ lib, fetchurl, buildLinux, runCommand, quilt, python3, gcc13Stdenv, ... }@args:

let
  # The PPA source package is named 6.8.0, but patches bump kernel to 6.8.12
  ppaVersion = "6.8.0";
  version = "6.8.12";
  debVersion = "1071.74";
  ppaBase = "https://ppa.launchpadcontent.net/ubuntu-qcom-iot/qcom-ppa/ubuntu/pool/main/l/linux-qcom";

  # Upstream kernel source
  origTarball = fetchurl {
    url = "${ppaBase}/linux-qcom_${ppaVersion}.orig.tar.gz";
    hash = "sha256-JlEhFZcr3wF6SsgmzH0+mwujl9T4XNMw5OT/VMeAYcg=";
  };

  # Debian source diff (contains debian/patches/ with quilt series)
  debianDiff = fetchurl {
    url = "${ppaBase}/linux-qcom_${ppaVersion}-${debVersion}.diff.gz";
    hash = "sha256-ADpuf7RTQjBwkbXsb/GtdMFGrFCbHGhZPBlxGyNOZ0M=";
  };

  # Patched kernel source: orig + debian patches applied via quilt
  patchedSrc = runCommand "linux-qcom-${version}-patched" {
    nativeBuildInputs = [ quilt ];
  } ''
    # Extract orig tarball
    tar xzf ${origTarball}
    cd linux-6.8

    # Apply debian diff to get debian/ directory
    gzip -dc ${debianDiff} | patch -p1

    # Apply all kernel patches from debian/patches/ using quilt
    export QUILT_PATCHES=debian/patches
    if [ -f debian/patches/series ]; then
      quilt push -a --fuzz=0
    fi

    # Clean up quilt state
    rm -rf .pc

    # Remove broken ubuntu/qcom subdirs (camera/graphics reference ION headers not in this tree)
    # Keep qps615 (tc956x PCIe Ethernet) which the EVK needs for wired networking
    rm -rf ubuntu/qcom/camera ubuntu/qcom/camera-qcm6490 ubuntu/qcom/camera-qcs8300 ubuntu/qcom/camera-qcs9100
    rm -rf ubuntu/qcom/graphics ubuntu/qcom/video
    # Rewrite Makefile to only build qps615
    cat > ubuntu/qcom/Makefile << 'QCOM_MK'
subdir-ccflags-y += -Wno-packed-bitfield-compat
subdir-ccflags-y += -Wno-enum-int-mismatch
obj-y += qps615/
QCOM_MK

    # Fix missing dt-bindings header: file exists at include/linux/ but DTS expects dt-bindings/arm/
    mkdir -p include/dt-bindings/arm
    cp include/linux/qcom_dma_heap_dt_constants.h include/dt-bindings/arm/

    # Remove upstream msm/ DRM driver - its XML register files are missing defines
    # that Ubuntu's patched a6xx_catalog.c references. msm_default/ is Ubuntu's working version.
    sed -i '\|obj-\$(CONFIG_DRM_MSM).*+= msm/$|d' drivers/gpu/drm/Makefile

    # Remove custom FORCE-based DTB rules that break dtbs_install (FORCE not available in install phase)
    sed -i '/FORCE/d' arch/arm64/boot/dts/qcom/Makefile
    sed -i '/if_changed,copy/d' arch/arm64/boot/dts/qcom/Makefile
    sed -i '/if_changed,cat/d' arch/arm64/boot/dts/qcom/Makefile
    sed -i '/quiet_cmd_cat\|cmd_cat = cat/d' arch/arm64/boot/dts/qcom/Makefile
    sed -i '/rb3gen2-ia-mezz-ovl\.dtb/d' arch/arm64/boot/dts/qcom/Makefile
    sed -i '/combined-dtb\.dtb/d' arch/arm64/boot/dts/qcom/Makefile

    cd ..
    mv linux-6.8 $out
  '';

  linuxArgs = {
    inherit version;
    modDirVersion = version;
    extraMeta.branch = "6.8";
    kernelPatches = [
      # NOTE: Do NOT add qseecom-sa8775p.patch — Ubuntu's kernel skips qseecom on
      # SA8775P ("untested machine") and CDSP0 works fine without it. Our patch caused
      # the SCM call to fail with -22, which poisoned CDSP0 boot (glink intent timeout).
    ];

    src = patchedSrc;

    # Let NixOS handle config generation normally (autoModules = true by default).
    # We only need structuredExtraConfig for Qualcomm-specific options and to disable
    # modules that reference APIs removed by Ubuntu's patches.
    ignoreConfigErrors = false;

    structuredExtraConfig = with lib.kernel; {
      # Match Ubuntu's scheduler/preemption settings. Full preemption + HZ=1000
      # is critical for CDSP fastrpc: qcom_sysmon sends notifications to DSPs
      # with a 5s timeout, and the kernel thread processing DSP responses must
      # be scheduled fast enough to avoid timeout. With HZ=250 + voluntary
      # preemption, the thread misses the window → sysmon timeout → fastrpc broken.
      HZ_1000 = lib.mkForce yes;
      HZ_250 = lib.mkForce (option no);
      HZ = lib.mkForce (freeform "1000");
      PREEMPT = lib.mkForce yes;
      PREEMPT_VOLUNTARY = lib.mkForce no;
      PREEMPT_DYNAMIC = lib.mkForce yes;
      SCHED_CLUSTER = yes;

      # Match Ubuntu: KASAN HW tags changes DMA allocation behavior,
      # MODVERSIONS adds CRC symbol versioning
      KASAN = lib.mkForce yes;
      KASAN_HW_TAGS = yes;
      MODVERSIONS = yes;

      # ACPI_HOTPLUG_CPU is a hidden bool (no prompt) auto-selected by deps.
      # NixOS base config tries to set it explicitly which fails. Override as optional.
      ACPI_HOTPLUG_CPU = lib.mkForce (option yes);

      # Disable modules broken by Ubuntu's patches (reference removed APIs/structs)
      # or that reference headers not present in this kernel tree
      PCI_EPF_TEST = no;
      SCSI_UFS_EXYNOS = no;
      WLAN_VENDOR_BCMDHD = no;
      CORESIGHT = no;
      PTP_QCOM_CLOCK_TSC = no;
      QCOM_WDT_CORE = yes;
      QTI_TZ_LOG = module;
      SENSORS_EMC2305 = yes;
      # Match Ubuntu settings for other SoC clock/pinctrl/interconnect drivers
      CLK_X1E80100_CAMCC = no;
      CLK_X1E80100_DISPCC = no;
      CLK_X1E80100_GCC = yes;
      CLK_X1E80100_GPUCC = no;
      PINCTRL_X1E80100 = yes;
      PINCTRL_SM8550 = yes;
      PINCTRL_SM8650 = yes;
      PINCTRL_SM7150 = module;
      SM_CAMCC_7150 = no;
      SM_DISPCC_7150 = no;
      SM_VIDEOCC_7150 = no;
      SND_SOC_X1E80100 = module;
      INTERCONNECT_QCOM_X1E80100 = yes;
      INTERCONNECT_QCOM_SM8550 = yes;
      INTERCONNECT_QCOM_SM8650 = yes;
      SM_CAMCC_8550 = module;
      SM_DISPCC_8550 = module;
      SM_DISPCC_8650 = yes;
      SM_GPUCC_8550 = module;
      SM_GPUCC_8650 = yes;

      # Ubuntu's qcom-rpmh-regulator calls devm_regulator_debug_register unconditionally
      REGULATOR_DEBUG_CONTROL = yes;

      # QCA8081 2.5G Ethernet PHY (on IQ-9075 EVK RJ45 port)
      QCA808X_PHY = yes;

      # QPS615 PCIe Ethernet switch (out-of-tree driver in ubuntu/qcom/qps615/)
      QCOM_QPS615_PCIE_SWITCH = yes;

      # TrustZone memory and secure communication
      QCOM_TZMEM_MODE_SHMBRIDGE = yes;
      QCOM_QSEECOM = yes;
      QCOM_QSEECOM_UEFISECAPP = yes;

      # Qualcomm Secure Invoke (SMCInvoke) - required for CDSP fastrpc on secured platforms
      QCOM_SCM_ADDON = yes;
      QCOM_SI_CORE = module;
      QCOM_SI_CORE_WQ = yes;
      QCOM_SI_CORE_MEM_OBJECT = module;
      QCOM_SI_CORE_XTS = module;

      # Secure buffer and memory sharing with TrustZone
      QCOM_SECURE_BUFFER = yes;
      QCOM_MEM_BUF = yes;
      QCOM_MEM_BUF_DEV = yes;

      # DMA-BUF heaps - needed for fastrpc buffer allocation
      DMABUF_HEAPS_SYSTEM = yes;
      QCOM_DMABUF_HEAPS = yes;
      QCOM_DMABUF_HEAPS_SYSTEM = yes;
      QCOM_DMABUF_HEAPS_CMA = yes;
      QCOM_DMABUF_HEAPS_SYSTEM_SECURE = yes;

      # Subsystem communication and remoteproc infrastructure
      QCOM_SSC_BLOCK_BUS = yes;
      QCOM_QMI_HELPERS = yes;
      QCOM_PDR_HELPERS = yes;
      QCOM_APR = yes;
      QCOM_SYSMON = module;
      QCOM_PIL_INFO = module;
      QCOM_RPROC_COMMON = module;
      REMOTEPROC_CDEV = yes;
      QCOM_FORCE_WDOG_BITE_ON_PANIC = yes;
      QCOM_WATCHDOG_IPI_PING = yes;
      QCOM_MEMORY_DUMP_V2 = yes;
      QCOM_SOC_DEBUG = yes;
      QCOM_DCC = yes;

      # Match Ubuntu y/m settings for platform drivers
      ARM_QCOM_CPUFREQ_NVMEM = module;
      ARM_SMMU_QCOM_DEBUG = yes;
      ARM_SMMU_QCOM_TBU = yes;
      ARM_SMMU_V3_SVA = yes;
      BACKLIGHT_QCOM_WLED = yes;
      CLK_QCOM_DEBUG = yes;
      DMABUF_HEAPS_CMA = yes;
      GUNYAH = yes;
      GUNYAH_QCOM_PLATFORM = yes;
      GUNYAH_VCPU = yes;
      GUNYAH_IRQFD = yes;
      GUNYAH_IOEVENTFD = yes;
      GUNYAH_DRIVERS = yes;
      I2C_QCOM_GENI = yes;
      INTERCONNECT_QCOM_QCS8300 = yes;
      MFD_I2C_PMIC = yes;
      QCOM_NET_PHYLIB = yes;
      QCOM_SOCINFO = yes;
      QCOM_SPM = yes;
      QCOM_TSENS = module;
      PHY_QCOM_QMP = yes;
      PHY_QCOM_QMP_PCIE = yes;
      PHY_QCOM_QMP_PCIE_8996 = yes;
      PHY_QCOM_QMP_UFS = yes;
      PHY_QCOM_QMP_USB = yes;
      PHY_QCOM_USB_SNPS_FEMTO_V2 = yes;
      REGULATOR_QCOM_PM8008 = yes;
      REGULATOR_QCOM_REFGEN = yes;
      SCSI_UFS_QCOM = yes;
      USB_DWC3_QCOM = module;
      RPMSG_NS = module;
      RPMSG_VIRTIO = module;

      # Match Ubuntu's settings to avoid the CDSP fastrpc ENOMEM race during
      # boot. The cdsp0-fix workaround that restarts CDSP after losing the
      # race leaves the DSP firmware in a state where sysmon/ssctl never
      # register, breaking fastrpc entirely. Better to prevent the race.
      #
      # FW_DEVLINK_SYNC_STATE_TIMEOUT: safety valve that forces sync_state()
      #   on suppliers that never get probed (e.g. LPASS pinctrl on this EVK
      #   stays in deferred-probe). Without it, ICC providers that CDSP
      #   depends on are blocked and the fastrpc probe runs in a degraded
      #   environment, hitting ENOMEM allocating glink intent buffers.
      FW_DEVLINK_SYNC_STATE_TIMEOUT = lib.mkForce yes;
      # REGULATOR_PROXY_CONSUMER: holds bootloader-on regulators ON until a
      # real consumer registers a vote. Without it (loaded as module after
      # qcom_q6v5_pas probes), DSP power rails can briefly glitch off,
      # corrupting firmware state.
      REGULATOR_PROXY_CONSUMER = lib.mkForce yes;
      # DEVFREQ governors built-in so interconnect bandwidth scaling is
      # available before CDSP firmware sends its first bandwidth request.
      DEVFREQ_GOV_PASSIVE = lib.mkForce yes;
      DEVFREQ_GOV_PERFORMANCE = lib.mkForce yes;
      DEVFREQ_GOV_POWERSAVE = lib.mkForce yes;
      # Match Ubuntu's CMA layout (7 areas of ~4.6MB instead of 19 of ~1.7MB)
      # so fastrpc's larger contiguous allocations don't fail with ENOMEM.
      CMA_AREAS = lib.mkForce (freeform "7");
    };

    # Use GCC 13 to match Ubuntu's build toolchain
    stdenv = gcc13Stdenv;

    # GCC 13.4 (NixOS) is stricter than 13.3 (Ubuntu) - these were warnings in 13.3
    extraMakeFlags = [
      "KCFLAGS=-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"
    ];

    extraMeta.platforms = [ "aarch64-linux" ];
  };

in
buildLinux (linuxArgs // (args.argsOverride or { }))
