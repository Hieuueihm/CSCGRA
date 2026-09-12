"""Vivado XSim unit gate for the command-local RANGE_TEMPLATE provider reader."""
import hashlib,json,tempfile,unittest
from pathlib import Path
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['rtl/v4/dataflow/range_reader.sv','verification/v4/dataflow/tb_range_reader.sv']
def sha(path): return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
class RangeReaderRtlTests(unittest.TestCase):
 def test_unaligned_provider_assembly_cache_bounds_tags_and_cancel(self):
  work=Path(tempfile.mkdtemp(prefix='range_reader_',dir=ROOT/'work')); binary=work/'range_reader.xsim.json'; before={p:sha(p) for p in SOURCES}
  compiled=compile_rtl(binary,'tb_range_reader',SOURCES,root=ROOT,timeout=180); self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
  ran=run_rtl(binary,[],root=ROOT,timeout=120); self.assertEqual(ran.returncode,0,ran.stdout+ran.stderr); self.assertIn('PASS requests=',ran.stdout)
  self.assertEqual(before,{p:sha(p) for p in SOURCES}); (work/'evidence.json').write_text(json.dumps({'status':'PASS','sources':before,'compile':compiled.__dict__,'run':ran.__dict__},indent=2,default=str))
if __name__=='__main__': unittest.main()