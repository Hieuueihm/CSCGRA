"""A/B schedule survey for the private PROJECT_DOT 8+tail optimization.

The fixture is intentionally separate from the permanent stream-kernel suite.
It uses the real factor store, panel, 32 PEs and fabric through the shared
driver, while an independent integer oracle validates every factor-column
column.  The wrapper reports accepted panel frames; it adds no runtime state.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]
BASE_PATH = ROOT / 'verification/v4/test_stream_kernel_rtl.py'
SPEC = importlib.util.spec_from_file_location('factor_project_dot_base', BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

WRAPPER = 'verification/v4/stream/tb_factor_project_dot_schedule_ab.sv'
TEST = 'verification/v4/test_factor_project_dot_schedule_ab_rtl.py'
SOURCES = BASE.SOURCES + [WRAPPER]
EXTRAS = BASE.SOURCE_EXTRAS + [TEST]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_cases(name: str, rows: int, cols: int, row_start: int, length: int,
                  col_start: int, alpha: int, mixed_signed: bool = False) -> tuple[list[str], dict]:
    """Independent S27 oracle for a restricted op20 factor rectangle."""
    assert 1 <= rows <= 128 and 1 <= cols <= 96
    assert 0 <= row_start and 1 <= length <= rows - row_start
    assert 0 <= col_start < cols
    raw = ([[((23 * row + 17 * col + 5) % 199 - 99) * 137
             for col in range(cols)] for row in range(rows)] if mixed_signed else
           [[1000 + ((23 * row + 17 * col + 5) % 997)
             for col in range(cols)] for row in range(rows)])
    factor = [[value << 6 for value in row] for row in raw]
    vector = [(((-1 if row % 3 == 1 else 1) if mixed_signed else 1) *
               (20000 + ((37 * row + 11) % 20001))) for row in range(length)]
    updated = [row[:] for row in factor]
    for col in range(col_start, cols):
        dot = BASE.rounded(sum(factor[row_start + row][col] * vector[row]
                               for row in range(length)), 22)
        scaled = BASE.rounded(alpha * dot, 22)
        for row in range(length):
            updated[row_start + row][col] -= BASE.rounded(vector[row] * scaled, 22)
    if not all(-(1 << 26) <= item < (1 << 26) for row in updated for item in row):
        raise AssertionError(f'{name}: fixture leaves S27 range')
    if alpha and not any(updated[row][col] != factor[row][col]
                         for row in range(row_start, row_start + length)
                         for col in range(col_start, cols)):
        raise AssertionError(f'{name}: nonzero alpha did not exercise rank update')
    fills = []
    for col in range(cols):
        for block in range((rows + 31) // 32):
            values = [raw[row][col]
                      for row in range(block * 32, min(rows, block * 32 + 32))]
            fills.append(f'{col} {block} {(1 << len(values)) - 1:x} {BASE.pack(values, 18):x}')
    init = BASE._project_header(13, rows, cols, rows, nonzero=1,
                                writes=BASE._vector_writes(0, vector), fills=fills,
                                expected_count=cols)
    project = BASE._project_header(20, rows, cols, length, scalar=alpha,
                                   descriptor=31, contexts=BASE.project_contexts(),
                                   support_length=cols, aux_length=row_start,
                                   index=col_start, cancel=6, expected_count=0)
    # Full factor-column readback makes each panel boundary and all untouched
    # prefix columns observable, while keeping the scenario set bounded.
    probes = range(cols)
    reads = []
    for col in probes:
        values = [updated[row][col] for row in range(rows)]
        reads.append(BASE._project_header(14, rows, cols, rows,
                                         nonzero=int(any(values)),
                                         writes=BASE._vector_writes(192, [17] * rows),
                                         reads=BASE._vector_reads(192, values),
                                         destination=192, index=col,
                                         expected_count=rows))
    return [init, project, *reads], dict(name=name, rows=rows, cols=cols,
                                         row_start=row_start, length=length,
                                         col_start=col_start, width=cols-col_start,
                                         alpha=alpha, mixed_signed=mixed_signed,
                                         updated=updated)


def narrow_dot_frames(length: int) -> int:
    """Existing residue schedule's exact accepted-frame count for <=8 columns."""
    remainder = length & 31
    return (length >> 5) * 8 + (8 if remainder > 8 else remainder)


