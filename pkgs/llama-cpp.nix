# llama.cpp with Hexagon HTP + Adreno OpenCL backends for Qualcomm acceleration.
# Cross-compiled from x86_64 to aarch64 so Hexagon SDK tools run natively on build host.
# - Hexagon: x86_64 SDK cross-compiles DSP skel libs loaded via FastRPC at runtime.
# - OpenCL: Adreno-optimized kernels, links against Qualcomm's libOpenCL.so at runtime.
{ lib
, stdenv
, buildPackages
, fetchFromGitHub
, fetchurl
, cmake
, curl
, python3
, opencl-headers
, ocl-icd
, hexagon-sdk
}:

let
  hexagonToolsRoot = "${hexagon-sdk}/tools/HEXAGON_Tools/19.0.07";
  rev = "af6528e6df5d798f7f1363ec1141699be0f638e2";

  # Pre-fetched UI assets (sandbox blocks network access during build)
  ui-assets = {
    "bundle.css" = fetchurl {
      url = "https://huggingface.co/buckets/ggml-org/llama-ui/resolve/latest/bundle.css";
      hash = "sha256-3nWNsbQkNyGrZwfudP5uEEk/2OEOSq6rIoYWUYnBoTc=";
    };
    "bundle.js" = fetchurl {
      url = "https://huggingface.co/buckets/ggml-org/llama-ui/resolve/latest/bundle.js";
      hash = "sha256-2Xn6ntXVbA7kyi87+otXPQY7ZxFjkrFU92fVUf8rjos=";
    };
    "index.html" = fetchurl {
      url = "https://huggingface.co/buckets/ggml-org/llama-ui/resolve/latest/index.html";
      hash = "sha256-PqVtrGlFbswvMa2E2ekSFVrjfyR6JI1/KBB6Ita8SvM=";
    };
    "loading.html" = fetchurl {
      url = "https://huggingface.co/buckets/ggml-org/llama-ui/resolve/latest/loading.html";
      hash = "sha256-JQAFfjmrgVGNFrKPXQGfYQe1irtHsqMNM4YtnntwPNw=";
    };
  };
in
stdenv.mkDerivation {
  pname = "llama-cpp";
  version = "0-unstable-2026-05-31";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    inherit rev;
    hash = "sha256-rWOhgQUOtpF6KhHuGnY9iFj6YiSjiscGGdwMFji8gwo=";
  };

  patches = [ ];

  nativeBuildInputs = [ cmake python3 ];
  buildInputs = [ curl opencl-headers ocl-icd ];

  postUnpack = ''
    mkdir -p $sourceRoot/tools/ui/dist
    cp ${ui-assets."bundle.css"} $sourceRoot/tools/ui/dist/bundle.css
    cp ${ui-assets."bundle.js"} $sourceRoot/tools/ui/dist/bundle.js
    cp ${ui-assets."index.html"} $sourceRoot/tools/ui/dist/index.html
    cp ${ui-assets."loading.html"} $sourceRoot/tools/ui/dist/loading.html
  '';

  cmakeFlags = [
    "-DLLAMA_BUILD_SERVER=ON"
    "-DLLAMA_BUILD_EXAMPLES=OFF"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DLLAMA_BUILD_TOOLS=ON"
    "-DLLAMA_BUILD_APP=ON"
    "-DLLAMA_BUILD_NUMBER=0"
    "-DLLAMA_BUILD_COMMIT=${rev}"
    "-DLLAMA_BUILD_UI=ON"
    "-DLLAMA_USE_PREBUILT_UI=ON"
    "-DHOST_CXX_COMPILER=${buildPackages.stdenv.cc}/bin/c++"
    "-DLLAMA_CURL=ON"
    "-DBUILD_SHARED_LIBS=ON"
    # Cross-compile: disable NATIVE (try_run fails), set ARM features explicitly
    "-DGGML_NATIVE=OFF"
    "-DCMAKE_C_FLAGS=-march=armv8.2-a+fp16+dotprod"
    "-DCMAKE_CXX_FLAGS=-march=armv8.2-a+fp16+dotprod"
    "-DGGML_BLAS=OFF"
    "-DGGML_VULKAN=OFF"
    "-DGGML_OPENCL=ON"
    "-DGGML_OPENCL_USE_ADRENO_KERNELS=ON"
    "-DGGML_HEXAGON=ON"
    "-DGGML_HEXAGON_FP32_QUANTIZE_GROUP_SIZE=128"
    "-DGGML_CUDA=OFF"
    "-DGGML_METAL=OFF"
    "-DGGML_OPENMP=OFF"
    "-DGGML_LLAMAFILE=OFF"
    "-DLLAMA_OPENSSL=OFF"
    "-DHEXAGON_SDK_ROOT=${hexagon-sdk}"
    "-DHEXAGON_TOOLS_ROOT=${hexagonToolsRoot}"
    "-DPREBUILT_LIB_DIR=UbuntuARM_aarch64"
  ];

  meta = with lib; {
    description = "LLM inference server with Hexagon HTP + Adreno OpenCL (llama.cpp)";
    homepage = "https://github.com/ggml-org/llama.cpp";
    license = licenses.mit;
    platforms = [ "aarch64-linux" ];
    mainProgram = "llama-server";
  };
}
