# DSP smoketest: thin wrapper around `qnn-platform-validator --backend dsp
# --testBackend`, with the runtime library paths baked in.
#
# Exits 0 if the calculator skel test passes (host-side `libQnnHtpV73CalculatorStub.so`
# successfully invokes the DSP-side calculator). This is the canonical
# end-to-end DSP smoketest — proves `libcdsprpc.so` can open a session,
# load a DSP library, and execute code on the Hexagon.
{ stdenv, lib, makeWrapper, qnn-sdk, qcom-vendor-libs, qairt-dsp-binaries, dragonwing-firmware }:

let
  ride = "share/qcom/sa8775p/Qualcomm/SA8775P-RIDE/dsp/cdsp";
in
stdenv.mkDerivation {
  pname = "qcom-dsp-smoketest";
  version = "1";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${qnn-sdk}/bin/qnn-platform-validator $out/bin/qcom-dsp-smoketest \
      --add-flags "--backend dsp --testBackend" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ qcom-vendor-libs qnn-sdk ]} \
      --set ADSP_LIBRARY_PATH "/run/qcom-dsp:${dragonwing-firmware}/${ride}:${qairt-dsp-binaries}/${ride}" \
      --set DSP_LIBRARY_PATH  "/run/qcom-dsp:${dragonwing-firmware}/${ride}:${qairt-dsp-binaries}/${ride}"
  '';

  meta = with lib; {
    description = "Qualcomm Hexagon DSP smoketest (calculator on CDSP via QNN)";
    platforms = [ "aarch64-linux" ];
    license = licenses.mit;  # this wrapper. Bundled qnn-sdk / DSP binaries unfree.
  };
}
