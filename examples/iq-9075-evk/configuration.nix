# Minimal NixOS configuration for the Qualcomm IQ-9075 EVK.
#
# Intended as a copy-paste starting point: flash this onto a fresh EVK,
# verify the DSP works, then start customizing. Ships with:
#
#   - root user (initial password: `qcom`; change immediately).
#   - DHCP networking with hostname `iq-9075-evk`.
#   - SSH on port 22 with password auth (LOCKED in production — set up
#     authorizedKeys and disable PasswordAuthentication before exposing).
#   - dsp-smoketest + dsp-imagenet-test in $PATH so you can verify the
#     Hexagon HTP path right after first boot.
#   - Deploy infrastructure (firmware bundle, disk image, flash script)
#     enabled so `nix build .#nixosConfigurations.iq-9075-evk.config.system.build.flashScript`
#     produces an x86_64 binary that flashes the board via qdl.
#
# After flashing and booting:
#   ssh root@<dhcp-address>     # password: qcom
#   qcom-dsp-smoketest          # ~1s, exits 0 if DSP is healthy
#   qcom-dsp-imagenet-test      # ~10s, runs BEiT on HTP
#
# See ../../README.md for the full flashing workflow.
{ config, lib, pkgs, pkgsX86, ... }:
{
  hardware.qualcomm.device = "iq-9075-evk";

  hardware.qualcomm.iq-9075-evk.firmware.enable = true;
  hardware.qualcomm.iq-9075-evk.diskImage.enable = true;
  hardware.qualcomm.iq-9075-evk.flashScript.enable = true;

  # The 512 MiB ESP fills quickly with ~56 MiB kernels + ~33 MiB initrds.
  # Keep a small boot menu; GRUB may need temporary free space before pruning.
  # Preserve firmware-owned ESP files (e.g. Persisted_Capsules.bin).
  boot.loader.grub.configurationLimit = 2;

  nix.settings.auto-optimise-store = true;

  networking.hostName = "iq-9075-evk";
  networking.useNetworkd = true;
  networking.useDHCP = true;

  # CHANGE ME. The hash below is yescrypt for the literal string "qcom".
  # Generate a new one with: nix-shell -p mkpasswd --run 'mkpasswd -m yescrypt'
  users.users.root.hashedPassword =
    "$y$j9T$NKxGyvdLSfETJ4c.le.Ly0$cU2bBNePaDX/V4qRRJGJfXCHR.B62jqh4ZQIZNYRxl6";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";        # CHANGE ME after setting up keys.
      PasswordAuthentication = true;  # CHANGE ME after setting up keys.
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    tmux
    htop
    qualcomm.qnn-sdk
    qualcomm.dsp-smoketest
    qualcomm.dsp-imagenet-test
  ];

  # Optional: OpenAI-compatible llama.cpp inference server with Hexagon HTP.
  # pkgsX86 is supplied by this repository's flake; copy that specialArgs
  # declaration too when using this configuration in your own flake.
  # Build the HTP package on x86_64 and copy its closure to the board, or
  # configure an x86_64 remote builder. Do not substitute the OpenCL-only
  # native package when HTP is required.
  # Drop a GGUF at /var/lib/llama-server/model.gguf
  # (chown llama-server) before enabling — see ../../README.md for a worked
  # example using Qwen2.5-Coder-7B-Instruct.
  #
  # services.qualcomm.llama-server = {
  #   enable = true;
  #   package = pkgsX86.qualcomm.llama-cpp-hexagon;
  #   openFirewall = true;       # exposes port 8080 (default)
  #
  #   # Start with HTP alone. Add GPUOpenCL only after --list-devices
  #   # confirms it works in the service environment; installing vendor
  #   # libraries alone does not register an OpenCL ICD.
  #   devices = [ "HTP0" ];
  #
  #   # OpenCL backend doesn't implement SET_ROWS on quantized KV — leave
  #   # cacheType at f16 (null) instead of the q8_0 default.
  #   cacheType = null;
  #
  #   # `--fit off` skips llama-cpp's auto-shrink-to-fit step, which queries
  #   # HTP (0 MiB free) and aborts in common_fit_params on this platform.
  #   extraArgs = [ "--fit" "off" ];
  #
  #   # Bump as needed; KV cache is allocated at model load and is NOT
  #   # runtime-resizable.
  #   contextSize = 4096;
  # };

  # Failed FastRPC sessions have been observed retaining DMA mappings.
  # Bound retries so startup failures cannot exhaust the 32-bit IOVA space.
  # This is a mitigation, not a fix for the underlying mapping leak.
  systemd.services.llama-server = lib.mkIf config.services.qualcomm.llama-server.enable {
    startLimitIntervalSec = 300;
    startLimitBurst = 3;
    serviceConfig.RestartSec = lib.mkForce 30;
  };

  system.stateVersion = "25.11";
}
