"""Public export profile selection and target compatibility, without RTL changes."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from scripts.v4.export_recovery import compile_spec, export_spec


class ExportRecoveryTests(unittest.TestCase):
    def spec(self, algorithm='OMP'):
        return dict(algorithm=algorithm, operator=dict(kind='lfsr32', seed=0x12345678,
                    rows=16, columns=32, scale_raw=8192), policy=dict(sparsity=2, max_iterations=3))

    def test_balanced_default_and_reference_compatibility(self):
        balanced = compile_spec(self.spec())
        self.assertEqual(balanced['qr_execution_profile'], 'balanced')
        self.assertEqual(balanced['required_kernel_revision'], 2)
        reference = compile_spec(self.spec(), qr_profile='reference', target_kernel_revision=1)
        self.assertEqual(reference['required_kernel_revision'], 1)
        with self.assertRaisesRegex(ValueError, 'requires a newer kernel revision'):
            compile_spec(self.spec(), target_kernel_revision=1)

    def test_panel_profile_requires_revision3_only_when_policy_can_use_it(self):
        cosamp = self.spec('CoSaMP')
        cosamp['operator'].update(rows=32, columns=64)
        cosamp['policy'] = dict(sparsity=8, max_iterations=3, residual_atol=0)
        panel = compile_spec(cosamp, qr_profile='panel', target_kernel_revision=3)
        self.assertEqual((panel['required_kernel_revision'], panel['qr_panel_min_columns']), (3, 8))
        with self.assertRaisesRegex(ValueError, 'requires a newer kernel revision'):
            compile_spec(cosamp, qr_profile='panel', target_kernel_revision=2)
        narrow = compile_spec(self.spec('HTP'), qr_profile='panel', target_kernel_revision=2)
        self.assertEqual(narrow['required_kernel_revision'], 2)
        resident = compile_spec(cosamp, qr_profile='resident', target_kernel_revision=5)
        self.assertEqual((resident['revision'], resident['required_kernel_revision'], resident['qr_execution_profile']),
                         (2, 5, 'resident'))
        self.assertIn('FACTOR_PROJECT_UPDATE', resident['required_kernel_features'])
        with self.assertRaisesRegex(ValueError, 'newer kernel revision'):
            compile_spec(cosamp, qr_profile='resident', target_kernel_revision=4)
        compact = compile_spec(cosamp, qr_profile='compact', target_kernel_revision=6)
        self.assertEqual((compact['revision'], compact['required_kernel_revision'], compact['qr_execution_profile']),
                         (2, 6, 'compact'))
        self.assertIn('SCALAR_INSERT', compact['required_kernel_features'])
        self.assertTrue(compact['qr_scalar_insert_enabled'])
        with self.assertRaisesRegex(ValueError, 'newer kernel revision'):
            compile_spec(cosamp, qr_profile='compact', target_kernel_revision=5)
        streamed = compile_spec(cosamp, qr_profile='streamed', target_kernel_revision=6)
        self.assertEqual((streamed['revision'], streamed['required_kernel_revision'], streamed['qr_execution_profile']),
                         (2, 6, 'streamed'))
        self.assertTrue(streamed['qr_scalar_insert_enabled'])
        self.assertTrue(streamed['qr_stream_scalar_insert_enabled'])
        with self.assertRaisesRegex(ValueError, 'newer kernel revision'):
            compile_spec(cosamp, qr_profile='streamed', target_kernel_revision=5)
        view = compile_spec(cosamp, qr_profile='view', target_kernel_revision=7)
        self.assertEqual((view['revision'], view['required_kernel_revision'], view['qr_execution_profile']),
                         (2, 7, 'view'))
        self.assertTrue(view['qr_range_template_enabled'])
        self.assertIn('RANGE_TEMPLATE', view['required_kernel_features'])
        with self.assertRaisesRegex(ValueError, 'newer kernel revision'):
            compile_spec(cosamp, qr_profile='view', target_kernel_revision=6)

    def test_export_uses_canonical_loader_and_input_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'input.json'
            source.write_text(json.dumps(self.spec('HTP')))
            result = export_spec(source, root / 'program')
            self.assertEqual(result['qr_result_cache_entries'], 1)
            self.assertEqual(result['input_spec_sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(result['load_sha256'], hashlib.sha256((root / 'program/load.txt').read_bytes()).hexdigest())
            self.assertTrue((root / 'program/program.hex').exists())

    def test_non_qr_sparse_policy_and_invalid_operator(self):
        self.assertTrue(compile_spec(self.spec('GP'), sparse_forward=True)['sparse_forward'])
        chained = compile_spec(self.spec('GP'), operand_chains=True, target_kernel_revision=8)
        self.assertTrue(chained['operand_chains'])
        self.assertTrue(chained['operand_chains_emitted'])
        self.assertEqual(chained['required_kernel_revision'], 8)
        with self.assertRaisesRegex(ValueError, 'newer kernel revision'):
            compile_spec(self.spec('GP'), operand_chains=True, target_kernel_revision=7)
        # QR has no affine site.  The suite flag is recorded but does not add
        # op23/template words or artificially raise the profile requirement.
        qr = compile_spec(self.spec('OMP'), operand_chains=True, target_kernel_revision=2)
        self.assertTrue(qr['operand_chains'])
        self.assertFalse(qr['operand_chains_emitted'])
        self.assertEqual(qr['required_kernel_revision'], 2)
        bad = self.spec()
        bad['matrix'] = [[.25]]
        with self.assertRaisesRegex(ValueError, 'live LFSR'):
            compile_spec(bad)
        bad = self.spec()
        bad['operator']['seed'] = 0
        with self.assertRaises(ValueError):
            compile_spec(bad)


if __name__ == '__main__':
    unittest.main()
