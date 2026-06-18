{
  description = "NixOS modules and packages for Qualcomm Hexagon DSP / FastRPC platforms.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
        config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
          "qnn-sdk"
          "hexagon-sdk"
          "qcom-vendor-libs"
          "qcom-fastrpc"
          "qairt-dsp-binaries"
          "qai-hub-beit-w8a16"
          "qcom-dsp-smoketest"
          "qcom-dsp-imagenet-test"
        ];
      };
    in {
      overlays.default = import ./overlay.nix;

      nixosModules = {
        default = ./modules;
        qrtr = ./modules/qrtr.nix;
        pd-mapper = ./modules/pd-mapper.nix;
        fastrpc = ./modules/fastrpc.nix;
        firmware = ./modules/firmware.nix;
        kernel = ./modules/kernel.nix;
        sa8775p = ./modules/sa8775p;
        iq-9075-evk = ./modules/devices/iq-9075-evk.nix;
      };

      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          q = pkgs.qualcomm;
          common = {
            inherit (q) qrtr pd-mapper tqftpserv;
          };
          # Aarch64-only because they ship aarch64 binaries (DSP firmware,
          # vendor libraries, kernel).
          aarch64Only = {
            inherit (q) qcom-vendor-libs qcom-fastrpc
                        linux-qcom dragonwing-firmware qairt-dsp-binaries qnn-sdk
                        dsp-smoketest dsp-imagenet-test qai-hub-beit;
          };
          # x86_64 build host only — Hexagon SDK is a cross-compiler. llama-cpp
          # is built here too because it needs hexagon-sdk during compile;
          # the produced binary still targets aarch64.
          x86Only = {
            inherit (q) hexagon-sdk llama-cpp;
          };
        in common
          // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") aarch64Only
          // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") x86Only
      );
    };
}
