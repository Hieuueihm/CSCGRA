"""Legacy fabric entry point: run the complete unified Vivado xsim gate.

Historical focused reports retain their original source/tool provenance.
This entry point does not relabel historical evidence as current acceptance.
"""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.v4.run_phi_rtl import unified_gate


def main(include_control=False, include_memory=False, argv=None):
    return unified_gate(argv)


if __name__ == "__main__":
    raise SystemExit(main())
