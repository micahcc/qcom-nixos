# tqftpserv - TFTP server over QRTR for Qualcomm DSP firmware loading
# DSPs request fastrpc_shell and skel libraries via TFTP over QRTR;
# this daemon serves them from /lib/firmware (or the sysfs firmware path).
{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config, zstd, qrtr }:

stdenv.mkDerivation {
  pname = "tqftpserv";
  version = "1.1.1-unstable-2025-04-08";

  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "tqftpserv";
    rev = "b6bb92d40cfffe28621abcf7bfaa6d99beea46cb";
    hash = "sha256-tXxiunBMbmHcko4tqgMXvOEZrMeqk4quybV1PukW0U0=";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ zstd qrtr ];

  mesonFlags = [
    "-Dsystemd-unit-prefix=${placeholder "out"}/lib/systemd/system"
  ];

  meta = with lib; {
    description = "TFTP server over QRTR for Qualcomm DSP firmware loading";
    homepage = "https://github.com/linux-msm/tqftpserv";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