def expected_dot_frames(length: int, width: int, split: bool) -> int:
    """Walk the exact per-panel DOT schedule, including a wide 32+16 tail."""
    frames, remaining = 0, width
    while remaining:
        panel = 8 if split and 9 <= remaining <= 16 else min(remaining, 32)
        frames += narrow_dot_frames(length) if panel <= 8 else length
        remaining -= panel
    return frames


def has_split_tail(width: int) -> bool:
    remaining = width
    while remaining:
        if 9 <= remaining <= 16:
            return True
        remaining -= min(remaining, 32)
    return False


# 38 representative positive cases, not a Cartesian product.  They cover the
# crossover around 32 rows, all requested widths and long-row savings, with
# nonzero row/column offsets, signed fractional alpha, mixed signs and a
# zero-alpha identity update.
CASES = (
    ('l16_w16', 16, 17, 0, 16, 1, (1 << 21) + 19),
    ('l18_w16', 18, 17, 0, 18, 1, -((1 << 21) + 23)),
    ('l20_w16', 20, 17, 0, 20, 1, (1 << 21) + 29),
    ('l22_w16', 22, 17, 0, 22, 1, -((1 << 21) + 31)),
    ('l23_w16', 23, 17, 0, 23, 1, (1 << 21) + 37),
    ('l24_w16', 24, 17, 0, 24, 1, -((1 << 21) + 41)),
    ('l25_w16', 25, 17, 0, 25, 1, (1 << 21) + 43),
    ('l26_w16', 26, 17, 0, 26, 1, -((1 << 21) + 45)),
    ('l27_w16', 27, 17, 0, 27, 1, -((1 << 21) + 47)),
    ('l28_w16', 28, 17, 0, 28, 1, (1 << 21) + 53),
    ('l29_w16', 29, 17, 0, 29, 1, -((1 << 21) + 59)),
    ('l30_w16', 30, 17, 0, 30, 1, (1 << 21) + 61),
    ('l31_w16', 31, 17, 0, 31, 1, -((1 << 21) + 67)),
    ('l32_w16', 32, 17, 0, 32, 1, (1 << 21) + 71),
    ('l33_w16', 33, 17, 0, 33, 1, -((1 << 21) + 73)),
    ('l34_w16', 34, 17, 0, 34, 1, (1 << 21) + 75),
    ('l35_w16', 35, 17, 0, 35, 1, -((1 << 21) + 77)),
    ('l36_w16', 36, 17, 0, 36, 1, (1 << 21) + 81),
    ('l37_w16', 37, 17, 0, 37, 1, -((1 << 21) + 85)),
    ('l38_w16', 38, 17, 0, 38, 1, (1 << 21) + 87),
    ('l39_w16', 39, 17, 0, 39, 1, -((1 << 21) + 91)),
    ('l40_w16', 40, 17, 0, 40, 1, (1 << 21) + 79),
    ('l41_w16', 41, 17, 0, 41, 1, -((1 << 21) + 93)),
    ('l47_w16', 47, 17, 0, 47, 1, (1 << 21) + 95),
    ('l48_w16', 48, 17, 0, 48, 1, -((1 << 21) + 83)),
    ('l64_w16', 64, 17, 0, 64, 1, (1 << 21) + 89),
    ('l63_w16', 63, 17, 0, 63, 1, -((1 << 21) + 99)),
    ('l65_w16', 65, 17, 0, 65, 1, (1 << 21) + 105),
    ('l128_w16', 128, 17, 0, 128, 1, -((1 << 21) + 97)),
    ('l64_w8', 64, 8, 0, 64, 0, (1 << 21) + 101),
    ('l64_w9_offset', 65, 17, 1, 64, 8, -((1 << 21) + 103)),
    ('l64_w12_offset', 66, 17, 2, 64, 5, (1 << 21) + 107),
    ('l24_w9', 25, 17, 1, 24, 8, -((1 << 21) + 111)),
    ('l24_w12', 26, 17, 2, 24, 5, (1 << 21) + 115),
    ('l64_w17', 64, 17, 0, 64, 0, -((1 << 21) + 109)),
    ('l64_w24', 64, 24, 0, 64, 0, (1 << 21) + 113),
    ('l64_w32_zero_alpha', 64, 32, 0, 64, 0, 0),
    ('l64_w48_mixed_tail', 68, 48, 4, 64, 0, -((1 << 21) + 127), True),
)


class FactorProjectDotScheduleAbRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_project_dot_schedule_', dir=ROOT / 'work'))
        cls.before = {name: sha(ROOT / name) for name in dict.fromkeys(SOURCES + EXTRAS)}
        cases, cls.oracles = [], []
        for args in CASES:
            sequence, oracle = project_cases(*args)
            cases.extend(sequence)
            cls.oracles.append(oracle)
        cls.command_count = len(cases)
        cls.vectors = cls.folder / 'project_dot_schedule_vectors.txt'
        cls.vectors.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n', encoding='utf-8')

    @classmethod
    def compile_and_run(cls, top: str, name: str):
        return cls.compile_vectors(top, name, cls.vectors, cls.command_count,
                                   expected_metrics=len(cls.oracles))

    @classmethod
    def compile_vectors(cls, top: str, name: str, vectors: Path, command_count: int,
                        expected_metrics: int | None = None):
        binary = cls.folder / f'{name}.xsim.json'
        compiled = compile_rtl(binary, top, SOURCES, root=ROOT, timeout=240)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        result = run_rtl(binary, [f'vectors={vectors.as_posix()}'], root=ROOT, timeout=600)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        pattern = re.compile(r'PROJECT_DOT_SCHEDULE tag=(\d+) cycles=(\d+) dot_frames=(\d+) '
                             r'scale_frames=(\d+) rank_frames=(\d+) split=(\d+) stalls=(\d+)')
        rows = [tuple(map(int, hit.groups())) for hit in pattern.finditer(result.stdout)]
        if expected_metrics is not None and len(rows) != expected_metrics:
            raise AssertionError(f'{name}: expected {expected_metrics} op20 metrics, got {len(rows)}\n{result.stdout}')
        if not re.search(rf'PASS stream_kernel cycles=\d+ checks=\d+ commands={command_count} stalls=\d+', result.stdout):
            raise AssertionError(result.stdout)
        return dict(name=name, top=top, binary=str(binary), metrics=rows,
                    commands=compiled.commands + result.commands, stdout=result.stdout)

    def test_split_threshold_ab_exact_outputs_and_phase_frames(self):
        baseline = self.compile_and_run('tb_factor_project_dot_schedule_baseline', 'baseline')
        enabled = self.compile_and_run('tb_factor_project_dot_schedule_enabled', 'enabled')
        forced = self.compile_and_run('tb_factor_project_dot_schedule_min1', 'min1')
        for index, oracle in enumerate(self.oracles):
            _, _, base_dot, base_scale, base_rank, base_split, base_stalls = baseline['metrics'][index]
            _, _, enabled_dot, enabled_scale, enabled_rank, enabled_split, enabled_stalls = enabled['metrics'][index]
            _, _, min1_dot, min1_scale, min1_rank, min1_split, min1_stalls = forced['metrics'][index]
            self.assertEqual((base_split, base_stalls), (0, 0), oracle['name'])
            expected_enabled = int(oracle['length'] >= 24 and has_split_tail(oracle['width']))
            expected_min1 = int(has_split_tail(oracle['width']))
            self.assertEqual(enabled_split, expected_enabled, oracle['name'])
            self.assertEqual(min1_split, expected_min1, oracle['name'])
            # SCALE/RANK are contractually unchanged.  DOT splitting changes
            # only DOT scheduling; exact factor readbacks are checked by the
            # shared real-store host oracle in every run.
            self.assertEqual((base_scale, base_rank), (enabled_scale, enabled_rank), oracle['name'])
            self.assertEqual((base_scale, base_rank), (min1_scale, min1_rank), oracle['name'])
            self.assertEqual(base_dot, expected_dot_frames(oracle['length'], oracle['width'], False), oracle['name'])
            self.assertEqual(enabled_dot, expected_dot_frames(oracle['length'], oracle['width'], bool(expected_enabled)), oracle['name'])
            self.assertEqual(min1_dot, expected_dot_frames(oracle['length'], oracle['width'], bool(expected_min1)), oracle['name'])
        self.assertEqual(self.before, {name: sha(ROOT / name) for name in dict.fromkeys(SOURCES + EXTRAS)})
        record = dict(status='PASS', scope='op20_real_factor_store_32PE_schedule_AB_no_stalls',
                      cases=[dict(name=row['name'], rows=row['rows'], width=row['width'],
                                  row_start=row['row_start'], length=row['length'], col_start=row['col_start'], alpha=row['alpha'],
                                  mixed_signed=row['mixed_signed'])
                             for row in self.oracles], baseline=baseline, enabled=enabled, min1=forced,
                      source_sha256=self.before, vectors_sha256=sha(self.vectors),
                      assertions=['exact_factor_readback_integer_oracle', 'enabled_split_threshold',
                                  'forced_min1_split_threshold', 'scale_rank_phase_frames_unchanged'])
        (self.folder / 'test_split_threshold_ab_exact_outputs_and_phase_frames.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')

    def test_enabled_schedule_preserves_outputs_under_legacy_stalls(self):
        record = self.compile_and_run('tb_factor_project_dot_schedule_enabled_stalls', 'enabled_stalls')
        for metric, oracle in zip(record['metrics'], self.oracles):
            self.assertEqual(metric[-1], 1, oracle['name'])
        self.assertEqual(self.before, {name: sha(ROOT / name) for name in dict.fromkeys(SOURCES + EXTRAS)})
        payload = dict(status='PASS', scope='op20_enabled_real_factor_store_legacy_absolute_stalls',
                       enabled_stalls=record, source_sha256=self.before,
                       vectors_sha256=sha(self.vectors),
                       assertion='shared driver exact integer factor readbacks remain valid under default stalls')
        (self.folder / 'test_enabled_schedule_preserves_outputs_under_legacy_stalls.json').write_text(
            json.dumps(payload, indent=2) + '\n', encoding='utf-8')

    def test_second_dot_cancel_and_fabric_fault_each_recover(self):
        """Marker26 sees valid second-DOT input; marker27 sees accepted output."""
        def marker6(record: str) -> str:
            lines = record.splitlines()
            fields = lines[0].split()
            fields[19] = '6'
            return '\n'.join([' '.join(fields), *lines[1:]])

        def interrupted(marker: int, expected_fault: int, name: str):
            sequence, _ = project_cases(name, 64, 17, 0, 64, 1, (1 << 21) + 149)
            fields = sequence[1].splitlines()[0].split()
            fields[16] = str(expected_fault)
            fields[19] = str(marker)
            fields[21] = '0'  # no host reads before cancellation/fault completion
            return [sequence[0], ' '.join(fields)]

        def invalidated_factor_read():
            # A factor read before the recovery INIT must reject with identity
            # fault 6: cancellation/fabric fault invalidates private ownership
            # rather than relying on the succeeding INIT to replace it.
            return BASE._project_header(14, 64, 17, 64, fault=6, nonzero=0,
                                        cancel=6, destination=192, index=0,
                                        expected_count=0)

        cancel = interrupted(26, 0, 'cancel_after_split') + [invalidated_factor_read()]
        fault = interrupted(27, 3, 'fault_after_split') + [invalidated_factor_read()]
        recovery_a, _ = project_cases('recovery_after_cancel', 64, 17, 0, 64, 1, (1 << 21) + 151)
        recovery_b, _ = project_cases('recovery_after_fault', 64, 17, 0, 64, 1, -((1 << 21) + 157))
        # A real initial reset occurs before each negative path.  The INIT
        # immediately after cancel/fault must instead recover in-place.
        recovery_a[0] = marker6(recovery_a[0])
        recovery_b[0] = marker6(recovery_b[0])
        cases = cancel + recovery_a + fault + recovery_b
        vectors = self.folder / 'project_dot_split_fault_cancel_vectors.txt'
        vectors.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n', encoding='utf-8')
        record = self.compile_vectors('tb_factor_project_dot_schedule_enabled_stalls',
                                      'enabled_stalls_fault_cancel', vectors, len(cases),
                                      expected_metrics=3)
        self.assertRegex(record['stdout'], r'PROJECT_DOT_SPLIT_CANCEL reached tag=2 col=9 width=8')
        self.assertRegex(record['stdout'], r'PROJECT_DOT_SPLIT_FAULT reached tag=24 col=9 width=8')
        self.assertEqual(self.before, {name: sha(ROOT / name) for name in dict.fromkeys(SOURCES + EXTRAS)})
        payload = dict(status='PASS',
                       scope='op20_split_second_dot_cancel_and_accepted_fabric_fault_then_fresh_INIT_recovery',
                       enabled_stalls=record, source_sha256=self.before,
                       vectors_sha256=sha(vectors),
                       assertions=['marker26_second_dot_valid_reached_no_stale_success',
                                   'marker27_second_dot_accepted_fault3',
                                   'post_cancel_and_post_fault_factor_read_identity_fault6',
                                   'fresh_INIT_exact_factor_readback_recovery'])
        (self.folder / 'test_second_dot_cancel_and_fabric_fault_each_recover.json').write_text(
            json.dumps(payload, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    unittest.main()
