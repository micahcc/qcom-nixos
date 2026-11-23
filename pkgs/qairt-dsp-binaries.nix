# QNN AI Runtime DSP binaries (skel libraries for HTP inference on CDSP)
# From Ubuntu's qcom-ppa qairt-sdk source package
{ lib, stdenv, fetchurl, dpkg }:

stdenv.mkDerivation {
  pname = "qairt-dsp-binaries";
  version = "2.49.0";

  src = fetchurl {
    url = "https://ppa.launchpadcontent.net/ubuntu-qcom-iot/qcom-ppa/ubuntu/pool/main/q/qairt-sdk/qairt-dsp-binaries_2.49.0-0ubuntu1~bpo24.04.2_arm64.deb";
    name = "qairt-dsp-binaries.deb";
    hash = "sha256-Al0CXaibDYcvpBs0eX47H4KdsYQuU542gN5j7RbD6DE=";
  };

  nativeBuildInputs = [ dpkg ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    mkdir -p $out/share/qcom
    cp -a usr/share/qcom/* $out/share/qcom/
  '';

  meta = with lib; {
    description = "Qualcomm AI Runtime SDK - DSP binaries (HTP skel libraries)";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
