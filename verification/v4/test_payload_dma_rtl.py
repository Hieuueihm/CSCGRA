"""Source-bound XSim regression for the ID-less AXI payload DMA."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl, run_rtl
ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['rtl/v4/host/payload_dma_engine.sv','verification/v4/host/tb_payload_dma_engine.sv']
class PayloadDmaRtlTests(unittest.TestCase):
    def test_bursts_tails_stalls_faults_cancel_and_recovery(self):
        folder=Path(tempfile.mkdtemp(prefix='payload_dma_',dir=ROOT/'work'))
        tracked=SOURCES+['verification/v4/test_payload_dma_rtl.py','scripts/v4/xsim.py']
        before={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in tracked}
        binary=folder/'dma.xsim.json'
        compiled=compile_rtl(binary,'tb_payload_dma_engine',SOURCES,root=ROOT,timeout=240)
        self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
        result=run_rtl(binary,[],root=ROOT,timeout=180)
        (folder/'result.json').write_text(json.dumps(dict(status='PASS' if result.returncode==0 and 'PASS payload_dma' in result.stdout else 'FAIL',
            source_sha256=before,commands=compiled.commands+result.commands,stdout=result.stdout,stderr=result.stderr),indent=2))
        print(folder,flush=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS payload_dma',result.stdout)
        self.assertEqual(before,{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in tracked})
if __name__=='__main__':
    unittest.main()
