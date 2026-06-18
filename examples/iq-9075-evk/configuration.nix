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
{ pkgs, ... }:
{
  hardware.qualcomm.device = "iq-9075-evk";

  hardware.qualcomm.iq-9075-evk.firmware.enable = true;
  hardware.qualcomm.iq-9075-evk.diskImage.enable = true;
  hardware.qualcomm.iq-9075-evk.flashScript.enable = true;

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

  system.stateVersion = "25.11";
}
