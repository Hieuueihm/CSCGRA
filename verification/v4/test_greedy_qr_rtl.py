"""Five complete greedy programs on live Phi, builder, factors and shared PEs."""
import json
import unittest
from verification.v4 import test_recovery_algorithms_rtl as shared

RUNS = []


class GreedyQrRtlTests(unittest.TestCase):
    run_records = RUNS
    setUpClass = classmethod(shared.RecoveryAlgorithmsRtlTests.setUpClass.__func__)

    @classmethod
    def tearDownClass(cls):
        (cls.path/'qr_evidence.json').write_text(json.dumps(RUNS, indent=2))

    def case(self, *args, **kwargs):
        shared.RecoveryAlgorithmsRtlTests.case(self, *args, **kwargs)
        (self.path/'qr_evidence.json').write_text(json.dumps(RUNS, indent=2))

    def test_five_nonzero_complete_programs(self):
        for algorithm in ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'):
            with self.subTest(algorithm=algorithm):
                self.case(algorithm, rows=16, n=32, truth=True)

    def test_zero_measurement_all_five(self):
        for algorithm in ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'):
            with self.subTest(algorithm=algorithm):
                self.case(algorithm, rows=16, n=32, zero=True)


if __name__ == '__main__':
    unittest.main()
