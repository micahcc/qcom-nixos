# llama.cpp with Hexagon HTP + Adreno OpenCL backends for Qualcomm acceleration.
# Cross-compiled from x86_64 to aarch64 so Hexagon SDK tools run natively on build host.
# - Hexagon: x86_64 SDK cross-compiles DSP skel libs loaded via FastRPC at runtime.
# - OpenCL: Adreno-optimized kernels, links against Qualcomm's libOpenCL.so at runtime.
{ lib
, stdenv
, buildPackages
, fetchFromGitHub
, cmake
, nodejs
, curl
, python3
, opencl-headers
, ocl-icd
, hexagon-sdk
}:

let
  hexagonToolsRoot = "${hexagon-sdk}/tools/HEXAGON_Tools/19.0.07";
  rev = "af6528e6df5d798f7f1363ec1141699be0f638e2";
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

  nativeBuildInputs = [ cmake python3 nodejs hexagon-sdk ];
  buildInputs = [ curl opencl-headers ocl-icd ];

  cmakeFlags = [
    "-DLLAMA_BUILD_SERVER=ON"
    "-DLLAMA_BUILD_EXAMPLES=OFF"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DLLAMA_BUILD_TOOLS=ON"
    "-DLLAMA_BUILD_APP=ON"
    "-DLLAMA_BUILD_NUMBER=0"
    "-DLLAMA_BUILD_COMMIT=${rev}"
    "-DLLAMA_BUILD_UI=ON"
    "-DLLAMA_USE_PREBUILT_UI=OFF"
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
