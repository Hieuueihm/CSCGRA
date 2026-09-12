"""Scalar leaf RTL replay using a non-iterative, arbitrary-integer oracle."""
import hashlib
import json
import math
import os
from pathlib import Path
import random
import shutil
import tempfile
import unittest

from scripts.v4.generate_scalar_interface import ROOT, render
from scripts.v4.xsim import compile_rtl, run_rtl

RUNS=[]
INPUTS=['rst','cancel','req_valid','rsp_ready','req_op','req_a','req_b',
        'req_source_frac','req_job','req_tag','req_fmt']
WIDTHS=[1,1,1,1,2,64,64,8,16,16,8]

def oracle(op,a,b,frac,fmt):
    frac &= 255
    if fmt!=1 or op not in (0,1,2) or (frac not in (0,246) if op==0 else frac!=44):
        return 0,1,1
    if op==0:
        if b==0: return 0,2,1
        # Independent direct rational nearest operation, not restoring division.
        scaled=abs(a)<<(22 if frac==0 else 32)
        if (scaled>>27)>=abs(b):return 0,4,1
        magnitude=(2*scaled+abs(b))//(2*abs(b))
        result=-magnitude if (a<0)!=(b<0) else magnitude
        latency=28
    elif op==1:
        if a<0: return 0,3,1
        result=math.isqrt(a)
        if 4*a >= (2*result+1)**2: result+=1
        latency=33
    else:
        magnitude=(2*abs(a)+(1<<22))//(2*(1<<22))
        result=-magnitude if a<0 else magnitude
        latency=1
    return (0,4,latency) if not -(1<<26)<=result<(1<<26) else (result,0,latency)

