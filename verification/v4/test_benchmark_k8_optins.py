"""Fast guards for benchmark_k8's opt-in oracle and elaboration controls."""
from contextlib import contextmanager
from pathlib import Path
import unittest

from scripts.v4 import benchmark_k8 as benchmark


class BenchmarkK8OptinTests(unittest.TestCase):
    def setUp(self):
        self.accelerated = benchmark.ACCELERATED_ORACLE
        self.greedy = benchmark.ORIGINAL_GREEDY
        self.context = benchmark.model_acceleration

    def tearDown(self):
        benchmark.ACCELERATED_ORACLE = self.accelerated
        benchmark.ORIGINAL_GREEDY = self.greedy
        benchmark.model_acceleration = self.context

    def test_default_oracle_mode_keeps_reference_backends(self):
        mode = benchmark.oracle_mode(False)
        self.assertFalse(mode['enabled'])
        self.assertEqual(mode['vm_gemv'], 'default_arithmetic_matvec')
        self.assertEqual(mode['fixed_model'], 'default_model_methods')
        self.assertEqual(mode['floating_model'], 'default_model_methods')

    def test_active_default_excludes_admm_but_explicit_reference_is_accepted(self):
        self.assertNotIn('ADMM', benchmark.ACTIVE_ALGORITHMS)
        self.assertIn('ADMM', benchmark.ALL_ALGORITHMS)
        parser = benchmark.argument_parser()
        self.assertEqual(parser.parse_args(['--freeze']).algorithms,
                         ','.join(benchmark.ACTIVE_ALGORITHMS))
        self.assertEqual(parser.parse_args(['--freeze', '--algorithms', ','.join(benchmark.ALL_ALGORITHMS)]).algorithms,
                         ','.join(benchmark.ALL_ALGORITHMS))
        cfg = dict(rows=64, columns=256, outer=8, gomp_extra=0,
                   algorithms=list(benchmark.ACTIVE_ALGORITHMS))
        self.assertEqual([algorithm for algorithm, _ in benchmark.requested_cases(cfg)],
                         list(benchmark.ACTIVE_ALGORITHMS))
        cfg['algorithms'] = list(benchmark.ALL_ALGORITHMS)
        self.assertEqual(benchmark.requested_cases(cfg)[-1], ('ADMM', 8))

    def test_operand_chain_flag_is_explicit_and_default_false(self):
        parser = benchmark.argument_parser()
        self.assertFalse(parser.parse_args(['--freeze']).operand_chains)
        self.assertTrue(parser.parse_args(['--freeze', '--operand-chains']).operand_chains)
        self.assertFalse(parser.parse_args(['--freeze', '--operand-chains', '--no-operand-chains']).operand_chains)

    def test_acceleration_context_wraps_only_fixed_model_dispatch(self):
        events = []
        @contextmanager
        def context():
            events.append('enter')
            try:
                yield
            finally:
                events.append('exit')
        def call(*args, **kwargs):
            events.append('call')
            return object()
        benchmark.model_acceleration = context
        benchmark.ORIGINAL_GREEDY = call
        benchmark.ACCELERATED_ORACLE = True
        fixed = benchmark.greedy_dispatch('OMP', None, None, None, profile=object())
        floating = benchmark.greedy_dispatch('OMP', None, None, None, profile=None)
        self.assertIsNot(fixed, floating)
        self.assertEqual(events, ['enter', 'call', 'exit', 'call'])
        self.assertIs(benchmark.OBSERVED['fixed'], fixed)
        self.assertIs(benchmark.OBSERVED['floating'], floating)

    def test_source_closure_captures_optin_helpers(self):
        paths = {path.relative_to(benchmark.ROOT).as_posix() for path in benchmark.sources()}
        self.assertIn('verification/v4/exact_model_context.py', paths)
        self.assertIn('verification/v4/exact_vm_gemv.py', paths)
        self.assertIn('scripts/v4/k8_exact_integer_acceleration.py', paths)
        self.assertIn('scripts/v4/benchmark_k8.py', paths)
        self.assertIn('config/v4_gemv_mapping_calibration.json', paths)
        self.assertIn('rtl/v4/include/tile_interface.vh', paths)


if __name__ == '__main__':
    unittest.main()
