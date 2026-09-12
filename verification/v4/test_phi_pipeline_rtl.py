"""Isolated elastic Phi leaves: synchronous data, ordered faults and two credits."""
from pathlib import Path
import hashlib,json,re,tempfile,unittest
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['rtl/v4/dataflow/phi_reader.sv','rtl/v4/memory/phi_sign_cache.sv','verification/v4/phi/tb_phi_pipeline.sv']
RUNS=[]
class PhiPipelineTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.folder=Path(tempfile.mkdtemp(prefix='phi_pipeline_',dir=ROOT/'work'));cls.binary=cls.folder/'phi.xsim.json'
  cls.paths=SOURCES+['verification/v4/test_phi_pipeline_rtl.py','scripts/v4/xsim.py','config/v4_phi_interface.json','models/v4/phi_stream.py','scripts/v4/generate_phi_interface.py']+[p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl/v4/include').glob('*.vh')]
  cls.before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in cls.paths}
  cls.compiled=compile_rtl(cls.binary,'tb_phi_pipeline',SOURCES,root=ROOT,timeout=240)
  if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
 def replay(self,m=33,n=9,mode=0,stall=0,abort=0,faults=False):
  folder=self.folder/f'{self._testMethodName}_{m}_{n}_{mode}_{stall}_{abort}';folder.mkdir()
  blocks=(m+31)//32
  words=[sum(((r*17+c*13+r*c)%7<3)<<lane for lane in range(32) if (r:=block*32+lane)<m) for c in range(n) for block in range(blocks)]
  image=words+[0]*(4096-len(words));(folder/'image.hex').write_text(''.join(f'{w:08x}\n' for w in image))
  requests=[]
  for i in range(128):
   mask=0;addresses=0;value=0;valid=0
   for bank in range(8):
    available=list(range(bank,n,8))
    if not available:continue
    col=available[(i+bank)%len(available)];block=(i+bank)%blocks;addr=col//8*blocks+block
    if i%3==0 and bank%2:continue
    mask|=1<<bank;addresses|=addr<<(bank*9);value|=words[col*blocks+block]<<(32*bank);valid|=((1<<min(32,m-block*32))-1)<<(32*bank)
   key=0x1234;gen=3;job=7;fmt=1;tag=(65528+i)&65535;inject=0;fault=0
   if faults and i in (10,21,32,43,54,65,76,87,98,109):
    which=(i-10)//11
    if mode:
     if which%3==0:gen=4
     elif which%3==1:mask=0
     else:mask=128;addresses=511<<(7*9)
     fault=3
    else:
     if which==0:key=0;mask|=1<<8;fault=3
     elif which==1:mask|=1<<8;fault=4
     elif which==2:addresses|=1<<72;fault=4
     elif which==3:gen=4;fault=3
     elif which==4:job=8;fault=3
     elif which==5:fmt=2;fault=3
     else:inject=which-5;fault=8 if inject in (1,3) else 7
    value=valid=0
   requests.append(f'{mask:x} {addresses:x} {key:x} {gen:x} {job:x} {tag:x} {fmt:x} {inject:x} {fault:x} {value:x} {valid:x}')
  (folder/'requests.txt').write_text('\n'.join(requests)+'\n')
  args=[f'image={(folder/"image.hex").as_posix()}',f'requests={(folder/"requests.txt").as_posix()}',f'm={m}',f'n={n}',f'mode={mode}',f'stall={stall}',f'abort={abort}']
  result=run_rtl(self.binary,args,root=ROOT,timeout=240)
  self.assertEqual(result.returncode,0,result.stdout+result.stderr)
  match=re.search(r'PASS phi_pipeline commands=(\d+) cycles=(\d+) grants=(\d+) refills=(\d+) max_run=(\d+) peak=(\d+) aborts=(\d+) accepted=(\d+) flushed=(\d+) joined_stall=(\d+)',result.stdout);self.assertIsNotNone(match,result.stdout)
  commands,cycles,grants,refills,max_run,peak,aborts,accepted,flushed,joined_stall=map(int,match.groups());self.assertEqual(commands,128);self.assertEqual(accepted,commands+flushed)
  if not mode and stall:self.assertGreater(joined_stall,0)
  self.assertEqual(self.before,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in self.paths})
  RUNS.append(dict(test=self.id(),status='PASS',shape=[m,n],mode=mode,stall=stall,abort=abort,cycles=cycles,comparisons=commands*7,accepted=accepted,retired=commands,flushed=flushed,matrix_grants=grants,simultaneous_refills=refills,max_consecutive_requests=max_run,peak=peak,aborts=aborts,older_response_during_request_stall=joined_stall,commands=self.compiled.commands+result.commands,stdout=result.stdout,compile_stdout=self.compiled.stdout,compile_stderr=self.compiled.stderr,source_sha256=self.before,input_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir()}))
  (self.folder/'evidence.json').write_bytes(json.dumps(RUNS,indent=2).encode())
 def test_cache_elastic_consume_refill_and_maximum_geometry(self):
  self.replay(mode=1);self.replay(128,1024,mode=1)
 def test_reader_two_credit_continuous_and_stalled_order(self):
  self.replay();self.replay(stall=1,faults=True)
 def test_cache_fault_order_tail_and_held_payload(self):self.replay(65,17,mode=1,stall=1,faults=True)
 def test_cancel_queued_cache_response_and_held_output_restart(self):
  for point in (1,2,3,4,5):self.replay(stall=1,abort=point,faults=True)
if __name__=='__main__':unittest.main()
