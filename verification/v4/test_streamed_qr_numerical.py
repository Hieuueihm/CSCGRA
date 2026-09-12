"""Feature6 streamed QR scalar-insert compiler/VM gates.

These are integer-program checks only.  They compare the new streamed image to
the existing compact image; neither result is RTL qualification.
"""
import hashlib
import json
from pathlib import Path
import unittest

import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode, unpack
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'work' / 'streamed_qr_numerical_20260910'
SOURCES = (
    'compiler/v4/qr_program.py',
    'compiler/v4/greedy_qr_emit.py',
    'compiler/v4/recovery_emit.py',
    'compiler/v4/recovery_program.py',
    'models/v4/fixed.py',
    'models/v4/lfsr_operator.py',
    'models/v4/recovery.py',
    'verification/v4/recovery_program_vm.py',
    'verification/v4/recovery_program_vm_reference.py',
    'verification/v4/test_streamed_qr_numerical.py',
)


def source_hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}


def digest(values):
    return hashlib.sha256(','.join(str(int(value)) for value in values).encode()).hexdigest()


def pcs(package, opcode):
    return [pc for pc, word in enumerate(package['program'])
            if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == opcode]


def trace_count(package, result, opcode):
    positions = set(pcs(package, opcode))
    return sum(pc in positions for pc in result['trace'])