class Replay:
    def __init__(self):
        self.rows=[]; self.expected=[]; self.left=0; self.valid=0
        self.payload=[0,0,0,0,0]; self.pending=None
        self.accepted=0; self.retired=0; self.flushed=0
        self.step(rst=1)

    def output(self,p):
        return [int(not(self.left or self.valid or p['rst'] or p['cancel'])),
                int(self.valid and not(p['rst'] or p['cancel'])),*self.payload]

    def step(self,**pins):
        p=dict.fromkeys(INPUTS,0); p.update(req_fmt=1); p.update(pins)
        self.rows.append(' '.join(f'{p[k]&((1<<w)-1):x}' for k,w in zip(INPUTS,WIDTHS)))
        self.expected.append(self.output(p) if len(self.rows)>1 else None)
        if p['rst'] or p['cancel']:
            self.flushed+=int(bool(self.left or self.valid))
            self.left=0; self.valid=0; self.payload=[0,0,0,0,0]
        elif self.left:
            self.left-=1
            if not self.left:
                data,fault=self.pending
                self.payload[:2]=[data&((1<<27)-1),fault]
                self.valid=1
        elif self.valid:
            if p['rsp_ready']:
                self.retired+=1; self.valid=0; self.payload=[0,0,0,0,0]
        elif p['req_valid']:
            data,fault,self.left=oracle(p['req_op'],p['req_a'],p['req_b'],p['req_source_frac'],p['req_fmt'])
            self.pending=(data,fault)
            self.payload=[0,fault if self.left==1 else 0,p['req_job'],p['req_tag'],p['req_fmt']]
            self.accepted+=1
        self.expected.append(self.output(p))

    def transaction(self,a,b=0,op=0,frac=None,fmt=1,stall=2):
        if frac is None: frac=0 if op==0 else 44
        tag=self.accepted&65535
        self.step(req_valid=1,req_op=op,req_a=a,req_b=b,req_source_frac=frac,
                  req_job=65535-tag,req_tag=tag,req_fmt=fmt)
        latency=self.left
        for i in range(latency):
            # Mutating busy request cannot alter the accepted operation.
            self.step(req_valid=1,req_op=3,req_a=-(1<<63)+i,req_b=i,
                      req_job=i,req_tag=65535-i,req_fmt=255,rsp_ready=i&1)
        for i in range(stall): self.step(req_valid=1,req_a=i,req_b=1,req_fmt=7)
        self.step(req_valid=1,req_a=99,req_b=1,rsp_ready=1)
        assert self.left==0 and self.valid==0

    def run(self,test):
        work=ROOT/'work'; work.mkdir(exist_ok=True)
        path=Path(tempfile.mkdtemp(prefix='v4_scalar_',dir=work))
        try:
            src=path/'vectors.txt'; dst=path/'trace.txt'; sim=path/'sim.xsim.json'
            src.write_text('\n'.join(self.rows)+'\n')
            compiled=compile_rtl(sim,'tb_arithmetic_service',
                ['rtl/v4/services/arithmetic_service.sv','verification/v4/program/tb_arithmetic_service.sv'],root=ROOT)
            test.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
            run=run_rtl(sim,['+src='+src.as_posix(),'+dst='+dst.as_posix()],root=ROOT)
            logs=compiled.commands+run.commands
            test.assertEqual(run.returncode,0,run.stdout+run.stderr)
            test.assertIn('PASS cycles=',run.stdout)
            lines=dst.read_text().splitlines()
            test.assertEqual(len(lines),len(self.expected))
            for i,(line,expected) in enumerate(zip(lines,self.expected)):
                cells=line.split()
                test.assertEqual([int(x) for x in cells[:2]],[i//2,i%2])
                if expected is not None:
                    test.assertEqual([int(x,16) for x in cells[2:]],expected,f'cycle {i//2} phase {i%2}')
            RUNS.append(dict(test=test.id(),status='PASS',stdout=run.stdout,compiler_stdout=compiled.stdout,compiler_stderr=compiled.stderr,
                             cycles=len(self.rows),comparisons=(len(self.expected)-1)*7,
                             accepted=self.accepted,retired=self.retired,flushed=self.flushed,
                             vectors_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),
                             trace_sha256=hashlib.sha256(dst.read_bytes()).hexdigest(),commands=logs))
        finally:
            if not os.environ.get('V4_SCALAR_KEEP'): shutil.rmtree(path)

class ArithmeticRtlTests(unittest.TestCase):
    def test_generated_interface(self):
        self.assertEqual((ROOT/'rtl/v4/include/scalar_interface.vh').read_text(),render())

    def test_div_boundaries_rounding_and_random(self):
        r=Replay(); rng=random.Random(9501)
        values=[-(1<<63),-(1<<63)+1,-(1<<26),-17,-16,-1,0,1,15,16,17,(1<<26)-1,(1<<27),(1<<63)-1]
        for a in values:
            for b in values: r.transaction(a,b,stall=rng.randrange(4))
        # Exact half ties and one side of each tie, both signs and denominator signs.
        for q in (0,1,2,(1<<26)-2,(1<<26)-1,1<<26):
            for delta in (-1,0,1):
                for sign in (-1,1):
                    for ds in (-1,1): r.transaction(sign*((2*q+1)*(1<<22)+delta),ds*(1<<45))
        for _ in range(350):
            r.transaction(rng.randrange(-(1<<63),1<<63),rng.randrange(-(1<<63),1<<63),stall=rng.randrange(5))
        r.run(self)

    def test_sqrt_boundaries_rounding_and_random(self):
        r=Replay(); rng=random.Random(9502)
        for q in (0,1,2,3,255,(1<<26)-2,(1<<26)-1,1<<26,(1<<31)-1):
            for n in (q*q-1,q*q,q*q+q,q*q+q+1,(q+1)**2-1):
                r.transaction(n,op=1,stall=rng.randrange(5))
        for n in (-(1<<63),-1,(1<<63)-1): r.transaction(n,op=1)
        for _ in range(300):
            r.transaction(rng.randrange(1<<rng.randrange(1,64)),op=1,stall=rng.randrange(5))
        r.run(self)

    def test_modes_and_fault_precedence(self):
        r=Replay()
        for op in range(4):
            for fmt in (0,1,2,255):
                for frac in (0,1,22,44,246,255):
                    r.transaction(-1,0,op=op,fmt=fmt,frac=frac)
        r.run(self)

    def test_reset_cancel_every_iteration_and_pending_response(self):
        r=Replay()
        for flush in ('rst','cancel'):
            for op,latency in ((0,28),(1,33),(2,1)):
                for delay in range(latency+4):
                    r.step(req_valid=1,req_op=op,req_a=1234567,req_b=7654321,
                           req_source_frac=0 if op==0 else 44,req_job=41,req_tag=89)
                    for _ in range(delay): r.step()
                    r.step(**{flush:1},req_valid=1,req_a=1,req_b=1,rsp_ready=1)
                    for _ in range(latency+1): r.step(rsp_ready=1)
                    r.transaction(1,1,stall=0)
        # Flush short domain/mode faults, then prove fresh acceptance.
        for delay in (0,1,3):
            r.step(req_valid=1,req_b=0)
            for _ in range(delay):r.step()
            r.step(cancel=1,rst=1,req_valid=1,rsp_ready=1)
            r.transaction(-16,1)
        r.run(self)

    def test_mp_fraction_negative_ties_and_ranges(self):
        r=Replay();rng=random.Random(1781)
        for a in [-(1<<63),-1,0,1,(1<<26)-1,(1<<63)-1]:
            for b in [-(1<<63),-1,0,1,32,1<<40,(1<<63)-1]:r.transaction(a,b,frac=-10)
        for _ in range(500):r.transaction(rng.randrange(-(1<<63),1<<63),rng.randrange(-(1<<63),1<<63),frac=-10)
        for q in [0,1,2,(1<<26)-1,1<<26]:
            for sign in [-1,1]:
                for delta in [-1,0,1]:r.transaction(sign*((2*q+1)*(1<<20)+delta),1<<53,frac=-10)
        r.run(self)

    def test_rescale_signed_ties_limits_random_and_stalls(self):
        r=Replay();rng=random.Random(20260909)
        for value in [-(1<<63),(1<<63)-1,0,1,-1]:r.transaction(value,op=2)
        for q in [0,1,2,(1<<26)-2,(1<<26)-1,1<<26]:
            for sign in [-1,1]:
                for delta in [-1,0,1]:r.transaction(sign*((2*q+1)*(1<<21)+delta),op=2,stall=rng.randrange(6))
        for _ in range(400):r.transaction(rng.randrange(-(1<<49),1<<49),op=2,stall=rng.randrange(6))
        r.run(self)

if __name__=='__main__':unittest.main()

