# BEiT image classifier as a QNN DLC (w8a16 quantized) for Hexagon HTP.
#
# Source: Qualcomm AI Hub (https://aihub.qualcomm.com/models/beit), publicly
# distributed via Hugging Face's release_assets.json which points at S3.
# Includes 1000 ImageNet labels and metadata describing the input/output
# tensor shapes and quantization parameters.
#
# Uses fetchzip so the hash is over the unpacked tree rather than the zip
# bytes — Qualcomm occasionally repacks the archive (zip metadata
# timestamps change) and a fetchurl hash would break.
{ stdenv, lib, fetchzip }:

stdenv.mkDerivation {
  pname = "qai-hub-beit-w8a16";
  version = "v0.56.0";

  src = fetchzip {
    url = "https://qaihub-public-assets.s3.us-west-2.amazonaws.com/qai-hub-models/models/beit/releases/v0.56.0/beit-qnn_dlc-w8a16.zip";
    hash = "sha256-frzxQDuWGHYTjsNlgqakle9SocGtXl5OrlzEV70XiTk=";
    stripRoot = true;
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/beit
    cp -a $src/. $out/share/beit/
    runHook postInstall
  '';

  meta = with lib; {
    description = "BEiT ImageNet classifier as QNN DLC (w8a16) for Hexagon HTP v73";
    homepage = "https://aihub.qualcomm.com/models/beit";
    license = licenses.unfree;  # Qualcomm AI Hub model license
    platforms = platforms.all;
  };
}
