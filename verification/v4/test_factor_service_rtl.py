"""Generic factor transfer worker: independent coordinates and integer data oracle."""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl, run_rtl
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['rtl/v4/memory/factor_store.sv','rtl/v4/dataflow/factor_service.sv','verification/v4/program/tb_factor_service.sv']
RUNS=[]

def signed(x):
    return x-(1<<27) if x&(1<<26) else x

class Replay:
    def __init__(self,m,s,zero=False):
        self.m=m;self.s=s;self.lines=[];self.expected={};self.outputs={};self.bundles={}
        self.matrix=[[0 if zero else ((r*101+c*53)%65521)-32760 for c in range(s)] for r in range(m)]
        self.initial_pool=[(i*73)%400001-200000 for i in range(15360)]
        self.pool=self.initial_pool.copy();self.factor=None
    def command(self,op,length=0,index=0,start=0,flags=0,src=0,dst=100,fault=0,inject=0,at=0,cancel=0,gen=1,fmt=1,dense=1,cols=None):
        cols=self.s if cols is None else cols
        count=cols if op in (13,19) else length
        if fault:count=0
        self.lines.append(' '.join(map(str,[op,length,index,start,flags,src,dst,fault,count,inject,at,cancel,gen,fmt,dense,cols])))
        n=len(self.lines)
        if op==0:self.expected[n]=('PHI',);return
        if cancel:self.expected[n]=('CANCEL',);self.factor=None;return
        if fault:self.expected[n]=('RESULT',fault,0,0,0);self.factor=None;return
        if op==13:
            self.factor=[[x<<6 for x in row[:cols]] for row in self.matrix]
            self.s=cols
            values=[x for row in self.factor for x in row]
        elif op==19:
            values=[x<<6 for row in self.matrix for x in row[self.s:cols]]
            for r in range(self.m):
                self.factor[r].extend(x<<6 for x in self.matrix[r][self.s:cols])
            self.s=cols
        else:
            coords=[(index,start+i) if flags&1 else (start+i,index) for i in range(length)]
            if op==15:
                values=self.pool[src*32:src*32+length]
                for (r,c),v in zip(coords,values):self.factor[r][c]=v
            else:
                values=[self.factor[r][c] for r,c in coords]
                self.outputs[n]=values;self.pool[dst*32:dst*32+length]=values
            bundles=[]
            for offset in range(0,length,32):
                mask=0;addresses={}
                for r,c in coords[offset:offset+32]:
                    bank=(r+c)%32;mask|=1<<bank;addresses[bank]=r*3+c//32
                bundles.append((int(op==15),mask,addresses))
            self.bundles[n]=bundles
        self.expected[n]=('RESULT',0,count,length if op==14 else 0,int(any(values)))
    def init(self,**kw):self.command(13,self.m,**kw)

class FactorServiceRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=Path(tempfile.mkdtemp(prefix='factor_service_',dir=ROOT/'work'))
        cls.binary=cls.folder/'factor.xsim.json'
        cls.paths=SOURCES+['verification/v4/test_factor_service_rtl.py','scripts/v4/xsim.py','config/v4_kernel_interface.json']+[p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl/v4/include').glob('*.vh')]
        cls.before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in cls.paths}
        cls.compiled=compile_rtl(cls.binary,'tb_factor_service',SOURCES,root=ROOT,timeout=240)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    def replay(self,im):
        case=self.folder/(self._testMethodName+'_'+str(im.m)+'_'+str(im.s));case.mkdir()
        dense=[0]*(128*96)
        for r,row in enumerate(im.matrix):
            for c,value in enumerate(row):dense[r*96+c]=value
        for name,values,width in [('matrix_dense',dense,18),('pool',im.initial_pool,27)]:
            (case/(name+'.hex')).write_text(''.join(f'{v&((1<<width)-1):x}\n' for v in values))
        (case/'commands.txt').write_text('\n'.join(im.lines)+'\n')
        args=[f'{key}={(case/name).as_posix()}' for key,name in [('matrix_dense','matrix_dense.hex'),('pool','pool.hex'),('commands','commands.txt'),('trace','trace.txt')]]+[f'm={im.m}',f's={im.s}']
        result=run_rtl(self.binary,args,root=ROOT,timeout=240)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        match=re.search(r'PASS factor commands=(\d+) cycles=(\d+)',result.stdout);self.assertIsNotNone(match,result.stdout)
        self.assertEqual(int(match[1]),len(im.lines))
        outcomes={};outputs={};banks={};mat_counts={};checks=0
        command_fields={n:list(map(int,line.split())) for n,line in enumerate(im.lines,1)}
        for line in (case/'trace.txt').read_text().splitlines():
            fields=line.split();kind=fields[0];n=int(fields[1])
            if kind in ('PHI','CANCEL','RESULT'):
                self.assertNotIn(n,outcomes);outcomes[n]=(kind,*map(int,fields[2:]))
            elif kind=='OUT':
                values=outputs.setdefault(n,[]);self.assertEqual(int(fields[2]),len(values));values.append(signed(int(fields[3],16)));checks+=1
            elif kind=='BANK':
                write,mask,address=int(fields[2]),int(fields[3],16),int(fields[4],16)
                banks.setdefault(n,[]).append((write,mask,{b:(address>>(9*b))&511 for b in range(32) if mask>>b&1}))
            elif kind=='MAT':
                k=mat_counts.get(n,0);mat_counts[n]=k+1
                op,index,command_cols=command_fields[n][0],command_fields[n][2],command_fields[n][15]
                c=(0 if op==13 else index)+k//((im.m+31)//32);block=k%((im.m+31)//32)
                mask=int(fields[2],16);addresses=int(fields[3],16);expected_mask=0
                for r in range(block*32,min(im.m,block*32+32)):
                    b=(r+c)%32;expected_mask|=1<<b
                    self.assertEqual((addresses>>(9*b))&511,r*((command_cols+31)//32)+c//32);checks+=1
                self.assertEqual(mask,expected_mask)
        self.assertEqual(outcomes,im.expected);self.assertEqual(outputs,im.outputs)
        for n,expected in im.bundles.items():self.assertEqual(banks.get(n,[]),expected);checks+=len(expected)
        for n,row in enumerate(im.lines,1):
            fields=list(map(int,row.split()))
            if fields[0] in (13,19) and fields[7]==0 and fields[11]==0:
                first_col=0 if fields[0]==13 else fields[2]
                self.assertEqual(mat_counts[n],(fields[15]-first_col)*((im.m+31)//32))
        self.assertEqual(self.before,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in self.paths})
        RUNS.append(dict(test=self.id(),status='PASS',cycles=int(match[2]),comparisons=checks,comparison_kind='coordinate and raw-value checks',commands=self.compiled.commands+result.commands,source_sha256=self.before,stdout=result.stdout,compile_stdout=self.compiled.stdout,compile_stderr=self.compiled.stderr,input_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in case.iterdir()},trace=(case/'trace.txt').read_text()))
        (self.folder/'evidence.json').write_text(json.dumps(RUNS,indent=2))
    def test_early_nonfinal_load_fault(self):
        im=Replay(33,2);im.init(fault=7,inject=9);im.init();im.command(14,33,index=1);self.replay(im)
    def test_extend_preserves_written_prefix(self):
        im=Replay(33,4)
        im.init(cols=2)
        im.command(15,1,index=0,start=0,flags=1,src=3,cols=2)
        im.command(19,33,index=2,start=0,cols=4,gen=2)
        im.command(14,4,index=0,start=0,flags=1,dst=40,cols=4,gen=2)
        self.replay(im)
    def test_extend_crosses_live_B_strides_at_maximum_shape(self):
        im=Replay(128,96)
        im.init(cols=31)
        sentinel=[-500000+i*7919 for i in range(128)]
        im.initial_pool[3*32:3*32+128]=sentinel
        im.pool[3*32:3*32+128]=sentinel
        im.command(15,128,index=0,start=0,src=3,cols=31)
        im.command(19,128,index=31,cols=33,gen=2)
        im.command(14,128,index=0,dst=300,cols=33,gen=2)
        im.command(14,128,index=32,dst=304,cols=33,gen=2)
        im.command(19,128,index=33,cols=63,gen=3)
        im.command(14,128,index=0,dst=308,cols=63,gen=3)
        im.command(14,128,index=62,dst=312,cols=63,gen=3)
        im.command(19,128,index=63,cols=65,gen=4)
        im.command(14,128,index=0,dst=316,cols=65,gen=4)
        im.command(14,128,index=64,dst=320,cols=65,gen=4)
        im.command(19,128,index=65,cols=96,gen=5)
        im.command(14,128,index=0,dst=324,gen=5)
        im.command(14,128,index=95,dst=328,gen=5)
        for col in range(96):
            im.command(14,128,index=col,dst=col*5,cols=96,gen=5)
        self.replay(im)
    def test_extend_rejects_and_invalidates_after_partial_load(self):
        im=Replay(33,6)
        im.init(cols=2)
        im.command(19,33,index=1,cols=4,gen=2,fault=4)
        im.command(14,1,fault=5)
        im.init(cols=2)
        im.command(19,33,index=2,cols=97,gen=2,fault=4)
        im.command(14,1,fault=5)
        im.init(cols=2)
        im.command(19,33,index=2,cols=4,gen=3,fault=6)
        im.command(14,1,gen=2,fault=5)
        im.init(cols=2)
        im.command(19,33,index=2,cols=4,gen=2,fault=7,inject=3,at=2)
        im.command(14,1,fault=5)
        im.init(cols=2)
        im.command(19,33,index=2,cols=4,gen=2,cancel=6)
        im.command(14,1,fault=5)
        self.replay(im)
    def test_extend_requires_next_epoch_and_rebases_after_commit(self):
        im=Replay(33,4)
        im.init(cols=2,gen=1)
        im.command(19,33,index=2,cols=4,gen=2)
        im.command(14,1,index=0,start=0,flags=1,gen=1,fault=6)
        im.init(cols=2,gen=1)
        im.command(19,33,index=2,cols=4,gen=1,fault=6)
        im.init(cols=2,gen=1)
        im.command(19,33,index=2,cols=4,gen=3,fault=6)
        im.init(cols=2,gen=0xffffffff)
        im.command(19,33,index=2,cols=4,gen=0)
        im.command(14,4,index=0,start=0,flags=1,dst=40,cols=4,gen=0)
        self.replay(im)
    def test_full_bundles_unaligned_ranges_and_epoch(self):
        im=Replay(128,96);im.init();im.command(14,128,index=95);im.command(14,96,index=127,flags=1)
        im.command(15,65,index=127,start=31,flags=1,src=20);im.command(14,96,index=127,flags=1)
        im.command(15,127,index=95,start=1,src=30);im.command(14,128,index=95)
        im.command(0);im.command(14,33,index=3);im.command(14,1,gen=2,fault=6);im.init(gen=2);im.command(14,1,gen=2)
        self.replay(im)
    def test_faults_cancel_and_reinitialization(self):
        im=Replay(96,35);im.command(14,1,fault=5)
        for injection in range(1,6):im.init(fault=7 if injection==3 else 6,inject=injection,at=1)
        for injection in (6,7,8):
            im.init();im.command(15,65,index=1,inject=injection,at=2,fault=7 if injection==8 else 6)
        for mode,op in [(1,13),(2,15),(3,15),(4,14),(5,14)]:
            im.init();im.command(op,96 if op==13 else 65,index=0,cancel=mode)
            im.command(14,1,fault=5)
        im.init();im.command(14,0,fault=4);im.init();im.command(14,2,index=34,start=95,fault=4)
        im.init();im.command(14,1,flags=2,fault=1);im.init();im.command(14,1,fmt=0,fault=1)
        im.init();im.command(14,1,dense=0,fault=1);im.init();im.command(14,33,index=34)
        self.replay(im)
    def test_zero_masked_padding_and_odd_shape(self):
        im=Replay(5,3,zero=True);im.init();im.command(14,5,index=2);im.command(14,3,index=4,flags=1);self.replay(im)
        im=Replay(33,17);im.init();im.command(15,17,index=32,flags=1,src=5);im.command(14,17,index=32,flags=1);im.command(14,32,index=16,start=1);self.replay(im)

if __name__=='__main__':unittest.main()
