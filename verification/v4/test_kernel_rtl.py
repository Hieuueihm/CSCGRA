"""Generic 32-PE kernel exact integer replay through the actual B cache."""
import hashlib
import json
from pathlib import Path
import random
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl,filelist_sources,run_rtl
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
S_MIN=-(1<<26)
S_MAX=(1<<26)-1

def rounded(value,shift):
    magnitude=abs(value)
    if shift: magnitude=(magnitude+(1<<(shift-1)))>>shift
    return -magnitude if value<0 else magnitude

def oracle(op,a,b,sa,sb,shift):
    raw=0
    if op==7: return [],0,sum(x*x for x in a)
    if op==10:return [],0,sa*sa+sb*sb
    if op==9:
        raw=rounded(sa*sb,22)
        return [],int(not S_MIN<=raw<=S_MAX)*3,raw
    if op==0:out=[0]*len(a)
    elif op==1:out=a[:]
    elif op==2:out=[x+y for x,y in zip(a,b)]
    elif op==3:out=[x-y for x,y in zip(a,b)]
    elif op in (4,5):out=[rounded(x*sa,22 if op==4 else shift) for x in a]
    elif op==8:
        narrowed=[rounded(x,2) for x in a]
        if any(not -(1<<23)<=x<(1<<23) for x in narrowed):return [],4,0
        out=[x*4 for x in narrowed]
    else:raise ValueError(op)
    if any(not S_MIN<=x<=S_MAX for x in out):return [],4 if op==5 else 3,0
    return out,0,0

def cases():
    rng=random.Random(6090932)
    for op in (0,1,2,3,4,5,7,8,9,10):
        for case in range(10):
            n=(1,31,32,33,96,128)[case%6]
            limits=[S_MIN,S_MIN+1,-33554432,-3,-2,-1,0,1,2,3,33554430,33554431,S_MAX]
            a=[rng.choice(limits) if case<4 else rng.randrange(-5000000,5000000) for _ in range(n)]
            b=[rng.choice(limits) if case<4 else rng.randrange(-5000000,5000000) for _ in range(n)]
            sa=(0,1,-1,2097152,-4194304,S_MIN,S_MAX,4194303,1234567,-3333333)[case]
            sb=(S_MIN,S_MAX,-4194304,2097152,-1,0,1,1234567,-3333333,4194304)[case]
            shift=(0,1,10,22,26,31,63,2,21,27)[case]
            out,fault,scalar=oracle(op,a,b,sa,sb,shift)
            row=[op,n,sa,sb,shift,fault,scalar]+a+[0]*(128-n)+b+[0]*(128-n)+out+[0]*(128-len(out))
            yield ' '.join(map(str,row))

class KernelRtlTests(unittest.TestCase):
    def test_integer_commands_real_b_cache_transactional_faults(self):
        path=Path(tempfile.mkdtemp(prefix='kernel_',dir=ROOT/'work'))
        vectors=path/'oracle.txt';vectors.write_text('\n'.join(cases())+'\n')
        sim=path/'kernel.xsim.json'
        sources=filelist_sources(ROOT)+[ROOT/p for p in ('rtl/v4/memory/vector_workspace.sv','rtl/v4/compute/kernel_fabric.sv','rtl/v4/compute/kernel_engine.sv','verification/v4/compute/tb_kernel.sv')]
        compiled=compile_rtl(sim,'tb_kernel',sources,root=ROOT)
        self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
        result=run_rtl(sim,['+oracle='+vectors.as_posix()],root=ROOT)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        match=re.search(r'PASS kernel checks=(\d+) cycles=(\d+)',result.stdout)
        self.assertIsNotNone(match,result.stdout)
        self.assertIn('ORACLE cases=100',result.stdout)
        stalls=re.search(r'STALLS request=(\d+) response=(\d+)',result.stdout)
        self.assertGreater(int(stalls[1]),0);self.assertGreater(int(stalls[2]),0)
        RUNS.append(dict(test=self.id(),comparisons=int(match[1]),cycles=int(match[2]),oracle_cases=100,
                         request_stalls=int(stalls[1]),response_stalls=int(stalls[2]),
                         vectors_sha256=hashlib.sha256(vectors.read_bytes()).hexdigest(),
                         commands=compiled.commands+result.commands,stdout=result.stdout))
        (path/'evidence.json').write_text(json.dumps(RUNS[-1],indent=2))

if __name__=='__main__':unittest.main()
