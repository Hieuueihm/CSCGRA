"""Fixed-stride S27 factor RAM: independent coordinate mapping, Vivado only."""
import hashlib
import json
from pathlib import Path
import random
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl, run_rtl
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['rtl/v4/memory/factor_store.sv','verification/v4/memory/tb_factor_store.sv']
EXTRAS=['verification/v4/test_factor_store_rtl.py','scripts/v4/xsim.py','docs/v4/architecture/QR_SOLVER.md']
RUNS=[]

def pack(values,width):
    return sum((x&((1<<width)-1))<<(i*width) for i,x in enumerate(values))

class Image:
    def __init__(self,rows=33,cols=17):
        self.rows=rows;self.cols=cols;self.lines=[];self.tag=0
        self.values={(r,c): ((r*197+c*997)%134217728)-67108864 for r in range(rows) for c in range(cols)}
    def load(self,cols=None):
        cols=self.cols if cols is None else cols
        self.lines.append(f'0 {self.rows} {cols} 1 -1')
        for c in range(cols):
            for b in range((self.rows+31)//32):
                data=[self.values[r,c] for r in range(b*32,min(self.rows,b*32+32))]
                last=c+1==cols and (b+1)*32>=self.rows
                self.lines.append(f'1 {c} {b} {(1<<len(data))-1:x} {pack(data,27):x} {int(last)} {0 if last else -1}')
        return self
    def append(self,old_cols,cols=None,fault=-1,probe=0,generation=4):
        cols=self.cols if cols is None else cols
        self.lines.append(f'11 {self.rows} {cols} {old_cols} 1 {fault} {probe} {generation}')
        if fault<0:
            for c in range(old_cols,cols):
                for b in range((self.rows+31)//32):
                    data=[self.values[r,c] for r in range(b*32,min(self.rows,b*32+32))]
                    last=c+1==cols and (b+1)*32>=self.rows
                    self.lines.append(f'1 {c} {b} {(1<<len(data))-1:x} {pack(data,27):x} {int(last)} {0 if last else -1}')
        self.cols=cols
        return self
    def request(self,coords,write=False,values=None,fault=0,key=0x1234,generation=3,job=7,fmt=1,bad_address=None):
        addr=[511]*32;data=[0]*32;gold=[0]*32;mask=0
        for i,(r,c) in enumerate(coords):
            bank=(r+c)%32
            assert not mask>>bank&1,'bank conflict in test vector'
            mask|=1<<bank;addr[bank]=r*3+c//32
            if write:data[bank]=values[i]
            elif not fault:gold[bank]=self.values[r,c]
        if bad_address is not None:addr[coords and (coords[-1][0]+coords[-1][1])%32 or 0]=bad_address
        if write and not fault:
            for xy,v in zip(coords,values):self.values[xy]=v
        self.tag+=1
        self.lines.append(f'2 {int(write)} {mask:x} {pack(addr,9):x} {pack(data,27):x} {key:x} {generation} {job} {self.tag} {fmt} {fault} {pack(gold,27):x}')
    def row(self,r,start=0,size=None,**kwargs):
        self.request([(r,c) for c in range(start,min(self.cols,start+(32 if size is None else size)))],**kwargs)
    def col(self,c,start=0,size=None,**kwargs):
        self.request([(r,c) for r in range(start,min(self.rows,start+(32 if size is None else size)))],**kwargs)

class FactorStoreRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=Path(tempfile.mkdtemp(prefix='factor_store_',dir=ROOT/'work'))
        cls.binary=cls.folder/'factor.xsim.json'
        cls.paths=SOURCES+EXTRAS+[p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl/v4/include').glob('*.vh')]
        cls.before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in cls.paths}
        cls.compiled=compile_rtl(cls.binary,'tb_factor_store',SOURCES,root=ROOT,timeout=240)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    def replay(self,lines):
        path=self.folder/(self._testMethodName+'.txt');path.write_text('\n'.join(lines)+'\n')
        result=run_rtl(self.binary,['vectors='+path.as_posix()],root=ROOT,timeout=240)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        match=re.search(r'PASS factor_store cycles=(\d+) checks=(\d+) accepted=(\d+) retired=(\d+) flushed=(\d+) max_run=(\d+)',result.stdout)
        self.assertIsNotNone(match,result.stdout)
        cycles,checks,accepted,retired,flushed,max_run=map(int,match.groups())
        self.assertEqual(accepted,retired+flushed)
        self.assertEqual(self.before,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in self.paths})
        RUNS.append(dict(test=self.id(),cycles=cycles,comparisons=checks,accepted=accepted,retired=retired,flushed=flushed,max_consecutive_grants=max_run,commands=self.compiled.commands+result.commands,source_sha256=self.before,vectors_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),stdout=result.stdout))
        (self.folder/'evidence.json').write_text(json.dumps(RUNS,indent=2))
    def test_shapes_full_rows_columns_and_extrema(self):
        lines=[]
        for m,s in [(1,1),(33,1),(33,33),(128,96)]:
            im=Image(m,s).load()
            for r in range(m):
                for c in range(0,s,32):im.row(r,c)
            for c in range(s):
                for r in range(0,m,32):im.col(c,r)
            im.lines+=['4'];lines+=im.lines
        self.replay(lines)
    def test_masked_write_read_ordering_and_two_ports(self):
        im=Image(128,96).load();rng=random.Random(91231)
        for k in range(128):
            r=k%128;c=(k%3)*32
            coords=[(r,j) for j in range(c,c+32) if j%3!=0]
            im.request(coords,write=True,values=[rng.randrange(-(1<<26),1<<26) for _ in coords])
            im.row(r,c)
        for c in range(96):
            for r in range(0,128,32):im.col(c,r)
        self.replay(im.lines)
    def test_credits_continuous_grants_and_cancel_pending(self):
        im=Image(33,33).load();im.lines+=['8 0']
        for i in range(512):im.row(i%33)
        im.lines+=['4','10 512','8 2'];im.row(0);im.col(1);im.lines+=['9','3','8 0']
        im.row(0,fault=3);im.lines+=['4'];im.load();im.col(2)
        im.lines+=['4','8 2'];im.row(1);im.lines+=['6','8 0'];im.row(1,fault=3)
        self.replay(im.lines)
    def test_metadata_address_faults_and_failed_write_atomicity(self):
        im=Image(33,33).load()
        for kw in [dict(key=99),dict(generation=4),dict(job=8),dict(fmt=0)]:im.row(0,fault=3,**kw)
        im.row(0,fault=4,bad_address=384)
        coords=[(0,c) for c in range(32)];im.request(coords,write=True,values=[7]*32,fault=4,bad_address=511);im.row(0)
        im.request([],fault=0);im.row(0)
        self.replay(im.lines)
    def test_loader_shape_order_mask_padding_last_reset_cancel(self):
        lines=['0 0 1 1 1','0 129 1 1 1','0 1 0 1 1','0 1 97 1 1','0 1 1 0 1']
        badfills=['1 1 0 1 0 1 2','1 0 1 1 0 1 2','1 0 0 3 0 1 2','1 0 0 1 8000000 1 2','1 0 0 1 0 0 2']
        for fill in badfills:lines+=['0 1 1 1 -1',fill]
        lines+=['0 33 1 1 -1','1 0 0 ffffffff 0 0 -1','3']
        im=Image(33,1);im.row(0,fault=3);lines+=im.lines
        lines+=['4','0 33 1 1 -1','1 0 0 ffffffff 0 0 -1','6']
        lines+=['0 1 1 1 -1','1 0 0 1 0 1 -2','3','0 1 1 0 -2','6']
        im=Image(1,1).load();im.row(0);lines+=im.lines
        self.replay(lines)
    def test_append_preserves_prefix_and_excludes_request(self):
        good=Image(33,4).load(2).append(2,4,probe=1)
        good.row(0,generation=3,fault=3)
        good.row(0,generation=4);good.col(3,generation=4)
        self.replay(good.lines)
    def test_append_rejects_bad_old_count(self):
        bad=Image(33,4).load(2).append(1,4,fault=1,probe=1)
        self.replay(bad.lines)
