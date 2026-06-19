# llama.cpp inference server with Hexagon HTP + Adreno OpenCL acceleration.
#
# Runs on port 8080 (OpenAI-compatible API) by default. The model file is
# expected to live at `model` (default `/var/lib/llama-server/model.gguf`).
#
# Installing a model:
#
#   # Pick any GGUF — Qwen2.5-Coder 7B Q4_K_M is a good default for coding
#   # on a 16GB-class device.
#   curl -L -o /tmp/model.gguf \
#     https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
#   sudo install -o llama-server -g llama-server -m 0644 \
#     /tmp/model.gguf /var/lib/llama-server/model.gguf
#   sudo systemctl restart llama-server
#
# Other good GGUF sources:
#   - https://huggingface.co/Qwen/Qwen2.5-Coder-{1.5B,3B,7B,14B}-Instruct-GGUF
#   - https://huggingface.co/bartowski/...   (re-quantized community variants)
#   - https://huggingface.co/unsloth/...     (often fastest to update for new models)
#
# To change the context size or any other runtime parameter, set the
# corresponding option (e.g. `services.qualcomm.llama-server.contextSize = 16384`)
# and rebuild — llama-server's KV cache is allocated at model load and cannot
# be resized at runtime.
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
      description = ''
        Path to the GGUF model file. Must be readable by the
        `llama-server` system user (UID/GID created by this module).

        Quick install of Qwen2.5-Coder 7B:
        ```sh
        curl -L -o /tmp/model.gguf \
          https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf
        sudo install -o llama-server -g llama-server -m 0644 \
          /tmp/model.gguf /var/lib/llama-server/model.gguf
        sudo systemctl restart llama-server
        ```
      '';
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

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = ''
        Maximum context length in tokens (`--ctx-size`). The KV cache is
        allocated at model load and CANNOT be resized at runtime — change
        this option and rebuild to grow the context. Memory cost scales
        roughly linearly with context size; with `cache-type-{k,v} = q8_0`
        a 7B model uses ~0.6 MB per token, so 32k ≈ 19 GB of KV memory.
      '';
    };

    threads = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Number of CPU threads (`--threads`).";
    };

    nGpuLayers = lib.mkOption {
      type = lib.types.int;
      default = 99;
      description = ''
        Number of model layers to offload to the GPU (`--n-gpu-layers`).
        99 means "all layers"; set to 0 to keep the model on CPU.
      '';
    };

    cacheType = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "f32" "f16" "bf16" "q8_0" "q4_0" "q4_1" "q5_0" "q5_1" ]);
      default = "q8_0";
      description = ''
        KV cache quantization for both K and V (`--cache-type-k`/`--cache-type-v`).
        `q8_0` halves KV memory vs `f16` with negligible quality loss.
        Set `null` to leave llama-server's default (typically `f16`).
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "--mlock" "--no-mmap" ];
      description = ''
        Additional command-line arguments appended after the built-in
        `--ctx-size`/`--threads`/`--n-gpu-layers`/`--cache-type-*` flags.
        Use this for `--mlock`, `--no-mmap`, `--parallel`, etc.
      '';
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
          "--ctx-size" (toString cfg.contextSize)
          "--threads" (toString cfg.threads)
          "--n-gpu-layers" (toString cfg.nGpuLayers)
        ] ++ lib.optionals (cfg.cacheType != null) [
          "--cache-type-k" cfg.cacheType
          "--cache-type-v" cfg.cacheType
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
