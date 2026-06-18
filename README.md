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
    iq-9075-evk.nix – board-specific kernel modules
pkgs/              – package definitions (kernel, firmware, QNN SDK, etc.)
```

## Usage

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
        ({ ... }: {
          hardware.qualcomm.device = "iq-9075-evk";
        })
        # ...your board-specific bits: filesystems, users, networking...
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
