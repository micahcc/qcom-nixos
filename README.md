# qcom-nixos

NixOS modules and packages for Qualcomm Hexagon DSP / FastRPC platforms.

## Status

- **IQ-9075 EVK** (Qualcomm Dragonwing, SA8775P SoC, Hexagon v73): supported.
  HTP inference works end-to-end (verified with the BEiT image classifier
  from Qualcomm AI Hub).

Future devices can be added as `modules/devices/<board>.nix` selecting an
appropriate platform module under `modules/<soc>/`.

## What's in here

```
flake.nix          – flake outputs (nixosModules, overlay, packages)
overlay.nix        – pkgs.qualcomm.{qrtr,pd-mapper,qnn-sdk,…}
modules/
  default.nix      – top-level: hardware.qualcomm.{enable,device,platform}
  qrtr.nix         – qrtr-ns name service (initrd + post-switch-root)
  pd-mapper.nix    – Protection Domain mapper service
  fastrpc.nix      – udev rules + /run/qcom-dsp + /usr/lib/dsp/cdsp
  firmware.nix     – linux-firmware overlay + initrd firmware tree on cmdline
  kernel.nix       – pd_ignore_unused / clk_ignore_unused, base modules
  llama-server.nix – optional services.qualcomm.llama-server.* (HTP+OpenCL
                     llama.cpp inference server, OpenAI-compatible API)
  sa8775p/         – SA8775P platform: kernel, dragonwing-firmware,
                     qairt-dsp-binaries v73 wired into fastrpc dspPaths
  devices/
    iq-9075-evk.nix      – board-specific kernel modules
    iq-9075-evk-base.nix – EVK-generic NixOS config (boot, GRUB,
                           filesystems, QNN env, nix-register-paths)
  deploy/
    firmware.nix    – qdl-flashable NHLOS/CDT/DTB firmware bundle
    disk-image.nix  – raw disk image builder (4096-byte sector GPT)
    flash-script.nix – host-side (x86_64) qdl flash script
pkgs/              – package definitions (kernel, firmware, QNN SDK, etc.)
examples/
  iq-9075-evk/     – minimal NixOS config for the IQ-9075 EVK; consumed
                     by `nixosConfigurations.iq-9075-evk` for direct
                     `nix build` of disk image / flash script.
```

## Usage

A complete reference NixOS system is shipped at
[`examples/iq-9075-evk/configuration.nix`](examples/iq-9075-evk/configuration.nix)
and exposed as `nixosConfigurations.iq-9075-evk` for direct consumption:

```sh
# Build the example board's flashable image and flash script:
nix build github:micahcc/qcom-nixos#nixosConfigurations.iq-9075-evk.config.system.build.diskImage
nix build github:micahcc/qcom-nixos#nixosConfigurations.iq-9075-evk.config.system.build.flashScript
```

To bootstrap your own board, copy that file into your flake:

```nix
# In your flake.nix
{
  inputs.qcom-nixos.url = "github:micahcc/qcom-nixos";
  inputs.qcom-nixos.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, qcom-nixos }: {
    nixosConfigurations.my-iq-9075 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        qcom-nixos.nixosModules.default
        { nixpkgs.overlays = [ qcom-nixos.overlays.default ]; }
        ./configuration.nix  # adapted from examples/iq-9075-evk/
      ];
    };
  };
}
```

## Test that the DSP works

Two test binaries ship with this flake:

```sh
# Calculator skel on CDSP — quick smoketest of the FastRPC + QNN path.
# Exit 0 means libcdsprpc.so successfully loaded a DSP library and ran code.
qcom-dsp-smoketest

# Run the bundled QAIHub BEiT classifier on Hexagon HTP. With no --input,
# uses a zero-filled input — the goal is just to exercise the full inference
# path. Pass --input <301056-byte uint16 LE blob> for a real prediction.
qcom-dsp-imagenet-test
```

Add them to a test machine via:

```nix
environment.systemPackages = [
  pkgs.qualcomm.dsp-smoketest
  pkgs.qualcomm.dsp-imagenet-test
];
```

## Deploy (flash)

The deploy modules build a firmware bundle, disk image, and flash script for
the IQ-9075 EVK. All are opt-in:

```nix
hardware.qualcomm.iq-9075-evk.firmware.enable = true;
hardware.qualcomm.iq-9075-evk.diskImage.enable = true;
hardware.qualcomm.iq-9075-evk.flashScript.enable = true;
```

Options:

