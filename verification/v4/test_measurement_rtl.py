"""Measurement input protocol and exact D18-to-S27 boundary replay in Vivado."""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
class MeasurementRtlTests(unittest.TestCase):
    def test_boundaries_malformed_stalls_and_epoch_cleanup(self):
        path=Path(tempfile.mkdtemp(prefix='measurement_',dir=ROOT/'work'))
        binary=path/'measurement.xsim.json'
        sources=['rtl/v4/dataflow/measurement_loader.sv','verification/v4/measurement/tb_measurement.sv']
        compiled=compile_rtl(binary,'tb_measurement',sources,root=ROOT)
        self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
        result=run_rtl(binary,[],root=ROOT)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        match=re.search(r'PASS measurement cycles=(\d+) checks=(\d+) loads=(\d+) words=(\d+) stalls=(\d+)',result.stdout)
        self.assertIsNotNone(match,result.stdout)
        cycles,checks,loads,words,stalls=map(int,match.groups())
        self.assertGreaterEqual(loads,20);self.assertGreaterEqual(words,20);self.assertGreater(stalls,0)
        record=dict(test=self.id(),cycles=cycles,comparisons=checks,comparison_kind='exact_signed_embedding_and_protocol',
                    loads=loads,words=words,stalls=stalls,commands=compiled.commands+result.commands,stdout=result.stdout,
                    status='PASS',tests_run=1,failures=0,errors=0,skips=0,tools_failures=0,
                    source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources})
        RUNS.append(record);(path/'evidence.json').write_text(json.dumps(record,indent=2)+'\n')
if __name__=='__main__':unittest.main()
