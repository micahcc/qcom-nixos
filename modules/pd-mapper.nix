# pd-mapper (Protection Domain Mapper) service.
#
# Resolves protection domain locator queries (tms/servreg etc.) from DSPs.
# Required for CDSP/ADSP boot to complete on Qualcomm platforms. Runs both in
# initrd (pre-udev DSP probe) and post-switch-root.
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.pdMapper;
  pd-mapper = pkgs.qualcomm.pd-mapper;
in
{
  options.hardware.qualcomm.pdMapper = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.qualcomm.enable;
      description = "Enable pd-mapper (Qualcomm Protection Domain Mapper).";
    };

    firmwarePath = lib.mkOption {
      type = lib.types.str;
      default = config.hardware.qualcomm.firmwarePath;
      description = ''
        Subpath under `/lib/firmware/` where pd-mapper looks for `.jsn`
        protection domain descriptors.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.hardware.qualcomm.qrtr.enable;
      message = "hardware.qualcomm.pdMapper requires hardware.qualcomm.qrtr.";
    }];

    boot.initrd.systemd.storePaths = [ "${pd-mapper}/bin/pd-mapper" ];

    boot.initrd.systemd.services.pd-mapper = {
      description = "Qualcomm PD mapper (initrd)";
      requires = [ "qrtr-ns.service" ];
      after = [ "qrtr-ns.service" ];
      wantedBy = [ "initrd.target" ];
      before = [ "initrd.target" ];
      environment.PD_MAPPER_FIRMWARE_PATH = cfg.firmwarePath;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pd-mapper}/bin/pd-mapper";
        Restart = "always";
      };
    };

    systemd.services.pd-mapper = {
      description = "Qualcomm PD mapper service";
      requires = [ "qrtr-ns.service" ];
      after = [ "qrtr-ns.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.PD_MAPPER_FIRMWARE_PATH = cfg.firmwarePath;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pd-mapper}/bin/pd-mapper";
        Restart = "always";
        RestrictAddressFamilies = [ "AF_QIPCRTR" ];
      };
    };
  };
}
