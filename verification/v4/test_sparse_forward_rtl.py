"""Actual live-builder sparse-forward comparison against the full-Phi baseline."""
import unittest
import json
from verification.v4 import test_recovery_algorithms_rtl as shared

RUNS = []


class SparseForwardRtlTests(unittest.TestCase):
    run_records = RUNS
    setUpClass = classmethod(shared.RecoveryAlgorithmsRtlTests.setUpClass.__func__)
    @classmethod
    def tearDownClass(cls):
        (cls.path/'sparse_evidence.json').write_text(json.dumps(RUNS, indent=2))

    def case(self, *args, **kwargs):
        shared.RecoveryAlgorithmsRtlTests.case(self, *args, **kwargs)
        (self.path/'sparse_evidence.json').write_text(json.dumps(RUNS, indent=2))

    def paired(self, rows, columns, sparsity, iterations, scale):
        for algorithm in ('MP', 'GP', 'IHT'):
            for sparse in (False, True):
                self.case(algorithm, rows=rows, n=columns, iterations=iterations,
                          sparsity=sparsity, scale_override=scale, planted=True,
                          sparse_forward=sparse)
            baseline, variant = RUNS[-2:]
            for key in ('raw_phi_sha256', 'raw_y_sha256', 'output_raw_x_sha256',
                        'output_raw_r_sha256', 'accepted_support', 'status', 'outer_iterations'):
                self.assertEqual(baseline[key], variant[key], key)

    def test_matched_m32_n128_k2_outer2(self):
        self.paired(32, 128, 2, 2, 11585)

    def test_matched_m64_n256_k8_outer8(self):
        self.paired(64, 256, 8, 8, 8192)


if __name__ == '__main__':
    unittest.main()
