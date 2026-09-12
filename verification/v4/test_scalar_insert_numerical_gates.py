"""Executed feature6 numerical gates with per-test source-bound evidence.

These remain Python integer-program checks. They do not claim RTL coverage.
"""
import hashlib
import json
from pathlib import Path
import unittest

import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'work' / 'scalar_insert_numerical_gates_20260910'
SOURCES = (
    'compiler/v4/greedy_qr_emit.py', 'compiler/v4/qr_program.py',
    'compiler/v4/recovery_program.py', 'compiler/v4/recovery_emit.py',
    'verification/v4/recovery_program_vm.py', 'verification/v4/recovery_program_vm_reference.py',
    'models/v4/fixed.py', 'models/v4/lfsr_operator.py', 'models/v4/recovery.py',
    'config/v4_kernel_interface.json', 'rtl/v4/include/kernel_interface.vh',
    'docs/v4/architecture/SCALAR_INSERT.md',
    'verification/v4/test_scalar_insert_numerical_gates.py',
)


def source_hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}


def kernel_pcs(package, op):
    return [pc for pc, word in enumerate(package['program'])
            if decode(word)['kind'] == ABI['kinds']['KERNEL'] and decode(word)['kernel'] == op]


def trace_count(package, result, op):
    pcs = set(kernel_pcs(package, op))
    return sum(pc in pcs for pc in result['trace'])


def digest(values):
    return hashlib.sha256(','.join(str(int(value)) for value in values).encode()).hexdigest()


class ScalarInsertNumericalGateTests(unittest.TestCase):
    def _assert_exact(self, baseline, observed):
        self.assertEqual(list(observed['x']), list(baseline['x']))
        self.assertEqual(list(observed['residual']), list(baseline['residual']))
        self.assertEqual((observed['support'], observed['status'], observed['outer'], observed['inner']),
                         (baseline['support'], baseline['status'], baseline['outer'], baseline['inner']))

    def _record(self, name, *, policy, matrix, resident, compact, result, reference, extra):
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        payload = dict(
            test=self.id(), status='PASS', scope='executed compact-versus-resident and unaccelerated-reference integer VM gate; not RTL evidence',
            algorithm=compact['algorithm'], rows=int(matrix.shape[0]), columns=int(matrix.shape[1]), policy=policy,
            package=dict(resident_program_words=len(resident['program']), compact_program_words=len(compact['program']),
                         resident_templates=len(resident['templates']), compact_templates=len(compact['templates']),
                         required_kernel_revision=compact['required_kernel_revision']),
            compact_trace_ops={str(op): trace_count(compact, result, op) for op in (19, 20, 21)},
            result=dict(status=result['status'], outer=result['outer'], inner=result['inner'], support=list(result['support']),
                        raw_x_sha256=digest(result['x']), raw_r_sha256=digest(result['residual'])),
            reference=dict(status=reference['status'], outer=reference['outer'], inner=reference['inner'],
                           raw_x_sha256=digest(reference['x']), raw_r_sha256=digest(reference['residual'])),
            source_sha256=source_hashes(), **extra)
        (EVIDENCE / f'{name}.json').write_text(json.dumps(payload, indent=2) + '\n')

    def test_omp_correction_executes_scalar_insert_after_extend(self):
        matrix = lfsr32_matrix(0x12345678, 16, 32, scale=8192) / 65536.0
        measurement = np.random.default_rng(1).integers(-4096, 4097, 16) / 16384.0
        policy = Policy(4, max_iterations=3, residual_atol=0, ls_normal_rtol=1e-6)
        resident = compile_greedy_qr('OMP', matrix, policy, qr_profile='resident')
        compact = compile_greedy_qr('OMP', matrix, policy, qr_profile='compact')
        baseline = execute(resident, matrix, measurement, limit=3_000_000)
        result = execute(compact, matrix, measurement, limit=3_000_000)
        reference = reference_execute(compact, matrix, measurement, limit=3_000_000)
        self._assert_exact(baseline, result)
        self._assert_exact(baseline, reference)
        extensions = [i for i, pc in enumerate(result['trace']) if pc in set(kernel_pcs(compact, 19))]
        corrections = [i for i, pc in enumerate(result['trace']) if pc == compact['labels']['qr_solve']]
        inserts = [i for i, pc in enumerate(result['trace']) if pc in set(kernel_pcs(compact, 21))]
        self.assertGreaterEqual(len(extensions), 2)
        self.assertGreater(result['inner'], 1)
        self.assertTrue(any(point > extensions[0] for point in corrections))
        self.assertTrue(any(point > corrections[1] for point in inserts), 'correction solve did not execute op21')
        self._record('omp_correction', policy=policy.__dict__, matrix=matrix, resident=resident, compact=compact,
                     result=result, reference=reference,
                     extra=dict(actual_refinement=True, first_extend_trace_index=extensions[0],
                                correction_trace_indices=corrections, scalar_insert_trace_indices=inserts))

    def test_gomp_support96_executes_extend_project_and_scalar_insert(self):
        matrix = lfsr32_matrix(0x12345678, 128, 128, scale=4096) / 65536.0
        measurement = np.random.default_rng(911).integers(-8192, 8193, 128) / 16384.0
        policy = Policy(2, max_iterations=2, group_size=48, residual_atol=0)
        resident = compile_greedy_qr('GOMP', matrix, policy, qr_profile='resident')
        compact = compile_greedy_qr('GOMP', matrix, policy, qr_profile='compact')
        baseline = execute(resident, matrix, measurement, limit=5_000_000)
        result = execute(compact, matrix, measurement, limit=5_000_000)
        reference = reference_execute(compact, matrix, measurement, limit=5_000_000)
        self._assert_exact(baseline, result)
        self._assert_exact(baseline, reference)
        self.assertEqual(len(result['support']), 96)
        self.assertGreater(trace_count(compact, result, 19), 0)
        self.assertGreater(trace_count(compact, result, 20), 0)
        self.assertGreater(trace_count(compact, result, 21), 0)
        self._record('gomp_support96', policy=policy.__dict__, matrix=matrix, resident=resident, compact=compact,
                     result=result, reference=reference,
                     extra=dict(actual_refinement=result['inner'] > result['outer'],
                                refinement_counter=result['inner']))


if __name__ == '__main__':
    unittest.main()
