import unittest
from pathlib import Path

from verification.v4.test_recovery_algorithms_rtl import rtl_args


class InstructionLimitArgsTests(unittest.TestCase):
    def test_none_keeps_testbench_default(self):
        args = rtl_args(Path('fixture.txt'), Path('trace.txt'), 8192, 8000000, None)
        self.assertFalse(any('instruction_limit' in value for value in args))

    def test_explicit_values_are_passed_faithfully(self):
        for limit in (1, 10000, 10001):
            with self.subTest(limit=limit):
                args = rtl_args(Path('fixture.txt'), Path('trace.txt'), 8192, 8000000, limit)
                self.assertIn(f'+instruction_limit={limit}', args)

    def test_invalid_values_fail_before_simulation(self):
        for limit in (0, -1, True, 1.5, '10000', 2**32):
            with self.subTest(limit=repr(limit)):
                with self.assertRaises(ValueError):
                    rtl_args(Path('fixture.txt'), Path('trace.txt'), 8192, 8000000, limit)


if __name__ == '__main__':
    unittest.main()
