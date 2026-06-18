# Qualcomm package overlay.
#
# Adds Qualcomm-specific packages under `pkgs.qualcomm.*`. Generic packages
# (qrtr, pd-mapper, qcom-vendor-libs, qcom-fastrpc, tqftpserv) work on any
# Qualcomm SoC. Platform-specific packages (linux-qcom, dragonwing-firmware,
# qairt-dsp-binaries, qnn-sdk) are currently SA8775P-tuned.
final: prev:
let
  callPackage = prev.callPackage;
in
{
  qualcomm = (prev.qualcomm or {}) // {
    # Generic Qualcomm userspace
    qrtr            = callPackage ./pkgs/qrtr.nix {};
    pd-mapper       = callPackage ./pkgs/pd-mapper.nix { qrtr = final.qualcomm.qrtr; };
    tqftpserv       = callPackage ./pkgs/tqftpserv.nix { qrtr = final.qualcomm.qrtr; };
    qcom-vendor-libs = callPackage ./pkgs/qcom-vendor-libs.nix {};
    qcom-fastrpc    = callPackage ./pkgs/qcom-fastrpc.nix {
      qcom-vendor-libs = final.qualcomm.qcom-vendor-libs;
    };

    # SA8775P / IQ-9075 EVK platform
    linux-qcom         = callPackage ./pkgs/linux-qcom.nix {};
    dragonwing-firmware = callPackage ./pkgs/dragonwing-firmware.nix {};
    qairt-dsp-binaries  = callPackage ./pkgs/qairt-dsp-binaries.nix {};
    qnn-sdk             = callPackage ./pkgs/qnn-sdk.nix {};

    # AI Hub model (publicly fetched from huggingface/qaihub-public-assets)
    qai-hub-beit = callPackage ./pkgs/qai-hub-beit.nix {};

    # End-to-end DSP test apps
    dsp-smoketest = callPackage ./pkgs/dsp-smoketest.nix {
      inherit (final.qualcomm) qnn-sdk qcom-vendor-libs qairt-dsp-binaries dragonwing-firmware;
    };
    dsp-imagenet-test = callPackage ./pkgs/dsp-imagenet-test.nix {
      inherit (final.qualcomm) qnn-sdk qcom-vendor-libs qairt-dsp-binaries
                               dragonwing-firmware qai-hub-beit;
    };
  } // prev.lib.optionalAttrs prev.stdenv.buildPlatform.isx86_64 {
    # x86_64-only — Hexagon SDK is a cross-compiler for the host. llama-cpp
    # is also exposed only on x86_64 build hosts because it needs hexagon-sdk
    # at build time (the resulting binary still targets aarch64).
    hexagon-sdk = callPackage ./pkgs/hexagon-sdk.nix {};
    llama-cpp = (prev.pkgsCross.aarch64-multiplatform.callPackage ./pkgs/llama-cpp.nix {
      hexagon-sdk = callPackage ./pkgs/hexagon-sdk.nix {};
    });
  };
}
