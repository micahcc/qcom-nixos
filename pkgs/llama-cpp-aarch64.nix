# llama.cpp with the Adreno OpenCL backend for Qualcomm aarch64 systems.
# This target-native variant intentionally omits the x86_64-hosted Hexagon SDK.
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
}:

let
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

  nativeBuildInputs = [ cmake python3 nodejs ];
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
    "-DGGML_NATIVE=OFF"
    "-DCMAKE_C_FLAGS=-march=armv8.2-a+fp16+dotprod"
    "-DCMAKE_CXX_FLAGS=-march=armv8.2-a+fp16+dotprod"
    "-DGGML_BLAS=OFF"
    "-DGGML_VULKAN=OFF"
    "-DGGML_OPENCL=ON"
    "-DGGML_OPENCL_USE_ADRENO_KERNELS=ON"
    "-DGGML_HEXAGON=OFF"
    "-DGGML_CUDA=OFF"
    "-DGGML_METAL=OFF"
    "-DGGML_OPENMP=OFF"
    "-DGGML_LLAMAFILE=OFF"
    "-DLLAMA_OPENSSL=OFF"
  ];

  meta = with lib; {
    description = "LLM inference server with Adreno OpenCL (llama.cpp)";
    homepage = "https://github.com/ggml-org/llama.cpp";
    license = licenses.mit;
    platforms = [ "aarch64-linux" ];
    mainProgram = "llama-server";
  };
}
