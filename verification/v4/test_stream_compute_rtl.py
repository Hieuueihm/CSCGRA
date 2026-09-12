"""Cycle-independent integer scoreboard of every speculative stream frame."""
import hashlib,json,random,re,tempfile,unittest
from pathlib import Path
from scripts.v4.xsim import compile_rtl,run_rtl
from verification.v4.stream.arithmetic_oracle import arithmetic
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
OPS={1:0,2:1,3:2,8:3,9:4}
def pack(v,w):return sum((x&((1<<w)-1))<<(i*w) for i,x in enumerate(v))
def context(op=9,mode=0,a=0,b=1,imm=0):return op|(mode<<5)|(a<<6)|(b<<8)|((imm&((1<<27)-1))<<10)
def sign(v,w):return v-(1<<w) if v>>(w-1) else v
def vectors():
 rng=random.Random(9322026)
 for case in range(44):
  cfg_error=0;abort=0;fmt=1;stall=0 if case<2 else 1;frames=32 if case<2 else rng.randrange(2,18)
  contexts=[context(mode=case) for _ in range(32)] if case<2 else [context(rng.choice(list(OPS)),rng.randrange(2),rng.randrange(4),rng.randrange(4),rng.randrange(-(1<<26),(1<<26))) for _ in range(32)]
  if case==2:contexts=[context(9,1,0,0) for _ in range(32)] # ENERGY
  if case==3:contexts=[context(9,1) for _ in range(32)] # signed DOT
  if case in (4,5):contexts=[context(8,case-4) for _ in range(32)]
  if case==6:contexts=[context(1,0,2,3,i*7919-12345) for i in range(32)]
  if case in (7,8,9):abort=case-6
  if case==10:fmt=2;frames=0
  if case in (11,12):contexts[17]=(1<<63) if case==11 else 31;cfg_error=1;frames=0
  if case in (14,15):abort=case-10
  if case==13:contexts=[context(9,1) for _ in range(32)];frames=3
  yield f'{pack(contexts,64):0512x} {fmt} {frames} {abort} {stall} {cfg_error}'
  acc=[0]*32
  for frame in range(frames):
   extremes=[-(1<<26),(1<<26)-1,-131073,-131072,-65536,-1,0,1,65536,131071,131072]
   a=[rng.choice(extremes) if case>=2 else rng.randrange(-100000,100000) for _ in range(32)]
   b=[rng.choice(extremes) if case>=2 else rng.randrange(-100000,100000) for _ in range(32)]
   mask=(1<<32)-1 if case<2 else rng.getrandbits(32)
   if case==13:mask=0 if frame==2 else (1<<32)-1
   if case==3:b=[-v for v in a];a=[min(max(v,-30000000),30000000) for v in a];b=[-v for v in a]
   data=[];faults=[]
   for lane,word in enumerate(contexts):
    op=word&31;mode=(word>>5)&1;imm=sign((word>>10)&((1<<27)-1),27)
    sources=[a[lane],b[lane],imm,0]
    d,acc[lane],f=arithmetic(OPS[op],mode,sources[(word>>6)&3],sources[(word>>8)&3],acc[lane],bool(mask>>lane&1));data.append(d);faults.append(f)
   yield f'{pack(a,27):0216x} {pack(b,27):0216x} {mask:08x} {pack(data,27):0216x} {pack(acc,64):0512x} {pack(faults,4):032x}'
class StreamComputeRtlTests(unittest.TestCase):
 def test_independent_contexts_pipeline_and_transactions(self):
  path=Path(tempfile.mkdtemp(prefix='stream_compute_',dir=ROOT/'work'));source=path/'input.txt';trace=path/'trace.txt';binary=path/'sim.xsim.json'
  source.write_text('\n'.join(vectors())+'\n')
  files=['rtl/v4/compute/stream_pe.sv','rtl/v4/compute/stream_array.sv','rtl/v4/compute/stream_fabric.sv','verification/v4/stream/tb_stream.sv']
  compiled=compile_rtl(binary,'tb_stream',files,root=ROOT)
  self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
  result=run_rtl(binary,['+source='+source.as_posix(),'+trace='+trace.as_posix()],root=ROOT)
  self.assertEqual(result.returncode,0,result.stdout+result.stderr)
  m=re.search(r'PASS stream cases=(\d+) checks=(\d+) cycles=(\d+) accepted=(\d+) retired=(\d+) aborts=(\d+)',result.stdout)
  self.assertIsNotNone(m,result.stdout);cases,checks,cycles,accepted,retired,aborts=map(int,m.groups());self.assertEqual(cases,44);self.assertEqual(aborts,5)
  record=dict(status='PASS',test=self.id(),cases=cases,comparisons=checks,cycles=cycles,accepted=accepted,retired=retired,aborts=aborts,
      measured_unstalled_C18_MAC_II=1,measured_unstalled_S27_MAC_II=2,commands=compiled.commands+result.commands,stdout=result.stdout,
      vectors_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(),
      source_sha256={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files})
  RUNS.append(record);(path/'evidence.json').write_text(json.dumps(record,indent=2)+'\n')
if __name__=='__main__':unittest.main()
