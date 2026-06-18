# QRTR (Qualcomm IPC Router) name service.
#
# Required by pd-mapper and any QMI client. Runs in initrd (so pd-mapper can
# come up before DSPs probe via udev) and post-switch-root.
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.qrtr;
  qrtr = pkgs.qualcomm.qrtr;
in
{
  options.hardware.qualcomm.qrtr = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.qualcomm.enable;
      description = "Enable QIPCRTR name service (qrtr-ns).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.kernelModules = [ "qrtr" "qrtr_smd" ];
    boot.initrd.systemd.enable = lib.mkDefault true;
    boot.initrd.systemd.storePaths = [ "${qrtr}/bin/qrtr-ns" ];

    boot.initrd.systemd.services.qrtr-ns = {
      description = "QIPCRTR Name Service (initrd)";
      wantedBy = [ "initrd.target" ];
      before = [ "initrd.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${qrtr}/bin/qrtr-ns -f 1";
        Restart = "always";
      };
    };

    systemd.services.qrtr-ns = {
      description = "QIPCRTR Name Service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${qrtr}/bin/qrtr-ns -f 1";
        Restart = "always";
        RestrictAddressFamilies = [ "AF_QIPCRTR" ];
      };
    };

    environment.systemPackages = [ qrtr ];
  };
}
