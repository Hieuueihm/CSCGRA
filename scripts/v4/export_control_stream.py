"""Verify a V4 image and emit row-major records for the trusted RTL loader."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from compiler.v4.context_image import load_image, pack_tile, pack_control, REVISION, DEPTH

def export_stream(source: Path, output: Path, generation: int = 1) -> dict:
    if not 0 <= generation < 1 << 32:
        raise ValueError("generation must fit32 bits")
    image = load_image(source)
    records = []
    for pc, (tiles, control) in enumerate(zip(image.tiles, image.controls)):
        words = [int.from_bytes(pack_tile(tile), "little") for tile in tiles]
        words.append(int.from_bytes(pack_control(control), "little"))
        for bank, word in enumerate(words):
            records.append(f"{pc:02x} {bank:02x} {word:064x} {int(pc == DEPTH-1 and bank == 32)}\n")
    payload = "".join(records).encode("ascii")
    output.mkdir(parents=True, exist_ok=True)
    (output / "loader.txt").write_bytes(payload)
    header = dict(revision=REVISION, depth=DEPTH, generation=generation, verified=True,
                  records=len(records), stream_sha256=hashlib.sha256(payload).hexdigest(),
                  source_manifest_sha256=hashlib.sha256((source / "manifest.json").read_bytes()).hexdigest(),
                  boundary="Host must preserve verified bytes through transport; RTL does not compute SHA256")
    (output / "loader_header.json").write_text(json.dumps(header, indent=2)+"\n", encoding="utf-8")
    return header

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--generation", type=int, default=1)
    args = parser.parse_args()
    print(json.dumps(export_stream(args.source, args.output, args.generation), indent=2))

if __name__ == "__main__":
    main()
