"""Bounded Vivado xsim gate for stream_fabric cascade16."""
import hashlib,json,tempfile,unittest
from pathlib import Path
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
class FactorPanelFabric(unittest.TestCase):
 def test_cascade16_round_sub_stall(self):
  run=Path(tempfile.mkdtemp(prefix='factor_panel_fabric_',dir=ROOT/'work')); binary=run/'sim.json'
  files=['rtl/v4/compute/stream_pe.sv','rtl/v4/compute/stream_array.sv','rtl/v4/compute/stream_fabric.sv','verification/v4/compute/tb_factor_panel_fabric.sv']
  c=compile_rtl(binary,'tb_factor_panel_fabric',files,root=ROOT,timeout=90);self.assertEqual(c.returncode,0,c.stdout+c.stderr)
  r=run_rtl(binary,[],root=ROOT,timeout=90);self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('PASS factor_panel_fabric',r.stdout)
  (run/'evidence.json').write_text(json.dumps({'status':'PASS','stdout':r.stdout,
      'required_cases':['18 LFSR paired-mask/tail frames with independent signed oracle, zero masks, signed half ties and output stalls',
                        'malformed paired mask after queued valid work, held DONE and recovery',
                        'MUL range fault precedence over simultaneous downstream fault metadata',
                        'reset while held second-array output is valid'],
      'source_sha256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files},'commands':c.commands+r.commands},indent=2)+'\n')
if __name__=='__main__':unittest.main()
