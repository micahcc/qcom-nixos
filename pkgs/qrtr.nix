# QRTR - Qualcomm IPC Router userspace library and tools
# Pinned to last commit with qrtr-ns (before it was removed in favor of in-kernel NS).
# Ubuntu's Qualcomm kernel (6.8.0-1071-qcom) lacks CONFIG_QRTR_NS, so we need userspace qrtr-ns.
{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config }:

stdenv.mkDerivation {
  pname = "qrtr";
  version = "1.1-unstable-2024-06-19";

  src = fetchFromGitHub {
    owner = "andersson";
    repo = "qrtr";
    rev = "8f9b2bc3b60f59ecc9e6193764fa885cdef7f0ce";
    hash = "sha256-cPd7bd+S2uVILrFF797FwumPWBOJFDI4NvtoZ9HiWKM=";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];

  mesonFlags = [
    "-Dqrtr-ns=enabled"
    "-Dsystemd-service=disabled"
  ];

  meta = with lib; {
    description = "Qualcomm IPC Router userspace library and tools";
    homepage = "https://github.com/andersson/qrtr";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
