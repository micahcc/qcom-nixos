# Qualcomm AI Runtime (QNN SDK) - for Hexagon DSP and Adreno GPU inference
# Includes Genie LLM runtime for running models like DeepSeek on Hexagon HTP
# QCM6490/QCS9100 uses Hexagon v69
{ lib, stdenv, fetchurl, autoPatchelfHook, unzip }:

stdenv.mkDerivation rec {
  pname = "qnn-sdk";
  # Pinned to match qairt-dsp-binaries shipped on the Ubuntu PPA. Mismatching
  # host (libQnnHtp*) and DSP-side (libQnnHtpV73Skel) versions is rejected at
  # runtime: "Skel lib id mismatch: expected (vX.Y), detected (vA.B)".
  version = "2.45.0.260326";

  src = fetchurl {
    url = "https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/${version}/v${version}.zip";
    hash = "sha256-/6al1usL4oRt4vpPvrE4nvkaG5LviUzc04ytZu18yrc=";
  };

  nativeBuildInputs = [ unzip autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  # libcdsprpc.so is Qualcomm's FastRPC library, only available at runtime on device
  autoPatchelfIgnoreMissingDeps = [ "libcdsprpc.so" ];

  sourceRoot = ".";

  unpackPhase = ''
    unzip $src
  '';

  installPhase = ''
    local sdkdir=qairt/${version}

    # Host libraries (OE Linux GCC 11.2 - best ABI match for NixOS)
    mkdir -p $out/lib
    cp $sdkdir/lib/aarch64-oe-linux-gcc11.2/*.so $out/lib/

    # Hexagon v69 DSP libraries (loaded onto CDSP via FastRPC)
    mkdir -p $out/lib/hexagon-v69
    cp $sdkdir/lib/hexagon-v69/unsigned/*.so $out/lib/hexagon-v69/

    # Binaries (Genie LLM runtime + QNN tools)
    mkdir -p $out/bin
    cp $sdkdir/bin/aarch64-oe-linux-gcc11.2/* $out/bin/

    # Headers (QNN API + Genie API)
    mkdir -p $out/include
    cp -a $sdkdir/include/* $out/include/

    # Hexagon skel libs need to be in a known path at runtime
    # QNN looks for them via ADSP_LIBRARY_PATH or LD_LIBRARY_PATH
    mkdir -p $out/lib/dsp
    cp $sdkdir/lib/hexagon-v69/unsigned/*.so $out/lib/dsp/
  '';

  # Don't try to patch Hexagon DSP ELF binaries (they're QDSP6 arch, not aarch64).
  # autoPatchelf runs on all outputs; move DSP libs out, patch, move back.
  preFixup = ''
    # Temporarily hide Hexagon ELFs from autoPatchelf
    mv $out/lib/hexagon-v69 $out/lib/.hexagon-v69-hide
    mv $out/lib/dsp $out/lib/.dsp-hide
  '';

  postFixup = ''
    # Restore Hexagon DSP libraries
    mv $out/lib/.hexagon-v69-hide $out/lib/hexagon-v69
    mv $out/lib/.dsp-hide $out/lib/dsp
  '';

  meta = with lib; {
    description = "Qualcomm AI Runtime (QNN) SDK with Genie LLM runtime for Hexagon HTP inference";
    homepage = "https://www.qualcomm.com/developer/software/qualcomm-ai-engine-direct-sdk";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
