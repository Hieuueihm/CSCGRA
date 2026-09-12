"""Opt-in outer update lowering on the existing rounded affine datapath."""
import unittest
import numpy as np
from compiler.v4.greedy_qr_emit import ALGORITHMS, compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode
from models.v4.recovery import Policy
from scripts.v4.export_recovery import compile_spec
from scripts.v4 import benchmark_k8
from verification.v4.recovery_program_vm import execute

class OuterFusionTests(unittest.TestCase):
    def test_htp_rounding_outputs_match_separate_updates(self):
        for rows, columns in ((16,32), (33,35)):
            matrix = np.random.default_rng(991).choice([-1.,1.],(rows,columns))*.125
            measurement = matrix[:,2]*.25-matrix[:,9]*.125
            policy = Policy(2,max_iterations=3,residual_atol=0)
            for profile in ('reference','view'):
                packages = [compile_greedy_qr('HTP',matrix,policy,qr_profile=profile,outer_fusion=enabled)
                            for enabled in (False,True)]
                results = [execute(package,matrix,measurement,limit=1000000) for package in packages]
                for key in ('x','residual','support'):
                    self.assertEqual(list(results[0][key]),list(results[1][key]),key)
                for key in ('status','outer','inner'):
                    self.assertEqual(results[0][key],results[1][key],key)
                self.assertEqual(len(packages[0]['program'])-len(packages[1]['program']),1)
                self.assertTrue(packages[1]['outer_fusion_emitted'])
                self.assertIn('ROUNDED_AFFINE',packages[1]['required_kernel_features'])

    def test_other_qr_algorithms_keep_payloads(self):
        matrix = np.full((32,64),1/1024)
        for algorithm in ALGORITHMS:
            if algorithm == 'HTP':
                continue
            before = compile_greedy_qr(algorithm,matrix,Policy(8,max_iterations=8),qr_profile='view')
            after = compile_greedy_qr(algorithm,matrix,Policy(8,max_iterations=8),qr_profile='view',outer_fusion=True)
            for key in ('program','templates','vectors','constants','required_kernel_revision'):
                self.assertEqual(before[key],after[key],(algorithm,key))
            self.assertFalse(after['outer_fusion_emitted'])

    def test_fusion_requires_revision8_but_preserves_newer_requirements(self):
        spec = dict(algorithm='HTP',operator=dict(kind='lfsr32',seed=0x12345678,
                    rows=16,columns=32,scale_raw=8192),policy=dict(sparsity=2,max_iterations=3))
        with self.assertRaisesRegex(ValueError,'newer kernel revision'):
            compile_spec(spec,outer_fusion=True,target_kernel_revision=7)
        fused = compile_spec(spec,outer_fusion=True,target_kernel_revision=8)
        self.assertEqual(fused['required_kernel_revision'],8)
        opcodes = [decode(word)['kernel'] for word in fused['program'] if decode(word)['kind']==ABI['kinds']['KERNEL']]
        self.assertEqual(opcodes.count(23),1)
        latest = compile_spec(spec,outer_fusion=True,qr_profile='view',factor_range_template=True,
                              factor_energy_tap=True,target_kernel_revision=10)
        self.assertEqual(latest['required_kernel_revision'],10)
        with self.assertRaises(ValueError): compile_spec(spec,outer_fusion=1)
        spec['algorithm'] = 'GP'
        with self.assertRaisesRegex(ValueError,'QR outer'):
            compile_spec(spec,outer_fusion=True,target_kernel_revision=10)

    def test_flag_defaults_and_frozen_dependencies(self):
        parser = benchmark_k8.argument_parser()
        self.assertFalse(parser.parse_args([]).outer_fusion)
        self.assertTrue(parser.parse_args(['--outer-fusion']).outer_fusion)
        self.assertFalse(parser.parse_args(['--outer-fusion','--no-outer-fusion']).outer_fusion)
        matrix = np.full((16,32),.125)
        with self.assertRaisesRegex(ValueError,'boolean'):
            compile_greedy_qr('HTP',matrix,Policy(2),outer_fusion=1)

if __name__ == '__main__':
    unittest.main()
