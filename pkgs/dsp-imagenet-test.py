#!/usr/bin/env python3
"""Run a QNN DLC image classifier on Hexagon HTP and print top-5 predictions.

Designed to validate the end-to-end DSP inference path (libcdsprpc.so → DSP
PIL boot → fastrpc shell → QNN HTP skel → graph execute) on a working
Qualcomm board. Reads input as raw uint16 little-endian (default
1×224×224×3 = 301056 bytes — the BEiT w8a16 input layout).
"""
from __future__ import annotations

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def read_topk(logits_path: Path, k: int = 5) -> list[tuple[int, int]]:
    raw = logits_path.read_bytes()
    n = len(raw) // 2
    vals = struct.unpack(f"<{n}H", raw)
    return sorted(enumerate(vals), key=lambda iv: -iv[1])[:k]


def synthesize_zero_input(path: Path, n_bytes: int) -> None:
    """Write n_bytes of zeros — produces a deterministic (if meaningless) input."""
    path.write_bytes(b"\x00" * n_bytes)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--model", type=Path,
                    default=Path(os.environ.get("QCOM_DSP_IMAGENET_MODEL", "")),
                    help="Path to the QNN DLC model (e.g. beit.dlc). "
                         "Defaults to bundled QAIHub BEiT.")
    ap.add_argument("--input", type=Path,
                    help="Path to raw uint16 LE input data (default size 301056). "
                         "If omitted, a zero-filled input is synthesized for a smoketest.")
    ap.add_argument("--input-size", type=int, default=301056,
                    help="Expected input size in bytes. Default matches 1x224x224x3 uint16.")
    ap.add_argument("--labels", type=Path,
                    default=Path(os.environ.get("QCOM_DSP_IMAGENET_LABELS", "")),
                    help="ImageNet label file (one class per line). Defaults to bundled.")
    ap.add_argument("--top", type=int, default=5,
                    help="How many top predictions to print.")
    args = ap.parse_args()

    if not args.model or not args.model.exists():
        sys.exit(f"Model not found: {args.model} (set --model or QCOM_DSP_IMAGENET_MODEL).")
    if not args.labels or not args.labels.exists():
        sys.exit(f"Labels not found: {args.labels} (set --labels or QCOM_DSP_IMAGENET_LABELS).")
    if args.input is not None:
        if not args.input.exists():
            sys.exit(f"Input not found: {args.input}")
        actual = args.input.stat().st_size
        if actual != args.input_size:
            sys.exit(f"Input size mismatch: {actual} != {args.input_size}")

    qnn_net_run = os.environ.get("QCOM_DSP_IMAGENET_QNN_NET_RUN")
    backend = os.environ.get("QCOM_DSP_IMAGENET_BACKEND")
    if not qnn_net_run or not backend:
        sys.exit("Missing QCOM_DSP_IMAGENET_{QNN_NET_RUN,BACKEND} env vars.")

    with tempfile.TemporaryDirectory(prefix="qcom-dsp-imagenet-") as td:
        td = Path(td)
        input_copy = td / "input.raw"
        if args.input is not None:
            shutil.copy(args.input, input_copy)
        else:
            print(f"# no --input given; synthesizing {args.input_size} zero bytes "
                  f"(smoketest mode)", flush=True)
            synthesize_zero_input(input_copy, args.input_size)
        list_file = td / "input_list.txt"
        list_file.write_text(str(input_copy) + "\n")
        out_dir = td / "out"

        cmd = [
            qnn_net_run,
            "--dlc_path", str(args.model),
            "--backend", backend,
            "--input_list", str(list_file),
            "--output_dir", str(out_dir),
        ]
        print(f"+ {' '.join(cmd)}", flush=True)
        rc = subprocess.call(cmd)
        if rc != 0:
            print(f"qnn-net-run exited with status {rc}", file=sys.stderr)
            return rc

        # Output layout: <out_dir>/Result_0/<output_tensor_name>.raw
        result_dir = out_dir / "Result_0"
        outs = list(result_dir.glob("*.raw"))
        if not outs:
            sys.exit(f"No output tensors in {result_dir}")
        if len(outs) > 1:
            print(f"warning: multiple outputs, using {outs[0]}", file=sys.stderr)
        topk = read_topk(outs[0], args.top)
        labels = args.labels.read_text().splitlines()
        print()
        print(f"Top-{args.top} predictions ({outs[0].name}):")
        for idx, val in topk:
            label = labels[idx] if idx < len(labels) else "?"
            print(f"  [{idx:4d}] q={val:5d}  {label}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
