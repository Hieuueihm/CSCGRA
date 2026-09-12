"""Two live endpoint credits, mode handoff and pending host ownership."""
import json
from pathlib import Path
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl
from verification.v4 import test_live_operator_rtl as live
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
class OperatorQueueTests(unittest.TestCase):
    case=live.LiveOperatorMemoryRtlTests.case
    @classmethod
    def setUpClass(cls):
        cls.path=Path(tempfile.mkdtemp(prefix='operator_queue_',dir=ROOT/'work'))
        cls.binary=cls.path/'queue.xsim.json'
        files=['rtl/v4/operator/phi_sign_generator.sv','rtl/v4/memory/phi_sign_cache.sv','rtl/v4/dataflow/phi_reader.sv','rtl/v4/dataflow/support_builder.sv','rtl/v4/dataflow/operand_plan.sv','rtl/v4/memory/live_operator_memory.sv','rtl/v4/memory/paired_support_store.sv','rtl/v4/dataflow/operator_frame_feeder.sv','rtl/v4/memory/stream_vector_store.sv','verification/v4/memory/tb_operator_queue.sv']
        cls.compiled=compile_rtl(cls.binary,'tb_operator_queue',files,root=ROOT,timeout=240)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    def test_two_credits_modes_host_pending_cancel_and_reload(self):
        start=len(live.RUNS)
        self.case(rows=33,cols=67,count=17,feed=2)
        RUNS.extend(live.RUNS[start:])
        self.assertIn('PASS clocks=',RUNS[-1]['stdout'])
        (self.path/'evidence.json').write_text(json.dumps(RUNS,indent=2))
if __name__=='__main__':unittest.main()
