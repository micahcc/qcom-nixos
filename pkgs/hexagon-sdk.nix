# Qualcomm Hexagon SDK (trimmed, community edition)
# Provides hexagon-clang cross-compiler, QURT RTOS libs, and FastRPC headers
# for building DSP skel libraries that run on Hexagon HTP.
# x86_64 only — runs on the build host during cross-compilation.
{ lib, stdenv, fetchurl, autoPatchelfHook, zlib, gmp }:

stdenv.mkDerivation {
  pname = "hexagon-sdk";
  version = "6.6.0.0";

  src = fetchurl {
    url = "https://github.com/snapdragon-toolchain/hexagon-sdk/releases/download/v6.6.0.0/hexagon-sdk-v6.6.0.0-amd64-lnx.tar.xz";
    hash = "sha256-SpFuQsHaue/fLlh3P5Aep4D6Q8kHvwVKt2Vyo7PZQvQ=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib zlib gmp ];

  sourceRoot = "6.6.0.0";

  # Don't try to patch Hexagon target libraries (they're QDSP6 arch, not x86_64)
  autoPatchelfIgnoreMissingDeps = true;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    cp -a . $out/

    # Ensure hexagon-clang is executable
    chmod +x $out/tools/HEXAGON_Tools/19.0.07/Tools/bin/*
  '';

  # Only patch x86_64 host binaries, not hexagon target libs
  preFixup = ''
    # Hide non-x86_64 ELFs from autoPatchelf
    find $out/rtos -name "*.a" -o -name "*.o" | while read f; do
      chmod 444 "$f" 2>/dev/null || true
    done
  '';

  meta = with lib; {
    description = "Qualcomm Hexagon SDK with cross-compiler for DSP development";
    homepage = "https://github.com/snapdragon-toolchain/hexagon-sdk";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
