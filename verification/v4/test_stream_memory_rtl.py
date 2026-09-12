"""Paired full-N stream memory: Vivado integer payload/protocol replay."""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl, run_rtl
ROOT = Path(__file__).resolve().parents[2]
RUNS = []
class StreamMemoryRtlTests(unittest.TestCase):
    def test_full_pool_credits_masks_and_flush(self):
        path = Path(tempfile.mkdtemp(prefix='stream_memory_', dir=ROOT/'work'))
        binary = path/'memory.xsim.json'
        sources = ['rtl/v4/memory/stream_vector_store.sv',
                   'verification/v4/memory/tb_stream_vector_store.sv']
        before = {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}
        compiled = compile_rtl(binary, 'tb_stream_vector_store', sources, root=ROOT)
        self.assertEqual(compiled.returncode, 0, compiled.stdout+compiled.stderr)
        result = run_rtl(binary, [], root=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        match = re.search(r'PASS stream_vector_store cycles=(\d+) checks=(\d+) reads=(\d+) writes=(\d+) stalls=(\d+) flushed=(\d+)', result.stdout)
        self.assertIsNotNone(match, result.stdout)
        cycles, checks, reads, writes, stalls, flushed = map(int, match.groups())
        self.assertGreater(reads, 512); self.assertGreater(writes, 512)
        self.assertGreater(stalls, 0); self.assertGreaterEqual(flushed, 3)
        self.assertEqual(before, {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources})
        record = dict(test=self.id(), status='PASS', cycles=cycles, comparisons=checks,
                      comparison_kind='exact_27bit_memory_and_credit_protocol', reads=reads,
                      writes=writes, stalls=stalls, flushed=flushed, source_sha256=before,
                      commands=compiled.commands+result.commands, stdout=result.stdout)
        RUNS.append(record)
        (path/'evidence.json').write_text(json.dumps(record, indent=2)+'\n')
if __name__ == '__main__': unittest.main()
