# llama.cpp inference server with Hexagon HTP + Adreno OpenCL acceleration.
#
# Runs on port 8080 (OpenAI-compatible API) by default. The model file is
# expected to live at `model` (default `/var/lib/llama-server/model.gguf`).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.qualcomm.llama-server;
  llama-cpp = if cfg.package == null then pkgs.qualcomm.llama-cpp else cfg.package;
  # FastRPC's `libcdsprpc.so` resolves DSP-side dynamic libraries (the
  # `libggml-htp-v73.so` skel) by searching `ADSP_LIBRARY_PATH` on the host
  # AND falling back to the kernel's hardcoded `/usr/lib/dsp/cdsp/` path.
  # The base fastrpc module bind-mounts `/run/qcom-dsp` (dragonwing shells +
  # qairt-dsp QNN skels) at `/usr/lib/dsp/cdsp`. We need to add llama-cpp's
  # HTP skel libs to the mix, so build a merged tree just for this service.
  dspMerged = pkgs.buildEnv {
    name = "qcom-dsp-llama-server";
    paths = config.hardware.qualcomm.fastrpc.dspPaths
      ++ [ "${llama-cpp}/lib" ];
  };
in
{
  options.services.qualcomm.llama-server = {
    enable = lib.mkEnableOption "llama.cpp inference server with Hexagon HTP + Adreno OpenCL";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        llama-cpp package to use. Default: `pkgs.qualcomm.llama-cpp` (only
        present when the qcom-nixos overlay is applied to a host nixpkgs
        that also has `pkgs.pkgsCross.aarch64-multiplatform`, i.e. an x86_64
        build host). Pass an explicit package if you cross-compile elsewhere.
      '';
    };

    model = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/llama-server/model.gguf";
      description = "Path to the GGUF model file.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address for the OpenAI-compatible API.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port for the OpenAI-compatible API.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--ctx-size" "4096"
        "--n-gpu-layers" "99"
        "--threads" "8"
        "--cache-type-k" "q8_0"
        "--cache-type-v" "q8_0"
      ];
      description = "Additional command-line arguments passed to llama-server.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.llama-server = {
      isSystemUser = true;
      group = "llama-server";
      home = "/var/lib/llama-server";
      createHome = true;
    };
    users.groups.llama-server = {};

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.llama-server = {
      description = "llama.cpp inference server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        LD_LIBRARY_PATH = "${pkgs.qualcomm.qcom-vendor-libs}/lib";
        ADSP_LIBRARY_PATH = "${dspMerged}";
        DSP_LIBRARY_PATH  = "${dspMerged}";
      };

      serviceConfig = {
        Type = "simple";
        User = "llama-server";
        Group = "llama-server";
        SupplementaryGroups = [ "render" "video" ];
        ExecStart = lib.escapeShellArgs ([
          "${llama-cpp}/bin/llama-server"
          "--host" cfg.host
          "--port" (toString cfg.port)
          "--model" cfg.model
        ] ++ cfg.extraArgs);
        Restart = "on-failure";
        RestartSec = 5;

        # fastrpc shell loading uses a hardcoded /usr/lib/dsp/cdsp fallback
        # path. Bind the merged tree there inside this unit's mount namespace
        # so libcdsprpc.so finds both the standard DSP shells/skels AND
        # llama-cpp's libggml-htp-v73.so without polluting the system-wide
        # /run/qcom-dsp.
        BindPaths = [ "${dspMerged}:/usr/lib/dsp/cdsp" ];

        # Hardening
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
