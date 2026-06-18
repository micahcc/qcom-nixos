# Dragonwing runtime firmware (ADSP, CDSP, WiFi, GPU, FastRPC shells)
# From Ubuntu's qcom-ppa - provides DSP firmware and FastRPC shells for Hexagon
{ lib, stdenv, fetchurl, dpkg }:

stdenv.mkDerivation {
  pname = "linux-firmware-dragonwing";
  version = "1.0.0+20260324";

  src = fetchurl {
    url = "https://ppa.launchpadcontent.net/ubuntu-qcom-iot/qcom-ppa/ubuntu/pool/main/l/linux-firmware-dragonwing/linux-firmware-dragonwing_1.0.0+20260324_arm64.deb";
    hash = "sha256-YLsfreJNOI3Vdro22kWMdFUEkLHaO2iO74X26aNG+7s=";
  };

  nativeBuildInputs = [ dpkg ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    mkdir -p $out/lib/firmware
    # Deb uses usr/lib/firmware (usrmerge) — copy both locations
    if [ -d lib/firmware ]; then
      cp -a lib/firmware/* $out/lib/firmware/
    fi
    if [ -d usr/lib/firmware ]; then
      cp -a --no-clobber usr/lib/firmware/* $out/lib/firmware/
    fi
    # Move updates/ to top level so NixOS firmware merger picks them up.
    if [ -d $out/lib/firmware/updates ]; then
      cp -a --no-clobber $out/lib/firmware/updates/* $out/lib/firmware/
      rm -rf $out/lib/firmware/updates
    fi
    # Remove broken symlinks from the deb package
    find $out -xtype l -delete
    # Also install the FastRPC shells / DSP userspace
    if [ -d usr/share/qcom ]; then
      mkdir -p $out/share/qcom
      cp -a usr/share/qcom/* $out/share/qcom/
    fi

    # Install FastRPC shells into firmware directory so tqftpserv can serve them.
    # tqftpserv looks for files relative to the remoteproc firmware dirname
    # (e.g. qcom/sa8775p/fastrpc_shell_4 next to qcom/sa8775p/cdsp1.mbn).
    for dsp_dir in $out/share/qcom/sa8775p/Qualcomm/SA8775P-RIDE/dsp/*/; do
      for shell in "$dsp_dir"fastrpc_shell*; do
        [ -f "$shell" ] && cp -n "$shell" $out/lib/firmware/qcom/sa8775p/
      done
    done

  '';

  # Keep uncompressed - pd-mapper reads .jsn directly from disk.
  # linux-firmware handles compression for other platforms.
  compressFirmware = false;

  meta = with lib; {
    description = "Qualcomm Dragonwing firmware (ADSP, CDSP, GPU, WiFi, FastRPC)";
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux;
  };
}
