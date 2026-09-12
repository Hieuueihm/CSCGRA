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
class LiveOperatorMemoryRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path=Path(tempfile.mkdtemp(prefix='live_operator_',dir=ROOT/'work'));cls.binary=cls.path/'operator.xsim.json'
        cls.compiled=compile_rtl(cls.binary,'tb_live_operator_memory',[ROOT/p for p in ['rtl/v4/operator/phi_sign_generator.sv','rtl/v4/memory/phi_sign_cache.sv','rtl/v4/dataflow/phi_reader.sv','rtl/v4/dataflow/support_builder.sv','rtl/v4/dataflow/operand_plan.sv']]+
            [ROOT/p for p in ['rtl/v4/memory/live_operator_memory.sv','rtl/v4/memory/paired_support_store.sv','rtl/v4/dataflow/operator_frame_feeder.sv','rtl/v4/memory/stream_vector_store.sv','verification/v4/memory/tb_live_operator_memory.sv']],root=ROOT,timeout=300)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    @classmethod
    def tearDownClass(cls):
        (cls.path/'evidence.json').write_text(json.dumps(RUNS,indent=2))

    def case(self,rows=33,cols=127,count=17,seed=0x12345678,scale=32768,scenario=0,feed=0):
        trace=self.path/f'case{len(RUNS)}.txt'
        params=dict(rows=rows,cols=cols,count=count,seed=seed,scale=scale,scenario=scenario,feed=feed)
        run=run_rtl(self.binary,[f'+{key}={value}' for key,value in params.items()]+['+trace='+trace.as_posix()],root=ROOT,timeout=300)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr);self.assertIn('PASS clocks=',run.stdout)
        comparisons=0;coordinates=set();builds=[];cycles=reads=0;frames=0;cadence={}
        from models.v4.lfsr_operator import lfsr32_matrix
        phi=lfsr32_matrix(seed,rows,cols,scale=scale).astype(int)
        for line in trace.read_text().splitlines():
            fields=line.split()
            if fields[0]=='NEG':
                self.assertGreaterEqual(int(fields[1]),8);comparisons+=int(fields[1]);continue
            if fields[0]=='F':
                dense,rfour,trans,out,red,step=map(int,fields[1:7]);mask,mat,vec=[int(x,16) for x in fields[7:10]]
                latency,passes=map(int,fields[10:]);frames+=1
                cadence.setdefault(f'{dense}/{rfour}/{trans}',[]).append(latency)
                outputs=(count if dense else cols) if trans else rows
                reductions=rows if trans else (count if dense else cols)
                expected_mask=0;active_passes=set()
                for lane in range(32):
                    oo=out+(lane//4 if rfour else lane);rr=red+(8*(lane%4)+step if rfour else 0)
                    active=oo<outputs and rr<reductions
                    row,col=(rr,oo) if trans else (oo,rr)
                    golden=(row*101-col*53 if dense and scenario==7 else int(phi[row,cols-1-col if dense else col])) if active else 0
                    vector=rr*17-123 if active else 0
                    value=(mat>>(lane*27))&((1<<27)-1);value=value-(1<<27) if value&(1<<26) else value
                    raw=(vec>>(lane*27))&((1<<27)-1);raw=raw-(1<<27) if raw&(1<<26) else raw
                    self.assertEqual((value,raw),(golden,vector),(dense,rfour,trans,out,red,step,lane));comparisons+=2
                    expected_mask|=int(active)<<lane
                    if active:active_passes.add((lane%4 if rfour else lane//8) if not dense and rfour!=trans else 0)
                self.assertEqual(mask,expected_mask)
                # The focused tile-cache gate records endpoint passes.  A raw
                # tile hit has no endpoint grant, while a miss retains the
                # original pass count; payload is checked above either way.
                if feed>=1:self.assertIn(passes,(0,len(active_passes)))
                else:self.assertEqual(passes,len(active_passes))
                comparisons+=2
                continue
            if fields[0]=='TILE':
                self.assertEqual(tuple(map(int,fields[1:])),(1,1));comparisons+=2
            elif fields[0]=='MARK':
                comparisons+=1
            elif fields[0]=='BOUNDARY':
                self.assertGreaterEqual(int(fields[1]),1);comparisons+=1
            elif fields[0]=='B':builds.append(tuple(map(int,fields[1:])))
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
        if feed==2:
            self.assertGreaterEqual(frames,16);comparisons+=1
        elif scenario in (1,2,3,8,9,10,11):
            self.assertEqual(len(builds),1);self.assertEqual(builds[0][0],2 if scenario in (3,11) else 3)
            self.assertEqual((builds[0][1],builds[0][3],reads),(0,0,0));comparisons+=3
        else:
            self.assertEqual(len(coordinates),rows*count);comparisons+=1
            if scenario!=7:
                self.assertEqual(builds[-1][0],0);self.assertEqual(builds[-1][1],count*((rows+31)//32));comparisons+=2
            if scenario in (4,12):self.assertEqual(builds[0][0],4 if scenario==4 else 3);self.assertEqual(builds[0][3],0);comparisons+=2
        RUNS.append(dict(**params,cycles=cycles,comparisons=comparisons,comparison_kind='independent_coordinate_B_and_operand_plan_bank_checks',
            frames=frames,cadence={k:dict(min=min(v),max=max(v),frames=len(v)) for k,v in cadence.items()},reads=reads,coordinates_checked=len(coordinates),builds=builds,simulator='Vivado xsim',commands=self.compiled.commands+run.commands,
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

    def test_paired_store_two_credit_pipeline(self):
        binary=self.path/'paired.xsim.json'
        sources=['rtl/v4/memory/paired_support_store.sv','verification/v4/memory/tb_paired_support_store.sv']
        compiled=compile_rtl(binary,'tb_paired_support_store',sources,root=ROOT)
        self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
        run=run_rtl(binary,[],root=ROOT)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        import re
        match=re.search(r'PASS paired_support_store cycles=(\d+) checks=(\d+) reads=(\d+) stalls=(\d+) flushed=(\d+)',run.stdout)
        self.assertIsNotNone(match,run.stdout)
        cycles,checks,reads,stalls,flushed=map(int,match.groups())
        RUNS.append(dict(cycles=cycles,comparisons=checks,comparison_kind='paired_TDP_two_credit_payload_and_metadata',reads=reads,stalls=stalls,flushed=flushed,commands=compiled.commands+run.commands,stdout=run.stdout))

    def test_live_frame_four_modes_full_geometry_and_tails(self):
        self.case(rows=1,cols=1,count=1,feed=1)
        self.case(rows=37,cols=67,count=35,feed=1)
        self.case(rows=128,cols=1024,count=96,feed=1)
        self.case(rows=33,cols=127,count=35,scenario=7,feed=1)

if __name__=='__main__':unittest.main()
