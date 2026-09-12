"""Integer compiler/VM guards for opt-in factor-prefix QR reuse."""
import copy
import unittest

import numpy as np

from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode, encode, pack, unpack
from scripts.v4.export_recovery import compile_spec
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute


def planted_fixture(rows=64, columns=256, scale=8192):
    raw = lfsr32_matrix(0x12345678, rows, columns, scale=scale).astype(int)
    matrix = raw / 65536.0
    rng = np.random.default_rng(1909 + rows + columns)
    support = sorted(map(int, rng.choice(columns, 8, replace=False)))
    planted = np.zeros(columns)
    planted[support] = rng.uniform(.5, 1.0, 8) * rng.choice([-1, 1], 8)
    analog = matrix @ planted
    gain = .5 / float(np.max(np.abs(analog)))
    return matrix, np.rint(analog * gain * 16384) / 16384


def kernel_trace(package, result, opcode):
    return sum(
        decode(package['program'][pc])['kind'] == 1 and
        decode(package['program'][pc])['kernel'] == opcode
        for pc in result['trace'])


class QrReuseCompilerVmTests(unittest.TestCase):
    @staticmethod
    def patched_first_union(package, **immediate_updates):
        """Use the real program with a deterministic test-only support schedule."""
        patched = copy.deepcopy(package)
        pc = next(
            pc for pc, word in enumerate(patched['program'])
            if decode(word)['kind'] == 1 and decode(word)['kernel'] == 9)
        fields = decode(patched['program'][pc])
        immediate = unpack(ABI['service_immediate_fields'], fields['immediate'])
        immediate.update(immediate_updates)
        fields['immediate'] = pack(ABI['service_immediate_fields'], immediate)
        name = next(name for name, value in ABI['kinds'].items() if value == fields['kind'])
        patched['program'][pc] = encode(
            name, **{field: fields[field] for field in ABI['allowed_fields'][name]})
        return patched

    @staticmethod
    def broken_tau_prefix_copy(package):
        """Restore the short COPY bug for a mask-validity regression only."""
        broken = copy.deepcopy(package)
        pc = broken['labels']['qr_reuse'] + 1
        fields = decode(broken['program'][pc])
        assert fields['kind'] == 1 and fields['kernel'] == 12
        vector = {entry['name']: index for index, entry in enumerate(broken['vectors'])}
        copy_template = next(
            index for index, entry in enumerate(broken['templates']) if entry['name'] == 'copy')
        immediate = {name: 0 for name in ABI['service_immediate_fields']}
        immediate.update(template=copy_template, length=24)
        fields.update(kernel=0, dst_v=vector['qr_T'], a_v=vector['RU_T'], b_v=0,
                      length_mode=3,
                      immediate=pack(ABI['service_immediate_fields'], immediate))
        name = next(name for name, value in ABI['kinds'].items() if value == fields['kind'])
        broken['program'][pc] = encode(
            name, **{field: fields[field] for field in ABI['allowed_fields'][name]})
        return broken

    def pair(self, algorithm, matrix, measurement, policy):
        panel = compile_greedy_qr(algorithm, matrix, policy, qr_profile='panel')
        reuse = compile_greedy_qr(algorithm, matrix, policy, qr_profile='reuse')
        before = execute(panel, matrix, measurement, limit=3_000_000)
        after = execute(reuse, matrix, measurement, limit=3_000_000)
        self.assertEqual(list(after['x']), list(before['x']))
        self.assertEqual(list(after['residual']), list(before['residual']))
        self.assertEqual((after['support'], after['status'], after['outer'], after['inner']),
                         (before['support'], before['status'], before['outer'], before['inner']))
        return panel, reuse, before, after

    def test_matched_m64_omp_gomp_outer8_exact_and_extend(self):
        matrix, measurement = planted_fixture()
        policy = Policy(8, max_iterations=8, residual_atol=0)
        for algorithm in ('OMP', 'GOMP'):
            with self.subTest(algorithm=algorithm):
                _, reuse, _, result = self.pair(algorithm, matrix, measurement, policy)
                self.assertTrue(reuse['qr_reuse_enabled'])
                self.assertEqual(reuse['required_kernel_revision'], 4)
                self.assertEqual(kernel_trace(reuse, result, 19), 7)
                self.assertGreater(kernel_trace(reuse, result, 13), 0)

    def test_reference_vm_and_job_reset_match_primary(self):
        matrix, measurement = planted_fixture(32, 64)
        package = compile_greedy_qr('GOMP', matrix, Policy(8, max_iterations=4, residual_atol=0),
                                    qr_profile='reuse')
        first = execute(package, matrix, measurement, limit=1_000_000)
        second = execute(package, matrix, measurement, limit=1_000_000)
        reference = reference_execute(package, matrix, measurement, limit=1_000_000)
        for actual in (second, reference):
            self.assertEqual(list(actual['x']), list(first['x']))
            self.assertEqual(list(actual['residual']), list(first['residual']))
            self.assertEqual((actual['support'], actual['status'], actual['outer'], actual['inner']),
                             (first['support'], first['status'], first['outer'], first['inner']))
        self.assertGreater(kernel_trace(package, first, 19), 0)

    def test_masked_publication_rejects_old_tau_short_copy(self):
        matrix, measurement = planted_fixture(32, 64)
        package = compile_greedy_qr(
            'OMP', matrix, Policy(8, max_iterations=3, residual_atol=0), qr_profile='reuse')
        broken = self.broken_tau_prefix_copy(package)
        for runner in (execute, reference_execute):
            with self.subTest(runner=runner.__module__):
                with self.assertRaisesRegex(AssertionError, 'uninitialized vector'):
                    runner(broken, matrix, measurement, limit=1_000_000)
                fixed = runner(package, matrix, measurement, limit=1_000_000)
                self.assertGreater(kernel_trace(package, fixed, 19), 0)

    def test_masked_word_clears_aliased_descriptor_lanes(self):
        matrix, measurement = planted_fixture(32, 64)
        package = compile_greedy_qr(
            'OMP', matrix, Policy(8, max_iterations=3, residual_atol=0), qr_profile='reuse')
        aliased = copy.deepcopy(package)
        vectors = {entry['name']: entry for entry in aliased['vectors']}
        # A cap-one producer shares the first physical word with Y.  Its one
        # result lane must clear the remaining 31 mask lanes before QR reads
        # Y; descriptor capacity must not shorten that physical clear.
        vectors['CH']['base'] = vectors['Y']['base']
        vectors['CH']['capacity'] = 1
        for runner in (execute, reference_execute):
            with self.subTest(runner=runner.__module__):
                with self.assertRaisesRegex(AssertionError, 'uninitialized vector'):
                    runner(aliased, matrix, measurement, limit=1_000_000)

    def test_short_topk_and_union_clear_requested_words(self):
        # GOMP requests 64 indices but N=1 yields one TOPK result; OMP's
        # UNION likewise publishes one member against its R16=64 request.
        # In each package its second requested physical word aliases Y.
        topk_matrix = lfsr32_matrix(0x12345678, 64, 1, scale=8192) / 65536.0
        topk = compile_greedy_qr(
            'GOMP', topk_matrix,
            Policy(1, max_iterations=1, group_size=64, residual_atol=0), qr_profile='reuse')
        union_matrix, union_measurement = planted_fixture(64, 64)
        union = compile_greedy_qr(
            'OMP', union_matrix, Policy(8, max_iterations=1, residual_atol=0),
            qr_profile='reuse')
        for name, package, matrix, measurement, vector_name in (
            ('topk', topk, topk_matrix, np.ones(64) / 16384.0, 'CH'),
            ('union', union, union_matrix, union_measurement, 'NS'),
        ):
            aliased = copy.deepcopy(package)
            vectors = {entry['name']: entry for entry in aliased['vectors']}
            vectors[vector_name]['base'] = vectors['Y']['base'] - 1
            if name == 'topk':
                # Test-only: let the deliberately short GOMP result reach
                # QR so the aliased second requested word is consumed.
                topk_pc = next(
                    pc for pc, word in enumerate(aliased['program'])
                    if decode(word)['kind'] == 1 and decode(word)['kernel'] == 5)
                fields = decode(aliased['program'][topk_pc + 1])
                self.assertEqual(fields['kind'], ABI['kinds']['BR_COMPARE'])
                fields['immediate'] = ABI['comparisons']['GE']
                aliased['program'][topk_pc + 1] = encode(
                    'BR_COMPARE', **{field: fields[field]
                                     for field in ABI['allowed_fields']['BR_COMPARE']})
            for runner in (execute, reference_execute):
                with self.subTest(name=name, runner=runner.__module__):
                    with self.assertRaisesRegex(AssertionError, 'uninitialized vector'):
                        runner(aliased, matrix, measurement, limit=1_000_000)

    def test_other_qr_algorithms_keep_panel_schedule_without_extend(self):
        matrix, _ = planted_fixture(32, 64)
        policy = Policy(8, max_iterations=8, residual_atol=0)
        for algorithm in ('CoSaMP', 'SP', 'HTP'):
            with self.subTest(algorithm=algorithm):
                panel = compile_greedy_qr(algorithm, matrix, policy, qr_profile='panel')
                reuse = compile_greedy_qr(algorithm, matrix, policy, qr_profile='reuse')
                for field in ('program', 'templates', 'vectors', 'constants'):
                    self.assertEqual(reuse[field], panel[field], field)
                self.assertFalse(reuse['qr_reuse_enabled'])
                self.assertNotIn(19, [decode(word)['kernel'] for word in reuse['program']
                                      if decode(word)['kind'] == 1])

    def test_extend_template_is_strict(self):
        matrix, measurement = planted_fixture(32, 64)
        package = compile_greedy_qr('OMP', matrix, Policy(8, max_iterations=3, residual_atol=0),
                                    qr_profile='reuse')
        extend_template = next(
            unpack(ABI['service_immediate_fields'], decode(word)['immediate'])['template']
            for word in package['program']
            if decode(word)['kind'] == 1 and decode(word)['kernel'] == 19)
        bad = copy.deepcopy(package)
        bad['templates'][extend_template]['contexts'][0] = 1
        with self.assertRaisesRegex(AssertionError, 'FACTOR_EXTEND'):
            execute(bad, matrix, measurement)

    def test_correction_after_extend_matches_panel(self):
        # This fixed integer fixture reaches two EXTENDs and then requires the
        # full correction solver after the first extension.  It proves that
        # RU_QTY is only an initial-solve shortcut, never correction state.
        matrix = lfsr32_matrix(0x12345678, 16, 32, scale=8192) / 65536.0
        measurement = np.random.default_rng(1).integers(-4096, 4097, 16) / 16384.0
        panel, reuse, before, after = self.pair(
            'OMP', matrix, measurement,
            Policy(4, max_iterations=3, residual_atol=0, ls_normal_rtol=1e-6))
        extension_points = [
            index for index, pc in enumerate(after['trace'])
            if decode(reuse['program'][pc])['kind'] == 1 and
            decode(reuse['program'][pc])['kernel'] == 19]
        correction_points = [
            index for index, pc in enumerate(after['trace'])
            if pc == reuse['labels']['qr_solve']]
        self.assertGreaterEqual(len(extension_points), 2)
        self.assertTrue(any(point > extension_points[0] for point in correction_points))
        self.assertGreater(after['inner'], 1)
        self.assertEqual((after['status'], after['inner']), (before['status'], before['inner']))

    def test_reordered_and_shrunk_supports_execute_fallback_init(self):
        matrix, measurement = planted_fixture(32, 64)
        package = compile_greedy_qr(
            'OMP', matrix, Policy(8, max_iterations=4, residual_atol=0), qr_profile='reuse')
        # Sorted UNION reorders the already-ranked prefix; zero old length
        # deliberately shrinks it.  Both must take BUILD_B+INIT, never EXTEND.
        for name, update in (
            ('reordered', {'flags': 0}),
            ('shrunk', {'support_length_s': 0}),
        ):
            with self.subTest(name=name):
                fallback = self.patched_first_union(package, **update)
                result = execute(fallback, matrix, measurement, limit=1_000_000)
                self.assertIn(fallback['labels']['qr_reuse_fallback'], result['trace'])
                self.assertEqual(kernel_trace(fallback, result, 19), 0)
                self.assertEqual(kernel_trace(fallback, result, 13), result['outer'])
                self.assertEqual(result['status'], 'max_iterations')

    def test_grouped_gomp_crosses_panel_boundaries_numerically(self):
        # Two grouped selections reach S=33 then S=66: this crosses both the
        # 32-lane panel boundary and the S=64 service range without a 48-step
        # maximum-support run.  The separate support96 test above remains the
        # capacity guard for the maximum legal compile geometry.
        matrix = lfsr32_matrix(0x12345678, 66, 96, scale=4096) / 65536.0
        measurement = np.random.default_rng(77).integers(-8192, 8193, 66) / 16384.0
        policy = Policy(2, max_iterations=2, group_size=33, residual_atol=0,
                        ls_normal_rtol=1e-4)
        panel, reuse, before, after = self.pair('GOMP', matrix, measurement, policy)
        self.assertEqual(reuse['restricted_support_bound'], 66)
        self.assertEqual(len(after['support']), 66)
        self.assertEqual(kernel_trace(reuse, after, 13), 1)
        self.assertEqual(kernel_trace(reuse, after, 19), 1)
        self.assertEqual((after['status'], after['outer'], after['inner']),
                         (before['status'], before['outer'], before['inner']))

    def test_grouped_gomp_reaches_support96_numerically(self):
        # The maximum live QR support is exercised in two grouped outer
        # iterations (48 then 96), rather than by a 48-iteration schedule.
        # This is a normal LFSR sign-Phi fixture and the ordinary certificate
        # policy; no tolerance is relaxed to make the suffix path pass.
        matrix = lfsr32_matrix(0x12345678, 128, 128, scale=4096) / 65536.0
        measurement = np.random.default_rng(911).integers(-8192, 8193, 128) / 16384.0
        policy = Policy(2, max_iterations=2, group_size=48, residual_atol=0)
        panel, reuse, before, after = self.pair('GOMP', matrix, measurement, policy)
        self.assertEqual(reuse['restricted_support_bound'], 96)
        self.assertEqual(len(after['support']), 96)
        self.assertEqual(kernel_trace(reuse, after, 13), 1)
        self.assertEqual(kernel_trace(reuse, after, 19), 1)
        self.assertEqual((after['status'], after['outer'], after['inner']),
                         (before['status'], before['outer'], before['inner']))

    def test_export_profile_requires_revision4_and_preserves_program_revision2(self):
        spec = dict(algorithm='OMP', policy=dict(sparsity=8, max_iterations=3),
                    operator=dict(kind='lfsr32', seed=0x12345678, rows=32,
                                  columns=64, scale_raw=8192))
        with self.assertRaisesRegex(ValueError, 'newer kernel revision'):
            compile_spec(spec, qr_profile='reuse', target_kernel_revision=3)
        package = compile_spec(spec, qr_profile='reuse', target_kernel_revision=4)
        self.assertEqual(package['revision'], 2)
        self.assertEqual(package['target_kernel_revision'], 4)
        self.assertEqual(package['qr_execution_profile'], 'reuse')
        self.assertIn('FACTOR_EXTEND', package['required_kernel_features'])
        self.assertIn('next owned B epoch', package['qr_reuse_b_epoch_scope'])
        matrix, measurement = planted_fixture(32, 64)
        with self.assertRaisesRegex(ValueError, 'qr_cache_entries=0'):
            compile_greedy_qr('OMP', matrix, Policy(8, max_iterations=3),
                              qr_profile='reuse', qr_cache_entries=1)
        self.assertEqual(
            compile_greedy_qr('OMP', matrix, Policy(8, max_iterations=3),
                              qr_profile='reuse')['qr_result_cache_entries'], 0)

    def test_reuse_without_scalar_template_matches_panel(self):
        matrix, measurement = planted_fixture(32, 64)
        policy = Policy(8, max_iterations=3, residual_atol=0)
        panel = compile_greedy_qr(
            'OMP', matrix, policy, qr_profile='panel', qr_scalar_template=False)
        reuse = compile_greedy_qr(
            'OMP', matrix, policy, qr_profile='reuse', qr_scalar_template=False)
        before = execute(panel, matrix, measurement, limit=1_000_000)
        after = execute(reuse, matrix, measurement, limit=1_000_000)
        self.assertEqual(list(after['x']), list(before['x']))
        self.assertEqual(list(after['residual']), list(before['residual']))
        self.assertEqual((after['support'], after['status'], after['outer'], after['inner']),
                         (before['support'], before['status'], before['outer'], before['inner']))
        self.assertGreater(kernel_trace(reuse, after, 19), 0)

    def test_maximum_gomp_support96_compiles_within_pool_limits(self):
        matrix, _ = planted_fixture(128, 1024, 4096)
        package = compile_greedy_qr('GOMP', matrix,
            Policy(48, max_iterations=48, group_size=2, residual_atol=0), qr_profile='reuse')
        self.assertEqual(package['restricted_support_bound'], 96)
        self.assertLessEqual(len(package['program']), 1024)
        self.assertLessEqual(len(package['vectors']), 32)
        self.assertLessEqual(max(v['base'] + (v['capacity'] + 31) // 32
                                 for v in package['vectors']), 480)


if __name__ == '__main__':
    unittest.main()
