# pd-mapper - Qualcomm Protection Domain mapper service
{ lib, stdenv, fetchFromGitHub, qrtr, xz }:

stdenv.mkDerivation {
  pname = "pd-mapper";
  version = "unstable-2024-06-04";

  src = fetchFromGitHub {
    owner = "andersson";
    repo = "pd-mapper";
    rev = "5ecd2fe926aca7abfe40724177f63b942cff3947";
    hash = "sha256-I5/N24KONtNRSub00Mqh1GoMHO2qQKTj/ts2N6DQdPc=";
  };

  patches = [ ./pd-mapper-enumerate.patch ];

  buildInputs = [ qrtr xz ];

  makeFlags = [ "prefix=$(out)" ];

  NIX_CFLAGS_COMPILE = "-I${qrtr}/include";
  NIX_LDFLAGS = "-L${qrtr}/lib";

  meta = with lib; {
    description = "Qualcomm Protection Domain mapper service";
    homepage = "https://github.com/andersson/pd-mapper";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
