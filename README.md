# qcom-nixos

NixOS modules and packages for Qualcomm Hexagon DSP / FastRPC platforms.

## Status

### Todos

- Find a durable, immutable home for the Ubuntu PPA source artifacts used by the
  `linux-qcom` kernel and Dragonwing runtime firmware packages. The PPA removes
  superseded versions, which can break builds pinned to older URLs. The kernel
  source archive and patches are roughly 230 MB and 22 MB; the firmware package
  is roughly 57 MB. We are looking for a suitable place to mirror these files
  (for example, an artifact store or Git LFS) so builds remain reproducible.
- get rid of /usr/\* this is very un-nix, and is mostly uncessary global state.
  Ideally anything of that form ends up in /run/qcom or /run/qualcomm-drivers,
  similar to /run/openg-drivers (could also just be in there). The challenge is
  finding workarounds for all the hard coded paths.

### Devices

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
inference server. For Hexagon HTP, use the x86_64-built, aarch64-targeted
`qualcomm.llama-cpp-hexagon` package, not the native OpenCL-only package.
The reference flake supplies `pkgsX86` through `specialArgs` for this purpose.
When copying the example into your own flake, copy that declaration too.

```nix
services.qualcomm.llama-server = {
  enable = true;
  package = pkgsX86.qualcomm.llama-cpp-hexagon;
  model = "/var/lib/llama-server/model.gguf";
  openFirewall = true;    # exposes port 8080
  contextSize = 4096;     # KV cache is NOT runtime-resizable.
  threads = 8;
  nGpuLayers = 99;        # 99 = all layers offloaded; 0 = CPU only.

  # Start with HTP. Only add GPUOpenCL after confirming it is available
  # with --list-devices in the service's environment.
  devices = [ "HTP0" ];

  # OpenCL backend doesn't implement SET_ROWS on quantized KV — keep
  # the default f16 cache instead of q8_0.
  cacheType = null;

  # `--fit off` skips llama-cpp's auto-shrink-to-fit step. Without it,
  # llama-cpp queries HTP (0 MiB free) and aborts in common_fit_params.
  extraArgs = [ "--fit" "off" ];
};
```

Rebuild + activate: any change above (notably `contextSize`) requires a
`systemctl restart llama-server` because llama-server allocates the KV
cache at model load and can't resize it on the fly.

### Build architecture and copying outputs

The Hexagon SDK requires an x86_64-linux builder even though the resulting
llama-server runs on aarch64. Build on x86_64 and use `nix copy` to transfer
the package closure to the board, or configure an x86_64 remote builder.
Use a dedicated SSH build account, a daemon-readable private key, and pinned
SSH host keys; an interactive SSH session alone does not test daemon access.
Do not disable signature checking globally: trust a signing key for regular
transfers, or explicitly permit an unsigned transfer from a trusted builder.

For an already-built kernel, copy every output needed by the system, not
just `Image`: the kernel's separate `modules` output is also required.
Use `nix-store -q --outputs <kernel.drv>` and check which outputs exist on the
source. A dry run after copying should no longer list the kernel derivation;
initrd and shrunk-module derivations may still need to build.

### Diagnosing HTP startup failures

Check `journalctl -u llama-server` and `journalctl -k`. Loading
`libggml-htp-v73.so` successfully establishes that FastRPC communication is
working; a later buffer-mapping failure is not evidence of missing glink
interrupts. Verify current `/proc/interrupts` counts rather than relying on
old observations or fixed IRQ numbers.

Repeated failed sessions have been observed leaving hundreds of DMA buffers
attached to CDSP0 and exhausting its 32-bit IOMMU virtual address space.
`Cannot allocate memory` while mapping a small buffer can therefore occur
with ample free RAM and CMA. As root, inspect `/sys/kernel/debug/dma_buf/bufinfo`.
The example limits restarts to mitigate this; it does not repair the driver leak.

During recovery, first stop llama-server and any other CDSP0 clients. A
controlled CDSP0 remoteproc stop/start cleared the mapping failure in testing.
Identify the correct remoteproc using its `name` and `firmware` attributes;
**do not assume a stable remoteproc index**. Restarting it interrupts all clients
on that DSP. A reboot may still be needed to reclaim retained host buffers.

`invalid device: GPUOpenCL` is a separate failure: vendor libraries alone do
not provide a working OpenCL ICD. Keep `devices = [ "HTP0" ]` until OpenCL
is independently validated. A healthy HTTP endpoint and successful device
initialization do not prove correct inference: test generated output too.
Repetitive nonsensical output was observed with the tested HTP setup and
remains unresolved; do not treat this example as validated model accuracy.

### Boot partition space

The example retains two GRUB configurations to reduce pressure on the 512 MiB
ESP. Kernel/initrd copies and firmware-owned files can still fill it. GRUB
copies new files before completing cleanup, so a full ESP may prevent an update
even after lowering the retention limit. With no update running, remove only
confirmed incomplete `.tmp` copies or deliberately retire older boot artifacts,
keeping the current boot and a known-good fallback. Do not delete firmware files
such as `Persisted_Capsules.bin` merely because they are large.

### Installing a model

There's no model bundled — you supply your own GGUF. A good default for
coding on a 16 GB-class SA8775P is **Qwen2.5-Coder-7B-Instruct Q4_K_M**
(~4.7 GB, Apache 2.0):

```sh
ssh root@<board-ip> '
  curl -L -o /tmp/model.gguf \
    https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf &&
  sudo install -o llama-server -g llama-server -m 0644 /tmp/model.gguf /var/lib/llama-server/model.gguf &&
  sudo systemctl restart llama-server
'
```

Other useful GGUF model sources:

| Model                         | Size (Q4_K_M) | URL                                                            |
| ----------------------------- | ------------- | -------------------------------------------------------------- |
| `Qwen2.5-Coder-1.5B-Instruct` | ~1.0 GB       | `https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF` |
| `Qwen2.5-Coder-3B-Instruct`   | ~2.0 GB       | `https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF`   |
| `Qwen2.5-Coder-7B-Instruct`   | ~4.7 GB       | `https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF`   |
| `Qwen2.5-Coder-14B-Instruct`  | ~9.0 GB       | `https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct-GGUF`  |

For non-coding chat or general use, browse
[`bartowski`](https://huggingface.co/bartowski) and
[`unsloth`](https://huggingface.co/unsloth) on Hugging Face — both publish
quantized GGUFs of most popular open-weight models within hours of release.

Verify the server is running and answering:

```sh
curl http://<board-ip>:8080/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"messages":[{"role":"user","content":"write a haiku about hexagons"}]}'
```

## License

MIT (see LICENSE). Bundled firmware / DSP binaries / QNN SDK retain their
upstream licenses (Qualcomm proprietary, redistributable per Qualcomm's
terms — see individual package definitions).
