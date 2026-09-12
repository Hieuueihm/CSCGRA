"""Integer-oracle selection/support checks against real shared RAM in Vivado xsim."""
import hashlib
import json
from pathlib import Path
import random
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]
RUNS = []
MASK = (1 << 27) - 1
SOURCE_PATHS = [
    'rtl/v4/dataflow/support_service.sv',
    'rtl/v4/memory/stream_vector_store.sv',
    'verification/v4/stream/tb_support_service.sv',
    'verification/v4/test_support_service_rtl.py',
    'config/v4_kernel_interface.json',
    'rtl/v4/include/kernel_interface.vh',
    'scripts/v4/xsim.py',
]
def source_hashes():
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in SOURCE_PATHS}


def packed(values):
    return sum((value & MASK) << (27 * lane) for lane, value in enumerate(values))


class SupportServiceRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = Path(tempfile.mkdtemp(prefix='support_service_', dir=ROOT / 'work'))
        cls.binary = cls.path / 'support.xsim.json'
        cls.sources = [ROOT / path for path in [
            'rtl/v4/dataflow/support_service.sv', 'rtl/v4/memory/stream_vector_store.sv',
            'verification/v4/stream/tb_support_service.sv']]
        cls.before = source_hashes()
        cls.compiled = compile_rtl(cls.binary, 'tb_support_service', cls.sources, root=ROOT, timeout=300)
        if cls.compiled.returncode:
            raise AssertionError(cls.compiled.stdout + cls.compiled.stderr)

    @classmethod
    def tearDownClass(cls):
        after = source_hashes()
        if cls.before != after:
            raise AssertionError('support test source changed while suite was running')
        (cls.path / 'evidence.json').write_text(json.dumps(RUNS, indent=2))
        (cls.path / 'source_closure.json').write_text(json.dumps({
            'status': 'PASS', 'source_sha256_before': cls.before,
            'source_sha256_after': after, 'run_count': len(RUNS)}, indent=2))

    def case(self, op, values, support=(), auxiliary=(), k=1, flags=0, index=0,
             fault=(0, 0), stall=1, inject=0, cancel=0, fmt=1, sparse=False,
             source_base=0, support_base=64, auxiliary_base=96, source_valid=None, auxiliary_valid=None, scalar=0):
        n = len(values)
        insert_value = scalar
        # Range requests reserve the legacy support-list interface: a nonzero
        # support base is itself a command fault, even with an empty list.
        if op >= 11 and not support:
            support_base = 0
        if op >= 11 and k == 1:
            k = 0
        fixture = self.path / f'case{len(RUNS)}.txt'
        trace = self.path / f'trace{len(RUNS)}.txt'
        lines = [f'{op} {n} {k} {flags} {len(support)} {len(auxiliary)} {index} {fmt} {stall} {inject} {cancel} {scalar & ((1 << 27) - 1)}',
                 f'{source_base} {support_base} {auxiliary_base}']
        blocks = []
        for base, data in [(source_base, values), (support_base, support), (auxiliary_base, auxiliary)]:
            for start in range(0, len(data), 32):
                chunk = list(data[start:start + 32])
                mask = (1 << len(chunk)) - 1
                if sparse and base == source_base:
                    mask = sum(1 << lane for lane in range(len(chunk)) if start + lane in support)
                if base == source_base and source_valid is not None:
                    mask = sum(1 << lane for lane in range(len(chunk)) if start + lane in source_valid)
                if base == auxiliary_base and auxiliary_valid is not None:
                    mask = sum(1 << lane for lane in range(len(chunk)) if start + lane in auxiliary_valid)
                if mask and base + start // 32 < 480:
                    blocks.append(f'{base + start // 32} {mask:08x} {packed(chunk):0216x}')
        fixture.write_text('\n'.join(lines + [str(len(blocks))] + blocks) + '\n')
        result = run_rtl(self.binary, ['+fixture=' + fixture.as_posix(), '+trace=' + trace.as_posix()],
                         root=ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS cycles=', result.stdout)
        expected = []
        scalar = 0
        count = 0
        if fault == (0, 0):
            if op == 5:
                excluded = set(support) if flags & 1 else set()
                expected = sorted((i for i in range(n) if i not in excluded), key=lambda i: (-abs(values[i]), i))[:k]
                if flags & 2:
                    expected.sort()
                count = len(expected)
            elif op == 9:
                expected = list(dict.fromkeys([*support, *auxiliary]))
                if not flags & 1:
                    expected.sort()
                count = len(expected)
            elif op == 6:
                expected = [value if i in support else 0 for i, value in enumerate(values)]
                count = len(support)
            elif op == 7:
                expected = [values[i] for i in support]
                count = len(support)
            elif op == 8:
                expected = [0] * n
                for i, target in enumerate(support):
                    expected[target] = values[i]
                count = len(support)
            elif op == 10:
                scalar = values[index]
            elif op == 11:
                expected = values[index:index + len(auxiliary)]
                count = len(expected)
            elif op == 12:
                expected = list(values)
                expected[index:index + len(auxiliary)] = auxiliary
                count = len(expected)
            elif op == 21:
                expected = list(values)
                expected[index] = insert_value
                count = len(expected)
        memory = [0] * 1024
        valid = [0] * 32
        comparisons = 0
        response = None
        for line in trace.read_text().splitlines():
            fields = line.split()
            if fields[0] == 'C':
                memory = [0] * 1024
                valid = [0] * 32
            elif fields[0] == 'W':
                block, mask, data = int(fields[1]), int(fields[2], 16), int(fields[3], 16)
                self.assertLess(block, 32)
                self.assertNotEqual(mask, 0)
                comparisons += 2
                valid[block] |= mask
                for lane in range(32):
                    raw = data >> (27 * lane) & MASK
                    if mask >> lane & 1:
                        memory[block * 32 + lane] = raw - (1 << 27) if raw & (1 << 26) else raw
            elif fields[0] == 'R':
                response = tuple(map(int, fields[1:5])) + (int(fields[5], 16), int(fields[6]))
            elif fields[0] == 'END':
                cycles, reads, writes, stalls, checks = map(int, fields[1:])
                comparisons += checks
        self.assertIsNotNone(response)
        self.assertEqual(response[:2], fault)
        comparisons += 2
        if fault == (0, 0):
            self.assertEqual(response[2:], (count, len(expected), scalar & ((1 << 64) - 1), int(any(expected) or scalar != 0)))
            self.assertEqual(memory[:len(expected)], expected)
            for block in range(32):
                self.assertEqual(valid[block], (1 << min(32, max(0, len(expected) - 32 * block))) - 1)
            comparisons += len(expected) + 33
        else:
            self.assertEqual(response[2:], (0, 0, 0, 0))
            comparisons += 1
        RUNS.append(dict(op=op, length=n, k=k, support_length=len(support), auxiliary_length=len(auxiliary),
                         flags=flags, cancel=cancel, inject=inject, fault=list(fault), cycles=cycles,
                         reads=reads, writes=writes, stalls=stalls, comparisons=comparisons,
                         status='PASS', comparison_kind='independent_integer_support_oracle_and_held_endpoint_assertions',
                         source_sha256=self.before, source_unchanged=source_hashes() == self.before,
                         simulator='Vivado xsim', returncode=result.returncode, stdout=result.stdout,
                         commands=self.compiled.commands + result.commands,
                         fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                         trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))
        return RUNS[-1]

    def test_scalar_insert_virtual_lane_and_reserved_opcode_gap(self):
        values = [i * 23 - 301 for i in range(1024)]
        for index, scalar in [(0, 0), (31, -17), (32, 1 << 21), (1023, -(1 << 26))]:
            self.case(21, values, index=index, scalar=scalar, auxiliary_base=0, support_base=0, stall=1)
        # Replaced source lane is not read.  The last block of 33/65-element
        # vectors can likewise be entirely virtual while earlier source blocks
        # remain valid and must be preserved exactly.
        n1_zero = self.case(21, [37], index=0, scalar=0, source_valid=(), auxiliary_base=0, support_base=0, stall=1)
        n1_nonzero = self.case(21, [37], index=0, scalar=-17, source_valid=(), auxiliary_base=0, support_base=0, stall=1)
        tail33 = self.case(21, list(range(33)), index=32, scalar=-19, source_valid=tuple(range(32)), auxiliary_base=0, support_base=0, stall=1)
        tail65 = self.case(21, [i - 41 for i in range(65)], index=64, scalar=0, source_valid=tuple(range(64)), auxiliary_base=0, support_base=0, stall=1)
        self.assertEqual(n1_zero['reads'], 0)
        self.assertEqual(n1_nonzero['reads'], 0)
        self.assertEqual(tail33['reads'], 1)
        self.assertEqual(tail65['reads'], 2)
        self.case(13, [1] * 33, fault=(1, 0), support_base=0, auxiliary_base=0)
    def test_range_transport_block_boundaries_and_source_masks(self):
        values = [(-1 if i & 1 else 1) * (i * 257 + 11) for i in range(128)]
        spans = (1, 31, 32, 33, 65, 96, 127, 128)
        starts = (0, 1, 31, 32, 33)
        for start in starts:
            for span in spans:
                if start + span <= len(values):
                    auxiliary = [700003 + 13 * i for i in range(span)]
                    self.case(11, values, auxiliary=auxiliary, index=start, stall=1)
                    self.case(12, values, auxiliary=auxiliary, index=start, stall=1)
        # The public range domain is 1024 entries / 32 output blocks.
        full = [(-1 if i & 1 else 1) * (i * 101 + 5) for i in range(1024)]
        self.case(11, full, auxiliary=full, index=0, stall=0)
        self.case(12, full, auxiliary=list(reversed(full)), index=0, stall=0)
        # Lanes replaced by aux are not required source operands.  The middle
        # source block has no valid lanes, while output still needs blocks 0/2.
        self.case(12, values[:65], auxiliary=[-2000 - i for i in range(33)], index=31,
                  source_valid=list(range(31)) + [64], auxiliary_valid=list(range(33)), stall=1)
        # A missing required auxiliary lane and corrupted read metadata fault;
        # no range transport may consume an unchecked provider response.
        self.case(12, values[:65], auxiliary=[-2000 - i for i in range(33)], index=31,
                  source_valid=list(range(31)) + [64], auxiliary_valid=list(range(32)), fault=(7, 5), stall=1)
        for inject, fault in [(1, (6, 5)), (2, (5, 4)), (3, (7, 7))]:
            self.case(12, values[:65], auxiliary=[-2000 - i for i in range(33)], index=31,
                      inject=inject, fault=fault, stall=1)

    def test_range_transport_empty_invalid_alias_and_cancel_restart(self):
        values = [i * 31 - 1000 for i in range(128)]
        # Empty SLICE has no candidate write; empty REPLACE copies its source.
        self.case(11, values, auxiliary=[], index=0, stall=1)
        self.case(12, values, auxiliary=[], index=0, stall=1)
        self.case(11, values, support=[0], auxiliary=[1], index=0, fault=(1, 0))
        self.case(12, values, auxiliary=[1] * 33, index=96, fault=(4, 0))
        # Source/aux physical aliases remain legal: service output is candidate
        # scratch (480 + candidate block), never either public input block.
        self.case(12, values[:32], auxiliary=values[:31], index=1, source_base=448, auxiliary_base=448, stall=1)
        for cancel in range(1, 6):
            self.case(12, values[:65], auxiliary=[-i - 1 for i in range(33)], index=31, cancel=cancel, stall=1)

    def test_range_cache_boundary_reuse_and_legacy_bypass(self):
        values = [i * 101 - 7000 for i in range(128)]
        # One output block and an aligned multi-block slice have no shared
        # provider, so they deliberately retain the direct legacy schedule.
        self.assertEqual(self.case(11, values, auxiliary=values[:32], index=1, stall=1)['reads'], 2)
        self.assertEqual(self.case(11, values, auxiliary=values[:65], index=32, stall=1)['reads'], 3)
        # An unaligned multi-block interval requests each physical word once
        # with its command-wide required mask, then hits on the next output.
        reused = self.case(11, values, auxiliary=values[:65], index=1, stall=1)
        self.assertEqual(reused['reads'], 3)
        # REPLACE has the same boundary cache but preserves source/aux alias
        # semantics and the existing exact output oracle.
        replace = self.case(12, values, auxiliary=[-3000 - i for i in range(65)], index=1, stall=1)
        self.assertLess(replace['reads'], 8)

    def test_topk_ties_extrema_exclusion_sort_and_full_capacity(self):
        self.case(5, [-(1 << 26)], k=1)
        values = [0, -7, 7, -3, 3, -(1 << 26), (1 << 26) - 1] * 5
        self.case(5, values, k=17)
        self.case(5, values, support=[5, 5, 12, 19], k=32, flags=3)
        self.case(5, [0] * 33, k=33)
        self.case(5, [1, 2], support=[0, 1], k=2, flags=1)
        rng = random.Random(721)
        self.case(5, [rng.randrange(-(1 << 26), 1 << 26) for _ in range(1024)], k=1024, flags=2, stall=0)

    def test_topk_multiblock_winner_cache_reuses_validated_blocks(self):
        values = [((i * 7919) % (1 << 26)) * (-1 if i & 2 else 1) for i in range(1024)]
        # Initial cache fill reads all 32 words once.  Every remaining result
        # rereads exactly the block whose cached winner was consumed.
        cached = self.case(5, values, k=8, stall=1)
        self.assertEqual(cached['reads'], 32 + 7)
        # A non-multiple-of-32 source retains its tail mask and the same read
        # formula; stalls exercise request/response payload holding.
        tail = self.case(5, values[:65], k=3, stall=1)
        self.assertEqual(tail['reads'], 3 + 2)
        # K=1 and a one-word source intentionally retain the legacy scan.
        self.assertEqual(self.case(5, values, k=1, stall=1)['reads'], 32)
        self.assertEqual(self.case(5, values[:32], k=8, stall=1)['reads'], 8)
        # Validation happens before cached data can be used.  Every endpoint
        # cancel/reset case restarts against the same preloaded public RAM.
        for inject, fault in [(1, (6, 5)), (2, (5, 4)), (3, (7, 7))]:
            self.case(5, values[:65], k=3, inject=inject, fault=fault, stall=1)
        for cancel in range(1, 6):
            self.case(5, values[:65], k=3, cancel=cancel, stall=1)

    def test_topk_two_word_break_even_measurement(self):
        values = [((i * 31337) % (1 << 25)) * (-1 if i & 1 else 1) for i in range(64)]
        # This small geometry is recorded in the source-bound evidence for
        # candidate-vs-legacy selection policy; both retain the same oracle.
        self.assertEqual(self.case(5, values, k=1, stall=1)['reads'], 2)
        # N64/K2 measured slower through the global tree, so it stays legacy.
        self.assertEqual(self.case(5, values, k=2, stall=1)['reads'], 4)
        self.assertEqual(self.case(5, values, k=3, stall=1)['reads'], 4)
        self.assertEqual(self.case(5, values * 4, k=2, stall=1)['reads'], 9)

    def test_apply_gather_scatter_pick_and_empty_support(self):
        values = [(-1 if i & 1 else 1) * (i * 109 + 3) for i in range(1024)]
        for op in (6, 7, 8):
            self.case(op, values[:35], support=[34, 0, 17, 32])
            self.case(op, values[:33], support=[])
            self.case(op, values, support=list(range(1023, -1, -1)), stall=0)
        self.case(6, values[:35], support=[34, 0, 17], sparse=True)
        self.case(7, values[:35], support=[34, 0, 17], sparse=True)
        self.case(10, values, index=1023)
        self.case(10, [-(1 << 26)], index=0)
        self.case(10, values, index=1023, source_base=448)

    def test_union_sorted_ordered_dedup_empty_and_full_domain(self):
        self.case(9, [0] * 35, support=[7, 2, 7, 34], auxiliary=[2, 1, 0, 1], k=8)
        self.case(9, [0] * 35, support=[7, 2, 7, 34], auxiliary=[2, 1, 0, 1], k=8, flags=1)
        self.case(9, [0], k=1)
        self.case(9, [0] * 1024, support=list(range(1023, -1, -1)), auxiliary=list(range(1024)), k=1024, stall=0)

    def test_invalid_indices_capacity_flags_identity_and_source_masks(self):
        self.case(9, [0] * 4, support=[0, 1], auxiliary=[2], k=2, fault=(4, 3))
        for op in (6, 7, 8):
            self.case(op, [1] * 4, support=[1, 1], fault=(1, 2))
        self.case(7, [1] * 4, support=[-1], fault=(4, 1))
        self.case(7, [1] * 4, support=[4], fault=(4, 1))
        self.case(5, [1], flags=4, fault=(1, 0))
        self.case(5, [1], k=0, fault=(4, 0))
        self.case(10, [1], index=1, fault=(4, 0))
        self.case(10, [1], fmt=2, fault=(1, 0))
        for inject, fault in [(1, (6, 5)), (2, (5, 4)), (3, (7, 7))]:
            self.case(5, [1] * 33, inject=inject, fault=fault)
        self.case(5, [1] * 33, sparse=True, fault=(7, 5))
        self.case(10, [1] * 33, source_base=479, fault=(4, 0))
        self.case(7, [1] * 33, support=[0], support_base=480, fault=(4, 0))
        self.case(9, [1] * 33, auxiliary=[0], auxiliary_base=480, fault=(4, 0))

    def test_cancel_and_reset_each_endpoint_then_restart_preloaded_ram(self):
        for cancel in range(1, 6):
            self.case(7, list(range(35)), support=[34, 0, 17], cancel=cancel)


if __name__ == '__main__':
    unittest.main()
