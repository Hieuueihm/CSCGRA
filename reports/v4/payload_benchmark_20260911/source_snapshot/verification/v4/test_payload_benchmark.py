"""Fail-closed fixture and timing report parser checks; not RTL qualification."""
import unittest

from scripts.v4 import benchmark_payload as benchmark


class PayloadBenchmarkTests(unittest.TestCase):
    def case(self):
        return {"output_raw_x_sha256": benchmark.oracle.raw_digest([1, -1]),
                "output_raw_r_sha256": benchmark.oracle.raw_digest([0])}

    def trace(self):
        return ("PROFILE mode=0 setup=10 load=20 compute=30 writeback=40 total=100 "
                "native=29 iterations=8 dma_active=0 dma_stall=0\n"
                "X 0 0000001\nX 1 7ffffff\nV 0 0000000\nPASS payload_benchmark\n")

    def test_signed_outputs_and_disjoint_buckets(self):
        self.assertEqual(benchmark.parse_trace(self.trace(), self.case())["total"], 100)

    def test_incomplete_and_duplicate_profiles_rejected(self):
        for text in (self.trace().replace("PASS payload_benchmark", ""),
                     self.trace() + self.trace().splitlines()[0] + "\n"):
            with self.assertRaises(ValueError):
                benchmark.parse_trace(text, self.case())

    def test_early_stop_and_overlap_rejected(self):
        for text in (self.trace().replace("iterations=8", "iterations=7"),
                     self.trace().replace("total=100", "total=99")):
            with self.assertRaises(ValueError):
                benchmark.parse_trace(text, self.case())

    def test_changed_or_missing_result_rejected(self):
        for text in (self.trace().replace("7ffffff", "0000000"),
                     self.trace().replace("X 1 7ffffff\n", ""),
                     self.trace().replace("X 1", "X 2")):
            with self.assertRaises(ValueError):
                benchmark.parse_trace(text, self.case())

    def test_native_fixture_rejects_fault_and_trailing_data(self):
        job = "1 0 0 0 0 0\n0 0 0 0 0\n0\n0 0\n"
        text = "32 64 2\n" + job + job
        self.assertEqual(benchmark.parse_native_fixture(text)[:2], (32, 64))
        for bad in (text + "unexpected\n", text.replace("1 0 0 0 0 0", "1 0 0 0 2 0", 1)):
            with self.assertRaises(ValueError):
                benchmark.parse_native_fixture(bad)


if __name__ == "__main__":
    unittest.main()
