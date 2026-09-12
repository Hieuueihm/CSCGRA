"""Standalone Vivado A/B checks for support-service bitmap enumeration.

The two elaborations use the same fixture and a command-relative stall phase.
They compare integer selection results and transaction endpoints; measured
cycles/state occupancy are recorded but never treated as a performance claim.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]
MASK27 = (1 << 27) - 1
SOURCE_PATHS = [
    'rtl/v4/dataflow/support_service.sv',
    'rtl/v4/memory/stream_vector_store.sv',
    'rtl/v4/include/kernel_interface.vh',
    'config/v4_kernel_interface.json',
    'verification/v4/stream/tb_support_bitmap_ab.sv',
    'verification/v4/test_support_bitmap_ab_rtl.py',
    'scripts/v4/xsim.py',
]
RUNS: list[dict] = []


def packed(values: list[int]) -> int:
    return sum((value & MASK27) << (27 * lane) for lane, value in enumerate(values))


def signed27(raw: int) -> int:
    return raw - (1 << 27) if raw & (1 << 26) else raw


def source_hashes() -> dict[str, str]:
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in SOURCE_PATHS}


def topk_oracle(values: list[int], support: list[int], k: int, flags: int) -> list[int]:
    excluded = set(support) if flags & 1 else set()
    output = sorted((index for index in range(len(values)) if index not in excluded),
                    key=lambda index: (-abs(values[index]), index))[:k]
    return sorted(output) if flags & 2 else output


def union_oracle(support: list[int], auxiliary: list[int], flags: int) -> list[int]:
    ordered = list(dict.fromkeys([*support, *auxiliary]))
    return ordered if flags & 1 else sorted(ordered)


class SupportBitmapAbRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = Path(tempfile.mkdtemp(prefix='support_bitmap_ab_', dir=ROOT / 'work'))
        cls.before = source_hashes()
        cls.binaries = {}
        sources = [ROOT / path for path in [
            'rtl/v4/dataflow/support_service.sv',
            'rtl/v4/memory/stream_vector_store.sv',
            'verification/v4/stream/tb_support_bitmap_ab.sv',
        ]]
        for label, top in (('off', 'tb_support_bitmap_off'), ('on', 'tb_support_bitmap_on')):
            binary = cls.path / f'support_bitmap_{label}.xsim.json'
            compiled = compile_rtl(binary, top, sources, root=ROOT, timeout=300)
            if compiled.returncode:
                raise AssertionError(compiled.stdout + compiled.stderr)
            cls.binaries[label] = (binary, compiled.commands)

    @classmethod
    def tearDownClass(cls):
        after = source_hashes()
        if after != cls.before:
            raise AssertionError('bitmap A/B source changed while gate ran')
        (cls.path / 'evidence.json').write_text(json.dumps(RUNS, indent=2) + '\n', encoding='utf-8')
        (cls.path / 'source_closure.json').write_text(json.dumps({
            'status': 'PASS', 'source_sha256_before': cls.before,
            'source_sha256_after': after, 'run_count': len(RUNS),
            'scope': 'standalone OFF/ON support-service leaf comparison only',
        }, indent=2) + '\n', encoding='utf-8')

    def fixture(self, *, op: int, values: list[int], k: int, flags: int = 0,
                support: list[int] = (), auxiliary: list[int] = (), index: int = 0,
                stall: int = 1, inject: int = 0, cancel: int = 0, fmt: int = 1) -> Path:
        sequence = len(RUNS)
        path = self.path / f'case{sequence}.txt'
        bases = (0, 64, 96)
        lines = [f'{op} {len(values)} {k} {flags} {len(support)} {len(auxiliary)} {index} {fmt} {stall} {inject} {cancel} 0',
                 f'{bases[0]} {bases[1]} {bases[2]}']
        blocks: list[str] = []
        for base, data in zip(bases, (values, support, auxiliary)):
            for start in range(0, len(data), 32):
                part = data[start:start + 32]
                blocks.append(f'{base + start // 32} {(1 << len(part)) - 1:08x} {packed(part):0216x}')
        return self.write_fixture(path, lines, blocks)

    @staticmethod
    def write_fixture(path: Path, lines: list[str], blocks: list[str]) -> Path:
        path.write_text('\n'.join(lines + [str(len(blocks))] + blocks) + '\n', encoding='utf-8')
        return path

    @staticmethod
    def parse_trace(path: Path) -> dict:
        values: list[int] = []
        valid = [0] * 32
        writes: list[tuple[int, int, int]] = []
        response = None
        metrics = None
        for line in path.read_text(encoding='utf-8').splitlines():
            fields = line.split()
            if fields[0] == 'W':
                block, mask, data = int(fields[1]), int(fields[2], 16), int(fields[3], 16)
                writes.append((block, mask, data))
                valid[block] |= mask
                for lane in range(32):
                    if mask >> lane & 1:
                        point = block * 32 + lane
                        while len(values) <= point:
                            values.append(0)
                        values[point] = signed27((data >> (27 * lane)) & MASK27)
            elif fields[0] == 'R':
                response = (int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4]),
                            int(fields[5], 16), int(fields[6]))
            elif fields[0] == 'END':
                metrics = tuple(map(int, fields[1:]))
        if response is None or metrics is None:
            raise AssertionError(f'missing response or metrics in {path}')
        return {'response': response, 'values': values, 'valid': valid, 'writes': writes, 'metrics': metrics}

    def run_pair(self, fixture: Path) -> tuple[dict, dict, dict]:
        records = {}
        for label, (binary, commands) in self.binaries.items():
            trace = self.path / f'{fixture.stem}_{label}.trace'
            result = run_rtl(binary, ['+fixture=' + fixture.as_posix(), '+trace=' + trace.as_posix()],
                             root=ROOT, timeout=600)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(f'PASS bitmap={0 if label == "off" else 1}', result.stdout)
            records[label] = dict(parsed=self.parse_trace(trace), stdout=result.stdout,
                                  commands=commands + result.commands,
                                  trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest())
        self.assertEqual(records['off']['parsed']['response'], records['on']['parsed']['response'])
        self.assertEqual(records['off']['parsed']['values'], records['on']['parsed']['values'])
        self.assertEqual(records['off']['parsed']['valid'], records['on']['parsed']['valid'])
        self.assertEqual(records['off']['parsed']['writes'], records['on']['parsed']['writes'])
        return records['off']['parsed'], records['on']['parsed'], records

    def check_case(self, *, op: int, values: list[int], k: int, flags: int = 0,
                   support: list[int] = (), auxiliary: list[int] = (), index: int = 0,
                   fault: tuple[int, int] = (0, 0), stall: int = 1, inject: int = 0,
                   cancel: int = 0, expected: list[int] | None = None) -> dict:
        fixture = self.fixture(op=op, values=values, k=k, flags=flags, support=support,
                               auxiliary=auxiliary, index=index, stall=stall, inject=inject,
                               cancel=cancel)
        off, on, raw = self.run_pair(fixture)
        response = off['response']
        self.assertEqual(response[:2], fault)
        if expected is None and fault == (0, 0):
            expected = topk_oracle(values, list(support), k, flags) if op == 5 else union_oracle(list(support), list(auxiliary), flags)
        if fault == (0, 0):
            assert expected is not None
            self.assertEqual(response[2:], (len(expected), len(expected), 0, int(any(expected))))
            self.assertEqual(off['values'][:len(expected)], expected)
            for block in range(32):
                width = min(32, max(0, len(expected) - block * 32))
                self.assertEqual(off['valid'][block], (1 << width) - 1)
        else:
            self.assertEqual(response[2:], (0, 0, 0, 0))
            self.assertEqual(off['writes'], [])
            self.assertEqual(off['valid'], [0] * 32)
        record = dict(status='PASS', op=op, length=len(values), k=k, flags=flags,
                      support=list(support), auxiliary=list(auxiliary), index=index,
                      expected_fault=list(fault), cancel=cancel, inject=inject,
                      fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                      off=raw['off'], on=raw['on'], source_sha256=self.before,
                      stall_policy='identical command-relative grant phases: read=mod7, response=mod9, write=mod5',
                      comparison_kind='integer_oracle_OFF_ON_exact_result_count_order_fault_and_held_endpoint_equivalence')
        RUNS.append(record)
        return record

    def test_topk_domain_k_ties_extrema_and_exclusions(self):
        shapes = ((1, 1), (31, 1), (32, 2), (33, 3), (64, 8), (65, 62), (65, 65), (256, 8), (1024, 1024))
        for size, k in shapes:
            values = [((index * 7919) % ((1 << 25) - 1)) * (-1 if index & 2 else 1) for index in range(size)]
            values[0] = -(1 << 26)
            self.check_case(op=5, values=values, k=k, flags=2, stall=1)
        tied = [0, -7, 7, -3, 3, -(1 << 26), (1 << 26) - 1] * 5
        self.check_case(op=5, values=tied, k=17, flags=2, stall=1)
        self.check_case(op=5, values=tied, k=8, flags=3, support=[5, 5, 12, 19], stall=1)
        # K remains legal while a complete excluded set returns zero; all-zero
        # scores are still eligible and exercise sorted output publication.
        self.check_case(op=5, values=[9, -9, 0, 4, -4], k=3, flags=3, support=[0, 1, 2, 3, 4])
        self.check_case(op=5, values=[0] * 33, k=8, flags=2, stall=1)
        # K remains legal while an all-domain exclusion yields the successful
        # zero-result case.  All-zero scores, conversely, remain eligible.
        self.check_case(op=5, values=[9, -9, 0, 4, -4], k=3, flags=1, support=[0, 1, 2, 3, 4])
        self.check_case(op=5, values=[0] * 33, k=8, flags=2, stall=1)

    def test_union_empty_overlap_ordering_and_capacity_faults(self):
        self.check_case(op=9, values=[0], k=1, support=[], auxiliary=[], flags=0)
        support, auxiliary = [7, 2, 7, 34, 33], [2, 1, 0, 1, 34]
        self.check_case(op=9, values=[0] * 65, k=8, support=support, auxiliary=auxiliary, flags=0, stall=1)
        ordered = self.check_case(op=9, values=[0] * 65, k=8, support=support, auxiliary=auxiliary, flags=1, stall=1)
        self.assertEqual(ordered['on']['parsed']['metrics'][6], 0)
        self.check_case(op=9, values=[0] * 4, k=2, support=[0, 1], auxiliary=[2], fault=(4, 3))

    def test_faults_held_endpoints_cancel_reset_and_recovery(self):
        values = [((index * 31337) % (1 << 25)) * (-1 if index & 1 else 1) for index in range(65)]
        self.check_case(op=5, values=values, k=0, fault=(4, 0))
        self.check_case(op=5, values=values, k=3, flags=4, fault=(1, 0))
        for inject, fault in ((1, (6, 5)), (2, (5, 4)), (3, (7, 7))):
            self.check_case(op=5, values=values, k=3, flags=2, inject=inject, fault=fault, stall=1)
        for cancel in range(1, 6):
            self.check_case(op=5, values=values, k=8, flags=2, cancel=cancel, stall=1)

    def test_bitmap_state_is_measured_not_a_cycle_claim(self):
        values = [((index * 101) % 10007) * (-1 if index & 1 else 1) for index in range(1024)]
        topk = self.check_case(op=5, values=values, k=8, flags=2, stall=1)
        union_sparse = self.check_case(op=9, values=[0] * 1024, k=8,
                                       support=[0, 63, 64], auxiliary=[255, 511, 1023], flags=0, stall=1)
        for record in (topk, union_sparse):
            self.assertEqual(record['off']['parsed']['metrics'][6], 0)
            self.assertGreater(record['on']['parsed']['metrics'][6], 0)
        union_dense = self.check_case(op=9, values=[0] * 1024, k=1024,
                                      support=list(range(1023, -1, -1)), auxiliary=list(range(1024)), flags=0, stall=1)
        self.assertEqual(union_dense['on']['parsed']['metrics'][6], 0)
        self.assertEqual(union_dense['on']['parsed']['metrics'][5], union_dense['off']['parsed']['metrics'][5])
        # Ordered UNION is contractually excluded from bitmap enumeration.
        ordered = self.check_case(op=9, values=[0] * 256, k=256,
                                  support=list(range(255, -1, -1)), auxiliary=list(range(256)), flags=1, stall=1)
        self.assertEqual(ordered['on']['parsed']['metrics'][6], 0)

    def test_sparse_bitmap_bound_and_dense_fallback_state_occupancy(self):
        size = 1024
        keep = (0, 63, 64, 255, 511, 1023)
        values = [0] * size
        for rank, index in enumerate(keep):
            values[index] = (rank + 1) * (1009 if rank & 1 else -1009)
        sparse = self.check_case(op=5, values=values, k=len(keep), flags=3,
                                 support=[index for index in range(size) if index not in keep], stall=1)
        sparse_metrics = sparse['on']['parsed']['metrics']
        blocks = (size + 31) // 32
        # One word visit per bitmap word, one direct least-set-bit emission per
        # selected result, then the terminal transition.  Empty words between
        # selected positions remain part of the explicit bound.
        self.assertLessEqual(sparse_metrics[6], blocks + len(keep) + 1)
        self.assertEqual(sparse_metrics[7], len(keep))
        dense = self.check_case(op=5, values=list(range(size)), k=size, flags=2, stall=1)
        # B + K >= N selects the exact legacy linear SORT path, including its
        # state occupancy; this is a regression guard, not a speedup claim.
        self.assertEqual(dense['on']['parsed']['metrics'][6], 0)
        self.assertEqual(dense['on']['parsed']['metrics'][5], dense['off']['parsed']['metrics'][5])

    def test_threshold_boundary_and_cancel_inside_bitmap_word(self):
        values = [((index * 31337) % (1 << 25)) * (-1 if index & 1 else 1) for index in range(65)]
        sparse = self.check_case(op=5, values=values, k=61, flags=2, stall=1)
        fallback = self.check_case(op=5, values=values, k=62, flags=2, stall=1)
        self.assertGreater(sparse['on']['parsed']['metrics'][6], 0)
        self.assertEqual(fallback['on']['parsed']['metrics'][6], 0)
        self.assertEqual(fallback['on']['parsed']['metrics'][5], fallback['off']['parsed']['metrics'][5])
        keep = (0, 1, 2, 3, 31, 32, 64)
        sparse_values = [0] * 65
        for rank, index in enumerate(keep):
            sparse_values[index] = (rank + 1) * 4099
        self.check_case(op=5, values=sparse_values, k=len(keep), flags=3,
                        support=[index for index in range(65) if index not in keep], cancel=6, stall=1)
        self.check_case(op=5, values=sparse_values, k=len(keep), flags=3,
                        support=[index for index in range(65) if index not in keep], cancel=7, stall=1)


if __name__ == '__main__':
    unittest.main()
