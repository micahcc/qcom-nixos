# Builds the flash script that uses qdl to flash NixOS + firmware to the IQ-9075 EVK.
# The flash script runs on the x86_64 host, not on the aarch64 target.
#
# Enable with: hardware.qualcomm.iq-9075-evk.flashScript.enable = true;
# Exposes:     config.system.build.flashScript
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.qualcomm.iq-9075-evk.flashScript;
  firmware = config.system.build.firmware;

  # Flash script runs on x86_64 host, not aarch64 target
  hostPkgs = import pkgs.path { system = "x86_64-linux"; };

  flashScript = hostPkgs.writeShellScriptBin cfg.scriptName ''
    set -euo pipefail

    FIRMWARE_DIR="''${FIRMWARE_DIR:-${firmware}}"
    DISK_IMAGE="''${DISK_IMAGE:-${config.system.build.diskImage}}"
    PROGRAMMER="''${FIRMWARE_DIR}/prog_firehose_ddr.elf"

    usage() {
      cat <<EOF
    Usage: $(basename "$0") [COMMAND]

    Flash NixOS to Qualcomm Dragonwing IQ-9075 EVK via qdl (USB EDL mode).

    Commands:
      provision   Provision UFS LUN layout (only needed once for new/blank devices)
      cdt         Flash CDT board ID to LUN 3 (needed when switching board configs,
                  e.g. EVK vs EVK-IFP vs Ride-SX, or after provisioning)
      flash-rtss  Flash RTSS/SAIL firmware to SPI-NOR (needed on first flash or
                  when updating QLI firmware version)
      flash       Flash everything: RTSS + firmware + NixOS (use for first-time setup
                  or major firmware updates; requires power cycles between steps)
      flash-os    Flash only the NixOS disk image to LUN 0 (use for NixOS rebuilds
                  when firmware hasn't changed -- fastest option)
      flash-fw    Flash firmware only: XBL + CDT + NHLOS (needed when updating QLI
                  firmware version without changing the OS image)
      status      Check if device is in EDL mode

    Environment:
      FIRMWARE_DIR  Path to firmware binaries (default: from nix store)
      DISK_IMAGE    Path to NixOS disk image (default: nix-built image)

    To enter EDL mode:
      1. Turn ON DIP switch SW2-3 (push up)
      2. Connect 12V power supply
      3. Connect USB-C cable to host
      4. Verify: lsusb | grep "05c6:9008"
      5. After flashing, turn OFF SW2-3
    EOF
    }

    check_edl() {
      if [ -d /sys/bus/usb/devices ]; then
        found=0
        for dev in /sys/bus/usb/devices/*/idVendor; do
          [ -f "$dev" ] || continue
          dir=$(dirname "$dev")
          vendor=$(cat "$dir/idVendor" 2>/dev/null)
          product=$(cat "$dir/idProduct" 2>/dev/null)
          if [ "$vendor" = "05c6" ] && [ "$product" = "9008" ]; then
            found=1
            break
          fi
        done
        if [ "$found" = "0" ]; then
          echo "ERROR: No Qualcomm EDL device found (USB 05c6:9008)"
          echo ""
          echo "To enter EDL mode:"
          echo "  1. Turn ON DIP switch SW2-3 (push up)"
          echo "  2. Connect 12V power supply"
          echo "  3. Connect USB-C cable to host"
          echo "  4. Verify: lsusb | grep '05c6:9008'"
          return 1
        fi
      fi
      echo "EDL device detected."
    }

    generate_rawprogram0() {
      local img_size_bytes
      img_size_bytes=$(stat -c%s "$DISK_IMAGE")
      local img_size_kb=$(( img_size_bytes / 1024 ))
      local img_sectors=$(( img_size_bytes / 4096 ))

      cat <<XML
    <?xml version="1.0" ?>
    <data>
      <program start_sector="0" size_in_KB="$img_size_kb.0" physical_partition_number="0" partofsingleimage="false" file_sector_offset="0" num_partition_sectors="$img_sectors" readbackverify="false" filename="$DISK_IMAGE" sparse="false" start_byte_hex="0x0" SECTOR_SIZE_IN_BYTES="4096" label="disk"/>
    </data>
    XML
    }

    cmd_provision() {
      echo "=== UFS Provisioning ==="
      echo "WARNING: This will repartition UFS storage. Only needed for blank/new devices."
      echo ""
      read -rp "Continue? [y/N] " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || exit 1

      check_edl

      ${hostPkgs.qdl}/bin/qdl --storage ufs \
        -i "''${FIRMWARE_DIR}" \
        "$PROGRAMMER" \
        "''${FIRMWARE_DIR}/provision_1_1.xml"

      echo ""
      echo "UFS provisioning complete. Power cycle and re-enter EDL mode to continue."
    }

    cmd_cdt() {
      echo "=== Flash CDT (Board ID) to LUN 3 ==="
      check_edl

      ${hostPkgs.qdl}/bin/qdl --storage ufs \
        -i "''${FIRMWARE_DIR}" \
        "$PROGRAMMER" \
        "''${FIRMWARE_DIR}/rawprogram3.xml" \
        "''${FIRMWARE_DIR}/patch3.xml"

      echo ""
      echo "CDT flash complete."
    }

    cmd_flash_rtss() {
      echo "=== Flash RTSS firmware to SPI-NOR ==="
      check_edl

      ${hostPkgs.qdl}/bin/qdl --storage spinor \
        -i "''${FIRMWARE_DIR}/sail_nor" \
        "''${FIRMWARE_DIR}/sail_nor/prog_firehose_ddr.elf" \
        "''${FIRMWARE_DIR}/sail_nor/rawprogram0.xml" \
        "''${FIRMWARE_DIR}/sail_nor/patch0.xml"

      echo ""
      echo "RTSS (Safety Island) flash complete."
    }

    wait_for_edl() {
      echo ""
      echo ">>> Power cycle the device now (unplug 12V, wait 3s, plug back in)."
      read -rp "    Hit Enter when done..."
      echo "    Waiting for EDL device..."
      local attempts=0
      while [ $attempts -lt 60 ]; do
        sleep 2
        if check_edl_quiet; then
          echo "    EDL device detected. Continuing..."
          sleep 1
          return 0
        fi
        attempts=$((attempts + 1))
      done
      echo "ERROR: Timed out waiting for EDL device (120s). Power cycle and retry."
      return 1
    }

    check_edl_quiet() {
      if [ -d /sys/bus/usb/devices ]; then
        for dev in /sys/bus/usb/devices/*/idVendor; do
          [ -f "$dev" ] || continue
          dir=$(dirname "$dev")
          vendor=$(cat "$dir/idVendor" 2>/dev/null)
          product=$(cat "$dir/idProduct" 2>/dev/null)
          if [ "$vendor" = "05c6" ] && [ "$product" = "9008" ]; then
            return 0
          fi
        done
      fi
      return 1
    }

    cmd_flash() {
      echo "=== Full Flash: RTSS + CDT + Bootloader + NHLOS + NixOS ==="
      check_edl

      echo ""
      echo "--- Step 1/3: Flash RTSS to SPI-NOR ---"
      ${hostPkgs.qdl}/bin/qdl --storage spinor \
        -i "''${FIRMWARE_DIR}/sail_nor" \
        "''${FIRMWARE_DIR}/sail_nor/prog_firehose_ddr.elf" \
        "''${FIRMWARE_DIR}/sail_nor/rawprogram0.xml" \
        "''${FIRMWARE_DIR}/sail_nor/patch0.xml"

      wait_for_edl

      echo ""
      echo "--- Step 2/3: Flash CDT + Boot + NHLOS to UFS ---"
      ${hostPkgs.qdl}/bin/qdl --storage ufs \
        -i "''${FIRMWARE_DIR}" \
        "$PROGRAMMER" \
        "''${FIRMWARE_DIR}/rawprogram1.xml" \
        "''${FIRMWARE_DIR}/rawprogram2.xml" \
        "''${FIRMWARE_DIR}/rawprogram3.xml" \
        "''${FIRMWARE_DIR}/rawprogram4.xml" \
        "''${FIRMWARE_DIR}/patch1.xml" \
        "''${FIRMWARE_DIR}/patch2.xml" \
        "''${FIRMWARE_DIR}/patch3.xml" \
        "''${FIRMWARE_DIR}/patch4.xml"

      wait_for_edl

      echo ""
      echo "--- Step 3/3: Flash NixOS disk image to LUN 0 ---"
      local tmpdir
      tmpdir=$(mktemp -d)
      trap "rm -rf $tmpdir" EXIT

      generate_rawprogram0 > "$tmpdir/rawprogram0.xml"

      ${hostPkgs.qdl}/bin/qdl --storage ufs \
        -i "''${FIRMWARE_DIR}" \
        "$PROGRAMMER" \
        "$tmpdir/rawprogram0.xml"

      echo ""
      echo "Flash complete. Turn OFF SW2-3 and power cycle the device to boot NixOS."
    }

    cmd_flash_os() {
      echo "=== Flash NixOS disk image (LUN 0) ==="
      check_edl

      local tmpdir
      tmpdir=$(mktemp -d)
      trap "rm -rf $tmpdir" EXIT

      generate_rawprogram0 > "$tmpdir/rawprogram0.xml"

      ${hostPkgs.qdl}/bin/qdl --storage ufs \
        -i "''${FIRMWARE_DIR}" \
        "$PROGRAMMER" \
        "$tmpdir/rawprogram0.xml"

      echo ""
      echo "NixOS image flashed to LUN 0."
    }

    cmd_flash_fw() {
      echo "=== Flash Firmware: XBL (LUN 1,2) + CDT (LUN 3) + NHLOS (LUN 4) ==="
      check_edl

      ${hostPkgs.qdl}/bin/qdl --storage ufs \
        -i "''${FIRMWARE_DIR}" \
        "$PROGRAMMER" \
        "''${FIRMWARE_DIR}/rawprogram1.xml" \
        "''${FIRMWARE_DIR}/rawprogram2.xml" \
        "''${FIRMWARE_DIR}/rawprogram3.xml" \
        "''${FIRMWARE_DIR}/rawprogram4.xml" \
        "''${FIRMWARE_DIR}/patch1.xml" \
        "''${FIRMWARE_DIR}/patch2.xml" \
        "''${FIRMWARE_DIR}/patch3.xml" \
        "''${FIRMWARE_DIR}/patch4.xml"

      echo ""
      echo "Firmware flash complete."
    }

    cmd_status() {
      echo "Checking for Qualcomm EDL device..."
      if check_edl; then
        echo ""
        ${hostPkgs.usbutils}/bin/lsusb | grep "05c6:9008" || true
      fi
    }

    case "''${1:-}" in
      provision)  cmd_provision ;;
      cdt)        cmd_cdt ;;
      flash-rtss) cmd_flash_rtss ;;
      flash)      cmd_flash ;;
      flash-os)   cmd_flash_os ;;
      flash-fw)   cmd_flash_fw ;;
      status)     cmd_status ;;
      -h|--help)  usage ;;
      *)
        usage
        exit 1
        ;;
    esac
  '';
in
{
  options.hardware.qualcomm.iq-9075-evk.flashScript = {
    enable = lib.mkEnableOption "IQ-9075 EVK qdl flash script (system.build.flashScript)";

    scriptName = lib.mkOption {
      type = lib.types.str;
      default = "flash-${config.networking.hostName}";
      description = "Name of the generated flash script binary.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.qualcomm.iq-9075-evk.firmware.enable;
        message = "hardware.qualcomm.iq-9075-evk.flashScript requires firmware to be enabled.";
      }
      {
        assertion = config.hardware.qualcomm.iq-9075-evk.diskImage.enable;
        message = "hardware.qualcomm.iq-9075-evk.flashScript requires diskImage to be enabled.";
      }
    ];

    system.build.flashScript = flashScript;
  };
}
