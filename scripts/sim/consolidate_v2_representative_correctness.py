#!/usr/bin/env python3
"""Consolidate V3 RTL evidence for V2-representative geometries."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
LOG_ROOT = ROOT / "reports" / "v3" / "m13_correctness_sweep"
OUT_ROOT = ROOT / "reports" / "v3" / "v2_representative_correctness"
PASS_RE = re.compile(
    r"M13 E2E CASE PASS m=(\d+) n=(\d+) k=(\d+) "
    r"algorithm=(\d+) profile=(\d+) cycles=(\d+)"
)
FAIL_RE = re.compile(r"FAIL:|Fatal:|Assertion violation")
ALGORITHMS = ("omp", "cosamp", "iht", "htp", "sp", "gp", "gomp", "mp")
PROFILES = ("strict_paper", "balanced_variant", "fast_variant")
GEOMETRIES = {
    "m64_n256_k8_seed41": (64, 256, 8),
    "m128_n256_k8_seed29": (128, 256, 8),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_case(geometry: str, profile: str, algorithm: str) -> dict:
    path = LOG_ROOT / f"{geometry}_{profile}_{algorithm}.xsim.log"
    text = path.read_text(encoding="utf-8", errors="replace")
    if FAIL_RE.search(text):
        raise SystemExit(f"failure marker in {path}")
    matches = PASS_RE.findall(text)
    if len(matches) != 1:
        raise SystemExit(f"expected one PASS marker in {path}")
    m, n, k, algorithm_id, profile_id, cycles = map(int, matches[0])
    if (m, n, k) != GEOMETRIES[geometry]:
        raise SystemExit(f"geometry mismatch in {path}")
    if algorithm_id != ALGORITHMS.index(algorithm):
        raise SystemExit(f"algorithm mismatch in {path}")
    if profile_id != PROFILES.index(profile):
        raise SystemExit(f"profile mismatch in {path}")
    return {
        "geometry": geometry,
        "m": m,
        "n": n,
        "k": k,
        "profile": profile,
        "algorithm": algorithm,
        "status": "PASS",
        "cycles": cycles,
        "time_us_at_100mhz": cycles / 100.0,
        "log": path.relative_to(ROOT).as_posix(),
        "log_sha256": sha256(path),
    }


def markdown_table(rows: list[dict]) -> list[str]:
    lines = [
        "| Geometry | Profile | Algorithm | Cycles | Time at 100 MHz |",
        "| --- | --- | --- | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            f"| {row['geometry']} | `{row['profile']}` | "
            f"{row['algorithm'].upper()} | {row['cycles']:,} | "
            f"{row['time_us_at_100mhz']:.2f} us |"
        )
    return lines


def main() -> None:
    rows = [
        parse_case(geometry, profile, algorithm)
        for geometry in GEOMETRIES
        for profile in PROFILES
        for algorithm in ALGORITHMS
    ]
    profile_summaries = {
        profile: {
            "passed": sum(row["profile"] == profile for row in rows),
            "expected": len(GEOMETRIES) * len(ALGORITHMS),
        }
        for profile in PROFILES
    }
    payload = {
        "schema": "cscgra-v3-v2-representative-correctness-v2",
        "date": "2026-09-03",
        "clock_target_mhz": 100,
        "golden_gates": {
            "floating_oracle": "80/80 PASS",
            "fixed_point": "240/240 PASS",
        },
        "rtl_matrix": {
            "geometries": list(GEOMETRIES),
            "algorithms": list(ALGORITHMS),
            "profiles": list(PROFILES),
            "passed": len(rows),
            "expected": len(GEOMETRIES) * len(ALGORITHMS) * len(PROFILES),
            "profile_summaries": profile_summaries,
            "rows": rows,
        },
        "source_sha256": {
            "models/v3/hardware.py": sha256(ROOT / "models/v3/hardware.py"),
            "rtl/v3/integration/m8_resource_dispatcher.v": sha256(
                ROOT / "rtl/v3/integration/m8_resource_dispatcher.v"
            ),
            "rtl/v3/selection/support_state_manager.v": sha256(
                ROOT / "rtl/v3/selection/support_state_manager.v"
            ),
            "verification/v3/m13/tb_m13_compute_lifecycle.sv": sha256(
                ROOT / "verification/v3/m13/tb_m13_compute_lifecycle.sv"
            ),
        },
    }
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "results.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    lines = [
        "# V3 correctness on V2-representative configurations",
        "",
        "Date: **2026-09-03**. Clock used only for cycle-to-time conversion: "
        "**100 MHz**. No synthesis result is claimed here.",
        "",
        "## Scope",
        "",
        "- V2 M64/N256/K8: `verification/v2/tb_noisy24_k8_rep_final.v:9`.",
        "- V2 M128/N256/K8: `verification/v2/run1/tb_run1_m128n256k8.v:271`.",
        "- Floating oracle: **80/80 PASS**.",
        "- Fixed D18F14/S27F19/A62 golden: **240/240 PASS**.",
        "- RTL pass requires bit-exact support count, support indices, S27F19 "
        "coefficients and terminal stop reason, with no failure marker.",
        "",
        "## Root Cause Closed",
        "",
        "- SP balanced had been assigned a three-step OMP budget. Its refinement "
        "policy is now classified from the compiler-issued resource transaction "
        "pattern.",
        "- CoSaMP balanced/fast had been assigned GOMP budgets 4/3 because CoSaMP, "
        "SP and GOMP all start with `SUPPORT_UNION`. Classification is now deferred "
        "to the following `SUPPORT_COMMIT`, which distinguishes GOMP support-stream "
        "commit from CoSaMP global-union commit.",
        "- Both fixes preserve bit-exact checking. No tolerance relaxation, "
        "algorithm-ID decode or synthesis directive was introduced.",
        "",
        "## RTL Matrix",
        "",
        "Result: **48/48 PASS**: 2 geometries x 8 algorithms x 3 profiles.",
        "",
        "- `strict_paper`: **16/16 PASS**.",
        "- `balanced_variant`: **16/16 PASS**.",
        "- `fast_variant`: **16/16 PASS**.",
        "",
        *markdown_table(rows),
        "",
        "## Conclusion",
        "",
        "- Floating-to-fixed-to-RTL correctness closure is complete for the two "
        "V2-representative geometries.",
        "- GP and MP are profile-invariant because they do not invoke restricted LS.",
        "- Timing and resource synthesis remain pending by design.",
        "- Wait for the requested RTL optimization direction before timing or synthesis.",
        "",
        "Machine-readable evidence: `results.json`.",
    ]
    (OUT_ROOT / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("V2-REPRESENTATIVE RTL MATRIX 48/48 PASS")


if __name__ == "__main__":
    main()
