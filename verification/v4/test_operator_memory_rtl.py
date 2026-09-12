"""Shared live operator ownership, support construction and diagonal reads in Vivado."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from models.v4.lfsr_operator import indexed_sign
from models.v4.operand_read import plan
from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources

ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
class OperatorMemoryRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(prefix='operator_memory_',dir=ROOT/'work')
        cls.path=Path(cls.temporary.name);cls.binary=cls.path/'operator.xsim.json'
        cls.compiled=compile_rtl(cls.binary,'tb_operator_memory',filelist_sources(ROOT)+
            [ROOT/'rtl/v4/memory/operator_memory.sv',ROOT/'verification/v4/memory/tb_operator_memory.sv'],root=ROOT,timeout=300)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    @classmethod
    def tearDownClass(cls):cls.temporary.cleanup()

    def case(self,rows=33,cols=127,count=17,seed=0x12345678,scale=32768,scenario=0):
        trace=self.path/f'case{len(RUNS)}.txt'
        params=dict(rows=rows,cols=cols,count=count,seed=seed,scale=scale,scenario=scenario)
        run=run_rtl(self.binary,[f'+{key}={value}' for key,value in params.items()]+['+trace='+trace.as_posix()],root=ROOT,timeout=300)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr);self.assertIn('PASS clocks=',run.stdout)
        comparisons=0;coordinates=set();builds=[];cycles=reads=0
        for line in trace.read_text().splitlines():
            fields=line.split()
            if fields[0]=='B':builds.append(tuple(map(int,fields[1:])))
            elif fields[0]=='END':cycles,reads=map(int,fields[1:])
            else:
                mode,trans,out,red,step=map(int,fields[1:6]);mask,address,data=map(lambda x:int(x,16),fields[6:])
                expected=plan(dict(mode=mode,trans=trans,rows=rows,cols=count,out_idx=out,red_idx=red,step=step,vec_base=0))
                self.assertEqual((mask,address),(expected['mat_mask'],expected['mat_addr']));comparisons+=2
                for bank in range(32):
                    value=data>>(18*bank)&((1<<18)-1);value=value-(1<<18) if value&(1<<17) else value
                    if not (mask>>bank&1):self.assertEqual(value,0);comparisons+=1;continue
                    a=address>>(9*bank)&511;row,group=divmod(a,(count+31)//32);col=group*32+(bank-row)%32
                    self.assertTrue(row<rows and col<count)
                    golden=row*101-col*53 if scenario==7 else indexed_sign(seed,rows,row,cols-1-col)*scale
                    self.assertEqual(value,golden,(scenario,mode,trans,row,col));comparisons+=1
                    coordinates.add((row,col))
        if scenario in (1,2,3,8,9,10,11):
            self.assertEqual(len(builds),1);self.assertEqual(builds[0][0],2 if scenario in (3,11) else 3)
            self.assertEqual((builds[0][1],builds[0][3],reads),(0,0,0));comparisons+=3
        else:
            self.assertEqual(len(coordinates),rows*count);comparisons+=1
            if scenario!=7:
                self.assertEqual(builds[-1][0],0);self.assertEqual(builds[-1][1],count*((rows+31)//32));comparisons+=2
            if scenario in (4,12):self.assertEqual(builds[0][0],4 if scenario==4 else 3);self.assertEqual(builds[0][3],0);comparisons+=2
        RUNS.append(dict(**params,cycles=cycles,comparisons=comparisons,comparison_kind='independent_coordinate_B_and_operand_plan_bank_checks',
            reads=reads,coordinates_checked=len(coordinates),builds=builds,simulator='Vivado xsim',commands=self.compiled.commands+run.commands,
            returncode=run.returncode,stdout=run.stdout,trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))

    def test_live_builder_both_directions_tails_maximum_and_host_dense(self):
        self.case(rows=1,cols=1,count=1,seed=0,scale=131071)
        self.case()
        self.case(rows=128,cols=1024,count=96)
        self.case(rows=33,cols=127,count=35,scenario=7)
    def test_identity_support_and_stale_response_faults(self):
        for scenario in (1,2,3,4,8,9,10,11,12):
            with self.subTest(scenario=scenario):self.case(scenario=scenario)
    def test_reset_cancel_flush_owned_read_and_reload(self):
        self.case(scenario=5);self.case(scenario=6)

if __name__=='__main__':unittest.main()
