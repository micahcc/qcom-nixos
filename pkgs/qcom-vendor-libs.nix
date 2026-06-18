# Qualcomm vendor userspace libraries extracted from the Ubuntu PPA.
# These are binary blobs needed at runtime for Adreno OpenCL and Hexagon FastRPC.
# Source: ppa:ubuntu-qcom-iot/qcom-ppa (noble/arm64)
{ lib, stdenv, fetchurl, autoPatchelfHook, glib, zlib, zstd }:

let
  ppaBase = "https://ppa.launchpadcontent.net/ubuntu-qcom-iot/qcom-ppa/ubuntu/pool/main/q";

  srcs = {
    fastrpc = fetchurl {
      url = "${ppaBase}/qcom-fastrpc/qcom-fastrpc1_1.0.15+repack2_arm64.deb";
      hash = "sha256-DRBFZbihxZFWT+DuPt4qX/KFF52dcVF++8qX/QDUimA=";
    };
    dmabufheap = fetchurl {
      url = "${ppaBase}/qcom-libdmabufheap/qcom-libdmabufheap_1.1.0+250131+rel1.0+nmu1_arm64.deb";
      hash = "sha256-K/IyV6rfi9Me1qsoOWbtX7Nj8ISnax9//LkDXNiOW+0=";
    };
    adreno-cl = fetchurl {
      url = "${ppaBase}/qcom-adreno/qcom-adreno-cl1_1.838.5~1+repack3-0ubuntu1_arm64.deb";
      hash = "sha256-WqszQj3wiJV1XYoUyIxIUP7/a8J7Lv0LBnSAVipWEdM=";
    };
    property-vault = fetchurl {
      url = "${ppaBase}/qcom-property-vault/qcom-property-vault_1.1.0-0ubuntu1_arm64.deb";
      hash = "sha256-8NrSO36hBb8nkGdeA4sg17RplFM/5U0heAcrHC25U7E=";
    };
  };
in
stdenv.mkDerivation {
  pname = "qcom-vendor-libs";
  version = "2024.11";

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook zstd ];
  buildInputs = [ stdenv.cc.cc.lib glib zlib ];

  # Some libs reference other Qualcomm libs we bundle together
  autoPatchelfIgnoreMissingDeps = [
    "libproperty_vault.so"
    "libdmabufheap.so"
  ];

  installPhase = ''
    mkdir -p $out/lib

    for deb in ${srcs.fastrpc} ${srcs.dmabufheap} ${srcs.adreno-cl} ${srcs.property-vault}; do
      ar x "$deb"
      tar xf data.tar* -C $out
      rm -f data.tar* control.tar* debian-binary
    done

    # Flatten libs into $out/lib
    find $out -name "*.so*" -exec mv -t $out/lib {} + 2>/dev/null || true
    # Clean up extracted directory structure
    rm -rf $out/usr $out/etc $out/var 2>/dev/null || true

    # Create unversioned symlinks (llama.cpp dlopen's "libcdsprpc.so" without version)
    cd $out/lib
    for f in *.so.*.*.*; do
      base="''${f%%.*}"
      ln -sf "$f" "''${base}.so" 2>/dev/null || true
    done
  '';

  meta = with lib; {
    description = "Qualcomm vendor userspace libraries (FastRPC, Adreno OpenCL)";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
