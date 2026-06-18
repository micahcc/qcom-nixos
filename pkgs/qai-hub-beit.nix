# BEiT image classifier as a QNN DLC (w8a16 quantized) for Hexagon HTP.
#
# Source: Qualcomm AI Hub (https://aihub.qualcomm.com/models/beit), publicly
# distributed via Hugging Face's release_assets.json which points at S3.
# Includes 1000 ImageNet labels and metadata describing the input/output
# tensor shapes and quantization parameters.
{ stdenv, lib, fetchurl, unzip }:

stdenv.mkDerivation {
  pname = "qai-hub-beit-w8a16";
  version = "v0.56.0";

  src = fetchurl {
    url = "https://qaihub-public-assets.s3.us-west-2.amazonaws.com/qai-hub-models/models/beit/releases/v0.56.0/beit-qnn_dlc-w8a16.zip";
    hash = "sha256-d+0d0LyPGj7H3p3IWT80EWNTKfcZ/0L2xcx30qvVJUQ=";
  };

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/beit
    unzip -j $src -d $out/share/beit
    runHook postInstall
  '';

  meta = with lib; {
    description = "BEiT ImageNet classifier as QNN DLC (w8a16) for Hexagon HTP v73";
    homepage = "https://aihub.qualcomm.com/models/beit";
    license = licenses.unfree;  # Qualcomm AI Hub model license
    platforms = platforms.all;
  };
}
