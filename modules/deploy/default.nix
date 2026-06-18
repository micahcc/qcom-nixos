# Deploy sub-modules: firmware bundle, disk-image builder, flash-script.
#
# All are opt-in (gated behind hardware.qualcomm.iq-9075-evk.*.enable).
{
  imports = [
    ./firmware.nix
    ./disk-image.nix
    ./flash-script.nix
  ];
}
