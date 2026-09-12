"""Real loaded generic programs, live Phi/B, shared scalar/PE pool and result commit."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from verification.v4.recovery_cycle_profile import cycle_profile
from compiler.v4 import recovery_program as asm
from models.v4.lfsr_operator import lfsr32_matrix
from scripts.v4.xsim import compile_rtl,run_rtl

ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
SOURCES=['rtl/v4/control/recovery_engine.sv','rtl/v4/control/program_sequencer.sv',
 'rtl/v4/memory/result_store.sv','rtl/v4/services/arithmetic_service.sv',
 'rtl/v4/compute/stream_kernel.sv','rtl/v4/dataflow/support_service.sv',
 'rtl/v4/dataflow/factor_service.sv','rtl/v4/dataflow/factor_panel_service.sv','rtl/v4/memory/factor_store.sv',
 'rtl/v4/compute/stream_fabric.sv','rtl/v4/compute/stream_array.sv','rtl/v4/compute/stream_pe.sv',
 'rtl/v4/memory/stream_vector_store.sv','rtl/v4/dataflow/operator_frame_feeder.sv','rtl/v4/dataflow/range_reader.sv',
 'rtl/v4/memory/live_operator_memory.sv','rtl/v4/memory/paired_support_store.sv',
 'rtl/v4/operator/phi_sign_generator.sv','rtl/v4/memory/phi_sign_cache.sv',
 'rtl/v4/dataflow/phi_reader.sv','rtl/v4/dataflow/support_builder.sv',
 'verification/v4/stream/tb_recovery_engine.sv']
SOURCE_EXTRAS=['config/v4_kernel_interface.json','config/v4_program_interface.json',
 'rtl/v4/include/kernel_interface.vh','rtl/v4/include/program_interface.vh',
 'docs/v4/architecture/FACTOR_PANEL.md','verification/v4/test_recovery_engine_rtl.py']


def pack(values,bits=27):
    return sum((int(v)&((1<<bits)-1))<<(bits*i) for i,v in enumerate(values))


def rounded(value,shift):
    value=int(value)
    return (-1 if value<0 else 1)*((abs(value)+(1<<(shift-1)))>>shift) if shift else value


def base_package(n,status=0,support_count=0,output_base=0):
    a=asm.Assembler()
    a.vector('x',n,output_base);a.vector('r',n,32);a.vector('support',min(n,96),96)
    a.template('move','MOV',src_b='A')
    if support_count:a.emit('SET',dst_s=29,immediate=support_count)
    a.emit('HALT_STATUS',dst_v=0,a_v=1,b_v=2,immediate=status)
    return a.finish()


def live_package(rows,n,count,mode,status=1):
    a=asm.Assembler()
    x=a.vector('x',n,0);v=a.vector('v',n,32);s1=a.vector('support1',count,96)
    s2=a.vector('support2',count,100);y=a.vector('y',rows,128);c=a.vector('c',count,160)
    matrix=a.template('matrix','MAC',output='LAST_ACC',mode=0)
    identity=a.template('identity','MUL',bind_b=(1<<32)-1)
    a.templates[-1]['descriptor']=5
    move=a.template('stored','MOV',src_b='A')
    def kernel(op,source,destination,length,**imm):
        a.emit('KERNEL',kernel=op,a_v=source,b_v=source,dst_v=destination,length_mode=2,
               b_s=4,immediate=asm.service_immediate(length=length,**imm))
    a.emit('SET',dst_s=1,immediate=1<<44)
    a.emit('SQRT',dst_s=2,a_s=1)
    a.emit('SET',dst_s=3,immediate=1<<22)
    a.emit('DIV',dst_s=4,a_s=2,b_s=3,immediate=0)
    a.branch('BR_COMPARE','scalar_ok',a_s=4,b_s=3,immediate=0)
    a.emit('FAIL',immediate=8)
    a.label('scalar_ok')
    a.emit('SET',dst_s=5,immediate=count)
    kernel(1,v,y,n,template=matrix)
    a.emit('BUILD_B',a_v=s1,a_s=5)
    kernel(1,y,c,rows,template=matrix,dense=1,transpose=1,r4=1,support_length_s=5)
    kernel(1,c,y,count,template=matrix,dense=1,support_length_s=5)
    a.emit('BUILD_B',a_v=s2,a_s=5)
    kernel(1,y,c,rows,template=matrix,dense=1,transpose=1,r4=1,support_length_s=5)
    kernel(8,c,x,n,template=move,support_v=s2,support_length_s=5)
    kernel(0,x,x,n,template=identity)
    kernel(3,x,x,n,template=move,store_mode=mode)
    a.emit('SET',dst_s=25,immediate=2);a.emit('SET',dst_s=26,immediate=3)
    a.emit('SET',dst_s=29,immediate=count)
    a.emit('HALT_STATUS',dst_v=x,a_v=y,b_v=s2,immediate=status)
    return a.finish()


class RecoveryEngineRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path=Path(tempfile.mkdtemp(prefix='recovery_engine_',dir=ROOT/'work'))
        cls.binary=cls.path/'recovery.xsim.json'
        cls.compiled=compile_rtl(cls.binary,'tb_recovery_engine',[ROOT/p for p in SOURCES],root=ROOT,timeout=300)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)

    @classmethod
    def tearDownClass(cls):
        (cls.path/'evidence.json').write_text(json.dumps(RUNS,indent=2))

    def case(self,rows=7,n=35,count=3,mode=1,scenario=0,kind='live',status=1):
        baseline=[7<<8]*n
        base=base_package(n)
        target=live_package(rows,n,count,mode,status)
        first=list(range(count));second=list(range(n-1,n-count-1,-1))
        values=[256]+[0]*(n-1)
        memory={32:values,96:first,100:second}
        phi=lfsr32_matrix(0x12345678,rows,n,scale=32768).astype(int)
        def gemv(matrix,vector):return [rounded(sum(int(v)*int(c) for v,c in zip(vector,row)),16) for row in matrix]
        y=gemv(phi,values)
        compact=gemv(phi[:,first].T,y)
        y=gemv(phi[:,first],compact)
        compact=gemv(phi[:,second].T,y)
        expected=[0]*n
        for index,value in zip(second,compact):expected[index]=rounded(value,2 if mode==1 else 8)<<(2 if mode==1 else 8)
        expected_fault=0;expected_status=status;active=1;exponent=-3
        if kind=='embedding':
            target=base_package(n,status);memory={0:[1]*n};expected_fault=5;active=0
        elif kind=='status':
            target=base_package(n,status);memory={0:[256]*n};expected_fault=2;active=0
        elif kind=='missing':
            target=base_package(n,status,output_base=256);memory={};expected_fault=4;active=0
        elif kind=='support':
            target=base_package(n,status,support_count=2);memory={0:[256]*n,96:[1,1]};expected_fault=4
        elif kind=='build_bad':
            memory[96]=[0]*count;expected_fault=3;expected_status=0
        if scenario==11:expected_fault=1;expected_status=0
        if scenario==12:expected_fault=7;expected_status=0
        if scenario in (1,2,3) or expected_fault:expected=baseline
        fixture=self.path/f'case{len(RUNS)}.txt';trace=self.path/f'trace{len(RUNS)}.txt'
        lines=[f'{rows} {n} 2']
        packages=[base,target]
        for job,(pkg,data) in enumerate([(base,{0:baseline}),(target,memory)]):
            lines.append(f'{mode} {0 if job==0 else exponent} {0 if job==0 else active} {0 if job==0 else scenario} {0 if job==0 else expected_fault} {0 if job==0 else expected_status}')
            records=asm.load_records(pkg)
            lines.append(f"{len(pkg['program'])} {len(pkg['templates'])} {len(pkg['vectors'])} {len(pkg['constants'])} {len(records)}")
            lines.extend(f'{k:x} {i:04x} {w:032x} {last:x}' for k,i,w,last in records)
            writes=[]
            for base_address,vector in data.items():
                for start in range(0,len(vector),32):
                    chunk=vector[start:start+32]
                    writes.append(f'{base_address+start//32} {(1<<len(chunk))-1:08x} {pack(chunk):0216x}')
            lines.append(str(len(writes)));lines.extend(writes)
        fixture.write_text('\n'.join(lines)+'\n')
        result=run_rtl(self.binary,['+fixture='+fixture.as_posix(),'+trace='+trace.as_posix()],root=ROOT,timeout=600)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS cycles=',result.stdout)
        checks=0;got=[[],[]];builds=[];scalar=[];completion=[];job_cycles=[];metadata=[]
        for line in trace.read_text().splitlines():
            fields=line.split()
            if fields[0]=='X':
                job,index,raw,fault,stored,exp,tag=int(fields[1]),int(fields[2]),int(fields[3],16),*map(int,fields[4:])
                value=raw-(1<<27) if raw&(1<<26) else raw
                got[job].append(value)
                old=job==0 or (scenario in (1,2,3) or expected_fault)
                self.assertEqual((fault,stored,exp,tag),(0,mode,0 if old else exponent,100 if old else 101));checks+=4
            elif fields[0]=='B':builds.append((int(fields[2]),int(fields[3]),int(fields[4],16)))
            elif fields[0]=='S':scalar.append((int(fields[2],16),int(fields[3])))
            elif fields[0]=='D':
                completion.append(tuple(map(int,fields[1:])))
                job_cycles.append(int(fields[-1]))
            elif fields[0]=='M':metadata.append(fields)
            elif fields[0]=='END':cycles,tbchecks,build_count,kernel_count,scalar_count=map(int,fields[1:]);checks+=tbchecks
        self.assertEqual(got,[baseline,expected]);checks+=2*n
        if not expected_fault and scenario not in (1,2,3):
            self.assertEqual(builds,[(count,1,pack(first,10)),(count,2,pack(second,10))]);checks+=2
            self.assertEqual(scalar,[(1<<22,0),(1<<22,0)]);checks+=2
            self.assertEqual(int(metadata[-1][7]),count)
            self.assertEqual(int(metadata[-1][8],16),pack(second,10));checks+=2
        RUNS.append(dict(rows=rows,columns=n,count=count,mode=mode,scenario=scenario,kind=kind,
            cycles=cycles,job_cycles=job_cycles,comparisons=checks,builds=build_count,kernels=kernel_count,scalars=scalar_count,
            cycle_profile=cycle_profile(trace.read_text()),
            comparison_kind='independent_integer_live_Phi_B_products_and_exact_committed_result',
            scope='loaded_generic_services_no_QR_or_full_algorithm_claim',simulator='Vivado xsim',
            commands=self.compiled.commands+result.commands,returncode=result.returncode,stdout=result.stdout,
            fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(),
            packages=[{'program_sha256':hashlib.sha256(''.join(f'{w:032x}\n' for w in p['program']).encode()).hexdigest(),'words':len(p['program'])} for p in packages]))

    def test_live_phi_two_builds_scalar_branches_alias_and_publication(self):
        self.case()
        self.case(rows=1,n=1,count=1,mode=2,status=5)
        self.case(rows=128,n=1024,count=96)

    def test_faults_preserve_committed_and_held_read(self):
        for kind in ('embedding','status','missing','support','build_bad'):
            self.case(kind=kind,status=8 if kind=='status' else 1,scenario=9 if kind=='embedding' else 0)
        self.case(scenario=11)
        self.case(scenario=12)

    def test_cancel_build_compute_drain_and_published_completion(self):
        for scenario in (1,2,3,4):self.case(scenario=scenario)


if __name__=='__main__':unittest.main()
