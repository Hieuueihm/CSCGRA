"""Enforce the canonical -> hardware Python -> RTL reference contract."""

from __future__ import annotations

import ast
import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
CANONICAL = ROOT / "models" / "reference" / "canonical.py"
HARDWARE = ROOT / "models" / "reference" / "hardware.py"
AUDIT = ROOT / "models" / "golden" / "audit_algorithm_semantics.py"
TB = ROOT / "verification" / "v2" / "run1" / "tb_run1_k_sweep.v"
V_GOLDEN = ROOT / "verification" / "v2" / "run1" / "k_sweep_golden_hardware.vh"
C_GOLDEN = ROOT / "sw" / "v2" / "src" / "cscgra_k_sweep_golden.h"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"reference contract FAIL: {message}")


def imports(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
    result: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            result.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            result.add(node.module.split(".")[0])
    return result


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    for path in (CANONICAL, HARDWARE, AUDIT, TB, V_GOLDEN, C_GOLDEN):
        require(path.is_file(), f"missing {path.relative_to(ROOT)}")

    canonical_imports = imports(CANONICAL)
    forbidden_canonical = {
        "hardware", "rtl", "verification", "golden", "canonical_fixed", "abstract_rtl"
    }
    require(
        canonical_imports.isdisjoint(forbidden_canonical),
        f"canonical.py imports downstream source: {sorted(canonical_imports & forbidden_canonical)}",
    )

    hardware_imports = imports(HARDWARE)
    forbidden_hardware = {"rtl", "verification", "canonical_fixed", "abstract_rtl"}
    require(
        hardware_imports.isdisjoint(forbidden_hardware),
        f"hardware.py imports RTL/legacy source: {sorted(hardware_imports & forbidden_hardware)}",
    )

    audit_text = AUDIT.read_text(encoding="utf-8-sig")
    require("import canonical" in audit_text, "semantic audit does not use canonical.py")
    require("import hardware" in audit_text, "semantic audit does not use hardware.py")
    require("canonical_fixed" not in audit_text, "semantic audit still uses canonical_fixed.py")
    require("generate_k_sweep_golden" not in audit_text, "semantic audit uses a legacy generator")

    tb_text = TB.read_text(encoding="utf-8-sig")
    require(
        '`include "k_sweep_golden_hardware.vh"' in tb_text,
        "default v2 testbench does not include the hardware golden",
    )
    require("KSWEEP_GOLD_TOL" in tb_text, "default testbench lacks exact hardware tolerance")

    v_text = V_GOLDEN.read_text(encoding="utf-8-sig")
    c_text = C_GOLDEN.read_text(encoding="utf-8-sig")
    require(
        v_text.startswith("// Auto-generated only by models/reference/hardware.py"),
        "Verilog hardware golden has the wrong owner",
    )
    require("localparam integer KSWEEP_GOLD_TOL = 0;" in v_text, "hardware golden is not exact")
    require(
        '#define KSGOLD_SOURCE_TAG "models/reference/hardware.py"' in c_text,
        "C hardware golden has the wrong owner",
    )
    require("#define KSGOLD_TOL 0U" in c_text, "C hardware golden is not exact")

    canonical = load_module("reference_contract_canonical", CANONICAL)
    hardware = load_module("reference_contract_hardware", HARDWARE)
    canonical_names = set(canonical.run_all([[1.0]], [1.0], 1, 0.125))
    hardware_names = set(hardware.ALGORITHM_NAMES)
    require(canonical_names == hardware_names, "canonical/hardware algorithm sets differ")
    require(
        set(hardware.HARDWARE_TRANSFORM) == hardware_names,
        "hardware transformation table is incomplete",
    )

    print("Reference contract PASS: canonical -> hardware Python -> exact RTL golden")
    open_variants = [
        name for name, description in hardware.HARDWARE_TRANSFORM.items()
        if description.startswith("OPEN:")
    ]
    if open_variants:
        print("Open semantic migrations: " + ", ".join(open_variants))


if __name__ == "__main__":
    main()