class StreamedQrNumericalTests(unittest.TestCase):
    @staticmethod
    def fixture(rows, columns, seed, measurement_seed, scale=8192):
        matrix = lfsr32_matrix(seed, rows, columns, scale=scale) / 65536.0
        measurement = np.random.default_rng(measurement_seed).integers(-4096, 4097, rows) / 16384.0
        return matrix, measurement

    def assert_exact(self, expected, observed):
        self.assertEqual(list(observed['x']), list(expected['x']))
        self.assertEqual(list(observed['residual']), list(expected['residual']))
        self.assertEqual((observed['support'], observed['status'], observed['outer'], observed['inner']),
                         (expected['support'], expected['status'], expected['outer'], expected['inner']))

    def record(self, name, *, compact, streamed, result, reference, matrix, policy, extra=None):
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        payload = dict(
            test=self.id(), status='PASS',
            scope='executed compact-versus-streamed integer VM comparison; not RTL evidence; reference VM shares Arithmetic implementation',
            algorithm=streamed['algorithm'], rows=int(matrix.shape[0]), columns=int(matrix.shape[1]),
            policy=policy, source_sha256=source_hashes(),
            image=dict(compact_words=len(compact['program']), streamed_words=len(streamed['program']),
                       compact_templates=len(compact['templates']), streamed_templates=len(streamed['templates']),
                       required_kernel_revision=streamed['required_kernel_revision'],
                       qr_stream_scalar_insert_enabled=streamed['qr_stream_scalar_insert_enabled']),
            result=dict(status=result['status'], outer=result['outer'], inner=result['inner'], support=list(result['support']),
                        raw_x_sha256=digest(result['x']), raw_r_sha256=digest(result['residual']),
                        op19_trace_count=trace_count(streamed, result, 19),
                        op20_trace_count=trace_count(streamed, result, 20),
                        op21_trace_count=trace_count(streamed, result, 21)),
            reference=dict(status=reference['status'], outer=reference['outer'], inner=reference['inner'],
                           raw_x_sha256=digest(reference['x']), raw_r_sha256=digest(reference['residual'])),
            **(extra or {}))
        (EVIDENCE / f'{name}.json').write_text(json.dumps(payload, indent=2) + '\n')

    def test_streamed_scalar_fields_are_canonical(self):
        matrix, _ = self.fixture(32, 64, 0x12345678, 17)
        package = compile_greedy_qr('CoSaMP', matrix, Policy(8, max_iterations=2, residual_atol=0),
                                    qr_profile='streamed')
        self.assertEqual(package['required_kernel_revision'], 6)
        self.assertTrue(package['qr_scalar_insert_enabled'])
        self.assertTrue(package['qr_stream_scalar_insert_enabled'])
        fields = []
        for pc in pcs(package, 21):
            decoded = decode(package['program'][pc])
            immediate = unpack(ABI['service_immediate_fields'], decoded['immediate'])
            fields.append((decoded['a_s'], immediate['index_s'], immediate['length']))
            self.assertEqual((decoded['dst_v'], decoded['a_v'], decoded['b_v'], decoded['dst_s'],
                              decoded['b_s'], decoded['flag_s'], decoded['target']),
                             (decoded['dst_v'], decoded['a_v'], 0, 0, 0, 0, 0))
        # S27F22 one comes from R15; tau/beta use their existing scalar RFs;
        # backsolve preserves compact's R5 insertion at the current R1 index.
        self.assertIn((15, 0, 2), fields)
        self.assertIn((8, 1, 28), fields)
        self.assertIn((6, 0, 2), fields)
        self.assertIn((5, 1, 28), fields)

    def test_m32_and_m64_raw_results_match_compact(self):
        for rows, columns, seed, measurement_seed in ((32, 64, 0x12345678, 177), (64, 256, 0x9E3779B9, 311)):
            with self.subTest(rows=rows, columns=columns):
                matrix, measurement = self.fixture(rows, columns, seed, measurement_seed)
                policy = Policy(8, max_iterations=2, residual_atol=0)
                compact = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='compact')
                streamed = compile_greedy_qr('CoSaMP', matrix, policy, qr_profile='streamed')
                baseline = execute(compact, matrix, measurement, limit=5_000_000)
                result = execute(streamed, matrix, measurement, limit=5_000_000)
                reference = reference_execute(streamed, matrix, measurement, limit=5_000_000)
                self.assert_exact(baseline, result)
                self.assert_exact(baseline, reference)
                self.assertGreater(trace_count(streamed, result, 21), trace_count(compact, baseline, 21))
                self.record(f'cosamp_m{rows}_n{columns}', compact=compact, streamed=streamed,
                            result=result, reference=reference, matrix=matrix, policy=policy.__dict__)

    def test_omp_refinement_executes_streamed_insert_after_extend(self):
        matrix, measurement = self.fixture(16, 32, 0x12345678, 1)
        policy = Policy(4, max_iterations=3, residual_atol=0, ls_normal_rtol=1e-6)
        compact = compile_greedy_qr('OMP', matrix, policy, qr_profile='compact')
        streamed = compile_greedy_qr('OMP', matrix, policy, qr_profile='streamed')
        baseline = execute(compact, matrix, measurement, limit=3_000_000)
        result = execute(streamed, matrix, measurement, limit=3_000_000)
        reference = reference_execute(streamed, matrix, measurement, limit=3_000_000)
        self.assert_exact(baseline, result)
        self.assert_exact(baseline, reference)
        extensions = [i for i, pc in enumerate(result['trace']) if pc in set(pcs(streamed, 19))]
        solve_calls = [i for i, pc in enumerate(result['trace']) if pc == streamed['labels']['qr_solve']]
        insertions = [i for i, pc in enumerate(result['trace']) if pc in set(pcs(streamed, 21))]
        self.assertGreaterEqual(len(extensions), 2)
        self.assertGreaterEqual(len(solve_calls), 3, 'initial plus correction solves must be visible in the trace')
        self.assertTrue(any(point > solve_calls[1] for point in insertions))
        self.record('omp_refinement', compact=compact, streamed=streamed, result=result, reference=reference,
                    matrix=matrix, policy=policy.__dict__,
                    extra=dict(actual_refinement=True, first_extend_trace_index=extensions[0],
                               qr_solve_trace_indices=solve_calls, scalar_insert_trace_indices=insertions))

    def test_gomp_support96_matches_compact(self):
        matrix, measurement = self.fixture(128, 128, 0x12345678, 911, scale=4096)
        policy = Policy(2, max_iterations=2, group_size=48, residual_atol=0)
        compact = compile_greedy_qr('GOMP', matrix, policy, qr_profile='compact')
        streamed = compile_greedy_qr('GOMP', matrix, policy, qr_profile='streamed')
        baseline = execute(compact, matrix, measurement, limit=5_000_000)
        result = execute(streamed, matrix, measurement, limit=5_000_000)
        reference = reference_execute(streamed, matrix, measurement, limit=5_000_000)
        self.assert_exact(baseline, result)
        self.assert_exact(baseline, reference)
        self.assertEqual(len(result['support']), 96)
        self.assertGreater(trace_count(streamed, result, 19), 0)
        self.assertGreater(trace_count(streamed, result, 20), 0)
        self.assertGreater(trace_count(streamed, result, 21), 0)
        self.record('gomp_support96', compact=compact, streamed=streamed, result=result, reference=reference,
                    matrix=matrix, policy=policy.__dict__,
                    extra=dict(actual_refinement=result['inner'] > result['outer']))


if __name__ == '__main__':
    unittest.main()
