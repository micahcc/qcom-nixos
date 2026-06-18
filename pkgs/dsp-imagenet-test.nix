# DSP imagenet inference test.
#
# Runs a quantized ImageNet classifier (BEiT w8a16, supplied at runtime via
# `--model`) on the Hexagon HTP backend through `qnn-net-run`, decodes the
# raw uint16 logits against the bundled ImageNet labels, and prints the top-5
# predicted classes. Exits 0 on a successful inference.
#
# This proves the end-to-end QNN HTP path works, beyond the calculator
# smoketest in dsp-smoketest.nix. Use a real 224×224×3 input image (or any
# uint16 LE blob of 301056 bytes) — sample data should be supplied by the
# caller.
{ stdenv, lib, makeWrapper, python3, qnn-sdk, qcom-vendor-libs
, qairt-dsp-binaries, dragonwing-firmware, qai-hub-beit }:

let
  ride = "share/qcom/sa8775p/Qualcomm/SA8775P-RIDE/dsp/cdsp";

  runner = ./dsp-imagenet-test.py;
in
stdenv.mkDerivation {
  pname = "qcom-dsp-imagenet-test";
  version = "1";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  installPhase = ''
    mkdir -p $out/bin
    install -m 0755 ${runner} $out/bin/.qcom-dsp-imagenet-test-impl
    sed -i "1c#!${python3.interpreter}" $out/bin/.qcom-dsp-imagenet-test-impl
    makeWrapper $out/bin/.qcom-dsp-imagenet-test-impl $out/bin/qcom-dsp-imagenet-test \
      --set QCOM_DSP_IMAGENET_LABELS "${qai-hub-beit}/share/beit/labels.txt" \
      --set QCOM_DSP_IMAGENET_MODEL "${qai-hub-beit}/share/beit/beit.dlc" \
      --set QCOM_DSP_IMAGENET_QNN_NET_RUN "${qnn-sdk}/bin/qnn-net-run" \
      --set QCOM_DSP_IMAGENET_BACKEND "${qnn-sdk}/lib/libQnnHtp.so" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ qcom-vendor-libs qnn-sdk ]} \
      --set ADSP_LIBRARY_PATH "/run/qcom-dsp:${dragonwing-firmware}/${ride}:${qairt-dsp-binaries}/${ride}" \
      --set DSP_LIBRARY_PATH  "/run/qcom-dsp:${dragonwing-firmware}/${ride}:${qairt-dsp-binaries}/${ride}"
  '';

  meta = with lib; {
    description = "Run an ImageNet classifier on Hexagon HTP and print top-5 predictions";
    platforms = [ "aarch64-linux" ];
    license = licenses.mit;  # this wrapper. Bundled qnn-sdk / DSP binaries / model unfree.
  };
}
