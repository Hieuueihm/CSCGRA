"""Real-fabric smoke for the narrow panel's terminal R4 path.

The service-only test owns exhaustive mocked bridge/fault scheduling.  This
gate deliberately reuses the independent stream-kernel integer fixture so the
candidate reaches the actual stream_fabric/stream_array/stream_pe terminal.
"""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl
from verification.v4.test_stream_kernel_rtl import (SOURCES, _project_header,
    _vector_reads, _vector_writes, factor_project_update_sequence, pack,
    project_contexts, rounded)

ROOT = Path(__file__).resolve().parents[2]
EXTRAS = (
    "verification/v4/test_factor_panel_narrow_fabric_rtl.py",
    "verification/v4/test_stream_kernel_rtl.py",
    "rtl/v4/dataflow/factor_panel_service.sv",
    "docs/v4/architecture/NARROW_PANEL_MAPPING.md",
    "scripts/v4/xsim.py",
)


class NarrowPanelRealFabric(unittest.TestCase):
    @staticmethod
    def narrow_cases(rows, cols, row_start, length, col_start, alpha):
        """Independent integer fixture for a restricted private rectangle."""
        # Keep the C18 source values well inside range, but make all three
        # S27F22 round boundaries observable.  Small raw/V values can leave
        # q and therefore every rank-one write at zero, which is not a useful
        # check of the real terminal or cascade path.
        raw = [[1000 + ((23*r + 17*c + 5) % 997) for c in range(cols)]
               for r in range(rows)]
        factor = [[value << 6 for value in row] for row in raw]
        vector = [20000 + ((37*r + 11) % 20001) for r in range(length)]
        updated = [row[:] for row in factor]
        for col in range(col_start, cols):
            q = rounded(sum(factor[row_start + r][col] * vector[r] for r in range(length)), 22)
            scaled = rounded(q * alpha, 22)
            if q == 0 or scaled == 0:
                raise AssertionError("fixture must exercise dot and scale outputs")
            for r in range(length):
                updated[row_start + r][col] -= rounded(vector[r] * scaled, 22)
        if not any(updated[row_start + r][col] != factor[row_start + r][col]
                   for r in range(length) for col in range(col_start, cols)):
            raise AssertionError("fixture must exercise rank-one writes")
        fills = []
        for col in range(cols):
            for block in range((rows + 31) // 32):
                values = [raw[row][col] for row in range(block * 32, min(rows, block * 32 + 32))]
                fills.append(f"{col} {block} {(1 << len(values)) - 1:x} {pack(values, 18):x}")
        init = _project_header(13, rows, cols, rows, writes=_vector_writes(0, vector),
                               fills=fills, nonzero=1, expected_count=cols)
        compact = _project_header(20, rows, cols, length, scalar=alpha, descriptor=31,
                                  contexts=project_contexts(), writes=_vector_writes(0, vector),
                                  support_length=cols, aux_length=row_start, index=col_start,
                                  cancel=6, expected_count=0)
        # Read every column and row.  Selected cells prove the update, while
        # all other cells prove the restricted rectangle leaves factor state
        # untouched; this also catches C=8 leader packing in the middle lanes.
        reads = [_project_header(14, rows, cols, rows,
                                 nonzero=int(any(updated[r][col] for r in range(rows))),
                                 writes=_vector_writes(192, [17] * rows),
                                 reads=_vector_reads(192, [updated[r][col] for r in range(rows)]),
                                 destination=192, index=col, expected_count=rows)
                 for col in range(cols)]
        return [init, compact, *reads]

    def test_fractional_project_update_real_terminal_tail(self):
        folder = Path(tempfile.mkdtemp(prefix="narrow_panel_real_fabric_", dir=ROOT / "work"))
        before = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                  for path in dict.fromkeys([*SOURCES, *EXTRAS])}
        binary = folder / "kernel.xsim.json"
        compiled = compile_rtl(binary, "tb_stream_kernel", SOURCES, root=ROOT, timeout=240)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        cases, oracle = factor_project_update_sequence(rows=33, cols=17)
        # C=17 forces the final C=1 panel; the fixture's alpha is fractional,
        # V uses base zero, and the readbacks are exact independent integers.
        self.assertEqual(len(oracle["updated"]), 33)
        vectors = folder / "vectors.txt"
        vectors.write_text(str(len(cases)) + "\n" + "\n".join(cases) + "\n")
        result = run_rtl(binary, ["vectors=" + vectors.as_posix()], root=ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"PASS stream_kernel cycles=\d+ checks=\d+ commands=\d+ stalls=\d+")
        self.assertEqual(before, {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                                  for path in dict.fromkeys([*SOURCES, *EXTRAS])})
        record = {"status": "PASS", "scope": "actual stream_fabric R4 terminal; C=1 tail, M33, fractional alpha, base0 V",
                  "source_sha256": before, "vectors_sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
                  "commands": compiled.commands + result.commands, "stdout": result.stdout}
        (folder / "evidence.json").write_text(json.dumps(record, indent=2) + "\n")

    def test_direct_narrow_rectangles_real_fabric(self):
        folder = Path(tempfile.mkdtemp(prefix="narrow_panel_real_rectangles_", dir=ROOT / "work"))
        before = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                  for path in dict.fromkeys([*SOURCES, *EXTRAS])}
        binary = folder / "kernel.xsim.json"
        compiled = compile_rtl(binary, "tb_stream_kernel", SOURCES, root=ROOT, timeout=240)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        # M33 avoids the unrelated legacy factor-read partial-image fixture
        # limitation while still driving row_start=1/L30/C1.  M128/L65 gives
        # C=8 mapping with a nonzero column start and a two-block row tail.
        cases = [*self.narrow_cases(33, 17, 1, 30, 16, -3145728),
                 *self.narrow_cases(128, 17, 0, 65, 9, -3145728)]
        vectors = folder / "vectors.txt"
        vectors.write_text(str(len(cases)) + "\n" + "\n".join(cases) + "\n")
        result = run_rtl(binary, ["vectors=" + vectors.as_posix()], root=ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"PASS stream_kernel cycles=\d+ checks=\d+ commands=\d+ stalls=\d+")
        self.assertEqual(before, {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                                  for path in dict.fromkeys([*SOURCES, *EXTRAS])})
        record = {
            "status": "PASS",
            "scope": ("actual stream_fabric R4 terminal; M33 row_start=1/L30/C1 and "
                      "M128 row_start=0/L65/C8 nonzero-column rectangles; negative fractional "
                      "alpha; all factor rows and columns exact-readback"),
            "source_sha256": before,
            "vectors_sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
            "commands": compiled.commands + result.commands,
            "stdout": result.stdout,
        }
        (folder / "evidence.json").write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main()
