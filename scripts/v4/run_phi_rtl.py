"""Legacy entry point for the unified Vivado gate; shared source/command helpers."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


def sources(full: bool) -> dict[str, str]:
    paths = [
        ROOT / name for name in (
            "config/v4_design.json", "config/v4_phi_interface.json", "config/v4_modules.json",
            "docs/v4/architecture/PHI_RTL_CONTRACT.md", "models/v4/lfsr_operator.py",
            "models/v4/phi_stream.py", "scripts/v4/generate_phi_interface.py",
            "scripts/v4/run_phi_rtl.py", "verification/v4/test_phi_rtl.py",
            "verification/v4/test_lfsr_operator.py",
        )
    ]
    paths.extend(path for path in (ROOT / "rtl/v4").rglob("*") if path.suffix in (".sv", ".vh", ".f"))
    if full:
        paths.extend((ROOT / "config").glob("v4*.json"))
        paths.extend((ROOT / "docs/v4/architecture").glob("*RTL_CONTRACT.md"))
        paths.append(ROOT / "docs/v4/architecture/LSQR_INTEGRATION.md")
        paths.extend(path for path in (ROOT / "verification/v4").rglob("*") if path.suffix in (".sv", ".json"))
        for folder in ("models/v4", "compiler/v4", "verification/v4", "scripts/v4"):
            paths.extend((ROOT / folder).rglob("*.py"))
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(set(paths))}


def run(command: list[str], env: dict | None = None) -> dict:
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=120)
    return {"command": command, "returncode": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr}


def unified_gate(argv=None, *, allow_full=False):
    """Consume only supported legacy arguments, then run the complete Vivado gate."""
    parser = argparse.ArgumentParser(description="Run the unified Vivado xsim V4 correctness gate")
    if allow_full:
        parser.add_argument("--full", action="store_true", help="retained compatibility; the unified gate is always full")
    parser.parse_args(argv)
    from scripts.v4.run_rtl import main as vivado_main
    return vivado_main([])


def main(argv=None):
    return unified_gate(argv, allow_full=True)


if __name__ == "__main__":
    raise SystemExit(main())
