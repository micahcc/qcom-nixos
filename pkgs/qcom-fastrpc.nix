# Qualcomm FastRPC userspace daemons (cdsprpcd, adsprpcd, gdsprpcd)
# These load the fastrpc shell onto DSPs and broker RPC requests.
# From Ubuntu's qcom-ppa: qcom-fastrpc1 package
{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, qcom-vendor-libs ? null }:

stdenv.mkDerivation {
  pname = "qcom-fastrpc";
  version = "1.0.15";

  src = fetchurl {
    url = "https://ppa.launchpadcontent.net/ubuntu-qcom-iot/qcom-ppa/ubuntu/pool/main/q/qcom-fastrpc/qcom-fastrpc1_1.0.15+repack2_arm64.deb";
    hash = "sha256-DRBFZbihxZFWT+DuPt4qX/KFF52dcVF++8qX/QDUimA=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook ];
  buildInputs = lib.optional (qcom-vendor-libs != null) qcom-vendor-libs;

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib
    cp usr/sbin/cdsprpcd $out/bin/
    cp usr/sbin/adsprpcd $out/bin/
    cp usr/sbin/gdsprpcd $out/bin/
    # Libraries (newer versions with cdsp1 support)
    cp usr/lib/aarch64-linux-gnu/libcdsprpc.so.1.0.0 $out/lib/libcdsprpc.so.1.0.0
    ln -s libcdsprpc.so.1.0.0 $out/lib/libcdsprpc.so.1
    ln -s libcdsprpc.so.1.0.0 $out/lib/libcdsprpc.so
    cp usr/lib/aarch64-linux-gnu/libcdsp_default_listener.so.1.0.0 $out/lib/libcdsp_default_listener.so.1.0.0
    ln -s libcdsp_default_listener.so.1.0.0 $out/lib/libcdsp_default_listener.so.1
    ln -s libcdsp_default_listener.so.1.0.0 $out/lib/libcdsp_default_listener.so
  '';

  meta = with lib; {
    description = "Qualcomm FastRPC userspace daemons";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
