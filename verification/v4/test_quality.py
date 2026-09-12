import math
import unittest
import numpy as np
from models.v4.quality import compare, metrics, signed_dot_width


class QualityTests(unittest.TestCase):
    def test_relative_and_absolute_gates_separate(self):
        result = compare([1., 1.], [0., 0.], [0., 0.], absolute_snr_min_db=20)
        self.assertTrue(result['arithmetic_quality_pass'])
        self.assertFalse(result['application_quality_pass'])
        self.assertFalse(result['paper_quality_pass'])

    def test_same_support_does_not_excuse_quality_loss(self):
        result = compare([1., 1.], [.9, .9], [.8, .8], absolute_snr_min_db=0)
        self.assertAlmostEqual(result['nmse_ratio'], 4.)
        self.assertFalse(result['arithmetic_quality_pass'])

    def test_exact_reference_and_missing_floor(self):
        self.assertFalse(compare([1.], [1.], [.999])['arithmetic_quality_pass'])
        self.assertTrue(compare([1.], [1.], [1.])['arithmetic_quality_pass'])
        self.assertFalse(compare([1.], [1.], [1.])['paper_quality_pass'])

    def test_metrics_nonfinite_zero_and_range_bound(self):
        self.assertEqual(metrics([0.], [0.])['nmse'], 0)
        self.assertTrue(math.isinf(metrics([0.], [1.])['nmse']))
        with self.assertRaises(ValueError):
            metrics([1.], [np.nan])
        self.assertEqual(signed_dot_width(27,27,1024), 64)
        self.assertEqual(signed_dot_width(18,27,1024), 55)
        self.assertEqual(signed_dot_width(8,8,1), 16)

    def test_thresholds_and_width_inputs_are_explicitly_validated(self):
        for kwargs in ({'max_snr_loss_db': np.nan},
                       {'max_snr_loss_db': -0.1},
                       {'max_nmse_ratio': np.inf},
                       {'max_nmse_ratio': -1.0},
                       {'absolute_snr_min_db': np.nan}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                compare([1.], [1.], [1.], **kwargs)
        for args in ((8.5, 8, 4), (8, True, 4), (8, 8, 0)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                signed_dot_width(*args)