| Option                    | Default                         | Description                      |
| ------------------------- | ------------------------------- | -------------------------------- |
| `firmware.nhlosBins`      | QLI 1.7 from codelinaro         | NHLOS firmware archive           |
| `firmware.cdtZip`         | IQ-9075 EVK CDT from codelinaro | CDT board ID zip                 |
| `firmware.dtbBin`         | Canonical dtb.bin               | Device tree partition image      |
| `diskImage.sectorSize`    | 4096                            | GPT sector size (must match UFS) |
| `diskImage.espSizeMB`     | 512                             | EFI System Partition size        |
| `diskImage.rootMinSizeMB` | 2048                            | Minimum root partition size      |
| `flashScript.scriptName`  | `flash-<hostname>`              | Name of the flash script         |

Build and flash (using the bundled `iq-9075-evk` example):

```sh
# Build the flash script (outputs an x86_64 binary; substitute your own
# config name if you have your own nixosConfigurations entry).
nix build .#nixosConfigurations.iq-9075-evk.config.system.build.flashScript

# Inspect available subcommands:
./result/bin/flash-iq-9075-evk --help
```

### Flashing an IQ-9075 EVK

Hardware prerequisites:

- 12 V wall power supply.
- USB-C cable from EVK to your build host.
- Find the SW2-3 DIP switch (next to the SoM). UP = EDL mode.

One-time host setup (Ubuntu host shown; adapt for your distro):

```sh
# Allow your user to talk to Qualcomm EDL devices.
sudo tee /etc/udev/rules.d/51-qcom-usb.rules <<'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="05c6", ATTRS{idProduct}=="9008", MODE="0664", GROUP="plugdev"
EOF
sudo systemctl restart udev
sudo usermod -aG plugdev "$USER"   # log out + back in afterwards
```

Put the EVK into EDL mode:

1. Push SW2-3 UP.
2. Connect USB-C to the host.
3. Connect 12 V power.
4. Verify: `lsusb | grep '05c6:9008'` should show `Qualcomm, Inc. Gobi Wireless Modem (QDL mode)`.

First-time flash (full bring-up, ~5 min, requires a power cycle between
RTSS / NHLOS / NixOS steps — the script prompts and waits):

```sh
sudo ./result/bin/flash-iq-9075-evk provision   # UFS LUN layout (ONCE per board)
sudo ./result/bin/flash-iq-9075-evk cdt         # board ID
sudo ./result/bin/flash-iq-9075-evk flash       # RTSS + bootloader + NHLOS + NixOS
```

After flashing: switch SW2-3 DOWN and power-cycle. The board boots NixOS.

Subsequent updates (no need to reflash everything):

```sh
sudo ./result/bin/flash-iq-9075-evk flash-os   # NixOS only (~30s)
sudo ./result/bin/flash-iq-9075-evk flash-fw   # firmware only (XBL + CDT + NHLOS)
```

Even faster for incremental NixOS changes (no qdl, no DIP switch):

```sh
nix build .#nixosConfigurations.iq-9075-evk.config.system.build.toplevel
nix copy --to ssh://root@<board-ip> ./result
ssh root@<board-ip> sudo install-configuration $(readlink -f ./result) boot
ssh root@<board-ip> sudo reboot
```

Common failures:

- **`failed to read sahara request from device`** → device exited EDL.
  Power-cycle (DIP switch still UP) and retry.
- **`Bus 002 Device XXX: ...` doesn't appear** → cable or DIP switch issue.
  Try a different USB port; some hubs don't pass through to EDL.
- **Boot hangs at GRUB or "no such device: ESP"** → re-flash with
  `flash-os` (the disk-image rebuild step likely missed the ESP partition).
- **DSP errors after first boot** (`ssctl service timeout`,
  `intent request timed out`) → almost always means the kernel CONFIG /
  cmdline matches Ubuntu's broken state; verify
  `cat /proc/cmdline | grep pd_ignore_unused` returns a hit.

Verify the DSP works after first boot:

```sh
ssh root@<board-ip> qcom-dsp-smoketest
ssh root@<board-ip> qcom-dsp-imagenet-test
```

## Run an LLM on the DSP

The `services.qualcomm.llama-server` module ships an OpenAI-compatible
inference server using llama.cpp's Hexagon HTP + Adreno OpenCL backends:

```nix
services.qualcomm.llama-server = {
  enable = true;
  model = "/var/lib/llama-server/model.gguf";
  openFirewall = true;  # exposes port 8080
};
```

Drop a GGUF model at the configured path (chown to user `llama-server`)
and the server will listen on port 8080 with the standard OpenAI API.

## License

MIT (see LICENSE). Bundled firmware / DSP binaries / QNN SDK retain their
upstream licenses (Qualcomm proprietary, redistributable per Qualcomm's
terms — see individual package definitions).
