"""Autonomous RTL LSQR against the existing integer LSQR numerical model."""
import hashlib
from pathlib import Path
import tempfile
import unittest
import numpy as np
from compiler.v4.solver_program import lsqr_program,decode,encode,KINDS,KERNELS
from models.v4.fixed import Format,Profile
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.recovery import Policy
from models.v4.lfsr_operator import indexed_sign
from scripts.v4.xsim import compile_rtl,run_rtl,filelist_sources

ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
EXTRA=['rtl/v4/memory/operator_memory.sv','rtl/v4/dataflow/measurement_loader.sv','rtl/v4/memory/vector_workspace.sv',
       'rtl/v4/compute/kernel_fabric.sv','rtl/v4/compute/kernel_engine.sv','rtl/v4/control/solver_sequencer.sv',
       'rtl/v4/dataflow/result_writeback.sv','rtl/v4/control/commit_controller.sv','rtl/v4/control/lsqr_engine.sv']
def pack(values,width):return sum((int(v)&((1<<width)-1))<<(i*width) for i,v in enumerate(values))
def oracle(b,y,maxiter):
    backend=IntegerLSQRKernels(np.asarray(b,dtype=float)/65536,np.asarray(y,dtype=float)/16384,
        Policy(len(b[0]),ls_max_iterations=maxiter,ls_normal_rtol=1e-5),
        Profile(Format(18,14),Format(18,16),Format(27,22),64),solution_format=Format(24,20))
    try:result=[int(v)//4 for v in backend.least_squares(list(range(len(b[0]))))]
    except ArithmeticError:result=None
    return result,backend.last_ls_report

class LsqrRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(prefix='lsqr_rtl_',dir=ROOT/'work')
        cls.path=Path(cls.temporary.name);cls.binary=cls.path/'lsqr.xsim.json'
        cls.compiled=compile_rtl(cls.binary,'tb_lsqr_engine',list(dict.fromkeys(filelist_sources(ROOT)+
            [ROOT/n for n in EXTRA]+[ROOT/'verification/v4/solver/tb_lsqr_engine.sv'])),root=ROOT,timeout=300)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    @classmethod
    def tearDownClass(cls):cls.temporary.cleanup()

    def case(self,rows=33,count=5,columns=None,generated=1,kind='normal',maxiter=32,exponent=0,abort=0,header=0,relocate=False):
        columns=count if columns is None else columns;seed=0x12345678;scale=8192
        support=list(reversed(range(columns-count,columns)))
        b=[[indexed_sign(seed,rows,row,support[col])*scale for col in range(count)]for row in range(rows)]
        if not generated:
            b=[[65536 if row==col else 0 for col in range(count)]for row in range(rows)]
            if kind=='overflow':b=[[1]]
            if kind=='round':b=[[19661]]
        y=[8192 if row==0 else -4096 if row==1 else (row*73)%2048-1024 for row in range(rows)]
        if kind=='zero':y=[0]*rows
        if kind=='bad_y':y[0]=8193
        if kind=='range':y=[8192 if row[0]>0 else -8192 for row in b]
        expected,report=oracle(b,y,maxiter)
        path=self.path/f'case{len(RUNS)}';path.mkdir();words,labels=lsqr_program()
        if relocate:
            for pc,word in enumerate(words):
                f=decode(word)
                if f['kind']==KINDS['KERNEL']:
                    if f['kernel']==KERNELS['NARROW_X']:f['dst_v']=14
                    elif f['kernel']==KERNELS['GEMV_B'] and f['a_v']==10:f['a_v']=14
                words[pc]=encode(**f)
        (path/'program.hex').write_text(''.join(f'{word:032x}\n' for word in words))
        (path/'support.hex').write_text(f'{pack(support,10):0240x}\n')
        lines=[]
        for block in range((rows+31)//32):
            values=y[block*32:block*32+32]
            lines.append(f'{block:x} {(1<<len(values))-1:08x} {pack(values,18):0144x} {int((block+1)*32>=rows)}\n')
        (path/'y.txt').write_text(''.join(lines));lines=[]
        for slot in range(count):
            for block in range((rows+31)//32):
                values=[b[row][slot] for row in range(block*32,min(rows,(block+1)*32))]
                lines.append(f'{slot:x} {block:x} {(1<<len(values))-1:08x} {pack(values,18):0144x} {int(slot==count-1 and (block+1)*32>=rows)}\n')
        (path/'b.txt').write_text(''.join(lines))
        params=dict(rows=rows,columns=columns,count=count,generated=generated,seed=seed,scale=scale,maxiter=maxiter,exponent=exponent,abort=abort,header=header)
        args=[f'+{k}={v}'for k,v in params.items()]+[f'+{k}={(path/n).as_posix()}'for k,n in [('program','program.hex'),('support','support.hex'),('y','y.txt'),('b','b.txt'),('trace','trace.txt')]]
        run=run_rtl(self.binary,args,root=ROOT,timeout=3600)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr);self.assertIn('PASS clocks=',run.stdout)
        done={};results={};cycles=0;comparisons=0
        for line in (path/'trace.txt').read_text().splitlines():
            p=line.split()
            if p[0]=='D':done[int(p[1])]=[int(v,16 if i in (4,5) else 10)for i,v in enumerate(p[2:])]
            elif p[0]=='X':
                run_id,slot=int(p[1]),int(p[2]);value=int(p[3],16);value-=1<<24 if value&(1<<23) else 0
                results.setdefault(run_id,[]).append((slot,value,*map(int,p[4:])))
            else:cycles=int(p[1])
        self.assertEqual(done[0][:4],[0,0,1,1]);self.assertEqual(results[0],[(0,524288,0,0,7,123)]);comparisons+=2
        final_runs=(1,2) if abort else (1,)
        for run_id in final_runs:
            fault,detail,committed,iterations,normal,rhs,run_cycles,retired=done[run_id]
            if abort in (1,2,3) and run_id==1:
                self.assertEqual((fault,committed),(8,0));self.assertEqual(results[run_id],results[0]);comparisons+=2;continue
            if header or kind=='bad_y':
                self.assertEqual((fault,committed),(1 if header else 2,0));self.assertEqual(results[run_id],results[0]);comparisons+=2
                continue
            if expected is None:
                self.assertEqual(fault,5);self.assertEqual(committed,0);self.assertEqual(results[run_id],results[0]);comparisons+=3
                if report['status']=='ls_not_converged':self.assertEqual(detail,10);comparisons+=1
                elif report['status']=='numeric_fault':self.assertEqual(detail,7);comparisons+=1
            else:
                self.assertEqual((fault,detail,committed),(0,0,1),done)
                self.assertEqual(results[run_id],[(slot,value,support[slot],exponent,7,123+run_id)for slot,value in enumerate(expected)])
                certificate=report['certificate_history'][-1]
                self.assertEqual((iterations,normal,rhs),(report['steps'],certificate['normal_energy_raw'],certificate['rhs_energy_raw']))
                # Exponent is host normalization metadata; unscale the stored X externally.
                decoded=np.ldexp(np.array([row[1] for row in results[run_id]],dtype=float)/2**20,-exponent)
                np.testing.assert_array_equal(decoded,np.ldexp(np.asarray(expected,dtype=float)/2**20,-exponent))
                comparisons+=count+4
        RUNS.append(dict(**params,kind=kind,relocated_candidate=relocate,cycles=cycles,comparisons=comparisons,comparison_kind='existing_IntegerLSQRKernels_exact_X_and_certificate',
            oracle_report=report,results=results,done=done,program_labels=labels,program_sha256=hashlib.sha256((path/'program.hex').read_bytes()).hexdigest(),
            simulator='Vivado xsim',commands=self.compiled.commands+run.commands,returncode=run.returncode,stdout=run.stdout,
            trace_sha256=hashlib.sha256((path/'trace.txt').read_bytes()).hexdigest()))

    def test_dense_analytic_rounding_and_zero(self):
        self.case(rows=5,count=3,generated=0,exponent=3)
        self.case(rows=1,count=1,generated=0,kind='round',exponent=-2)
        self.case(rows=7,count=3,generated=0,kind='zero')
        self.case(rows=5,count=3,generated=0,relocate=True)
    def test_live_phi_multiple_iterations_and_maximum_support(self):
        self.case()
        self.case(rows=128,count=96,columns=1024,kind='zero',maxiter=128)
        self.case(rows=128,count=96,columns=1024,kind='range',maxiter=128)
    def test_nonconvergence_overflow_preserve_committed(self):
        self.case(rows=7,count=3,maxiter=1)
        self.case(rows=1,count=1,generated=0,kind='overflow')
    def test_native_measurement_peak_and_start_header_rejection(self):
        self.case(rows=5,count=3,generated=0,kind='bad_y')
        for header in (1,2,3,4,5,6):self.case(rows=5,count=3,generated=0,header=header)
    def test_cancel_build_solve_and_candidate_drain_then_reload(self):
        for phase in (1,2,3,4):self.case(rows=7,count=3,abort=phase)

if __name__=='__main__':unittest.main()
