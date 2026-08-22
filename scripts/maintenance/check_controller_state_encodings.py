"""Guard the frozen sparse_loop_controller state-encoding contract.

Verification benches reach into the controller hierarchy and compare
`state` against numeric literals (e.g. `state == 7'd8`).  Renumbering or
renaming a state therefore breaks benches silently.  This checker pins the
literals the benches depend on to the canonical table in
rtl/v2/control/controller_states.vh and fails on drift in either direction.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
STATES_VH = ROOT / "rtl" / "v2" / "control" / "controller_states.vh"
CONTROLLER = ROOT / "rtl" / "v2" / "control" / "sparse_loop_controller.v"

# (bench, state name, pinned encoding, literal that must appear in the bench)
PINNED = [
    ("verification/v2/run1/tb_run1_k_sweep.v", "S_DONE", 8, "7'd8"),
    ("verification/v2/run1/tb_run1_noisy24_k8_rep.v", "S_CORR_WRITE", 37, "7'd37"),
]


def parse_states(text: str) -> dict[str, int]:
    states: dict[str, int] = {}
    for match in re.finditer(r"\b(S_[A-Z0-9_]+)\s*=\s*(?:7'd)?(\d+)\b", text):
        name, value = match.group(1), int(match.group(2))
        if value > 127:
            raise SystemExit(f"state encoding out of 7-bit range: {name}={value}")
        states[name] = value
    if not states:
        raise SystemExit("no state encodings found in controller_states.vh")
    return states


def main() -> int:
    states = parse_states(STATES_VH.read_text(errors="replace"))

    collisions: dict[int, list[str]] = {}
    for name, value in states.items():
        collisions.setdefault(value, []).append(name)
    duplicate = {v: names for v, names in collisions.items() if len(names) > 1}
    if duplicate:
        print("Controller state encoding FAIL: duplicate encodings")
        for value, names in sorted(duplicate.items()):
            print(f"  {value}: {', '.join(sorted(names))}")
        return 1

    controller_text = CONTROLLER.read_text(errors="replace")
    unused = [name for name in states if name not in controller_text]
    if unused:
        print("Controller state encoding FAIL: states absent from the controller body")
        for name in sorted(unused):
            print(f"  {name} (={states[name]}) is defined but never referenced")
        return 1

    for bench_rel, name, value, literal in PINNED:
        bench = (ROOT / bench_rel).read_text(errors="replace")
        if name not in states:
            print(f"Controller state encoding FAIL: pinned {name} missing from controller_states.vh")
            return 1
        if states[name] != value:
            print(
                f"Controller state encoding FAIL: {bench_rel} pins {name}={literal} "
                f"but controller_states.vh has {name}={states[name]}"
            )
            return 1
        if literal not in bench:
            print(
                f"Controller state encoding FAIL: {bench_rel} no longer contains "
                f"the pinned literal {literal} for {name}; update PINNED here"
            )
            return 1

    print(
        f"Controller state encodings PASS: {len(states)} states, no collisions, "
        f"{len(PINNED)} bench-pinned literals consistent"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
