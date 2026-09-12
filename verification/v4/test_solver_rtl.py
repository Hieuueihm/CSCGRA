"""Generic service sequencer executes compiler LSQR with real scalar RTL and golden kernels."""
import hashlib
import json
import math
from pathlib import Path
import re
import tempfile
import unittest
import numpy as np
from compiler.v4.solver_program import ROOT,encode,decode,lsqr_program
from scripts.v4.generate_solver_interface import render
from scripts.v4.xsim import compile_rtl,run_rtl
from models.v4.fixed import Format,Profile
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.recovery import Policy
RUNS=[];IMAGES=[]

def round_shift(value,shift):
    result=(abs(value)+(1<<(shift-1)))>>shift if shift else abs(value)
    return -result if value<0 else result
def checked(value,width=27):
    if not -(1<<(width-1))<=value<(1<<(width-1)):raise ArithmeticError('numeric')
    return value
def energy(values):
    total=0
    for value in values:total=checked(total+value*value,64)
    return total

def interpret(words,matrix,y,budget=32,limit=10000):
    """Integer list kernel oracle, independent of PE scheduling/RTL control state."""
    rows=len(y);cols=len(matrix[0]);vectors={0:list(y)};rf=[0]*32;rf[30]=budget
    pc=0;trace=[];retired=0;fault=0
    while retired<limit:
        f=decode(words[pc]);kind=f['kind'];a=rf[f['a_s']];b=rf[f['b_s']];nextpc=pc+1
        if kind==1:
            op=f['kernel'];length=rows if f['length_mode']==0 else cols if f['length_mode']==1 else (f['immediate']>>8)&255
            trans=f['immediate']&1;shift=rf[f['shift_s']];dest=f['dst_v'];srca=f['a_v'];srcb=f['b_v'];data=0
            if op==0:result=[0]*length
            elif op==1:result=list(vectors[srca])
            elif op in (2,3):result=[checked(x+y if op==2 else x-y) for x,y in zip(vectors[srca],vectors[srcb])]
            elif op in (4,5):result=[checked(round_shift(x*a,22 if op==4 else shift)) for x in vectors[srca]]
            elif op==6:
                operator=list(zip(*matrix)) if trans else matrix
                result=[]
                for row in operator:
                    total=0
                    for coefficient,value in zip(row,vectors[srca]):total=checked(total+coefficient*value,64)
                    result.append(checked(round_shift(total,16)))
            elif op==7:data=energy(vectors[srca]);result=None
            elif op==8:result=[checked(round_shift(x,2),24)*4 for x in vectors[srca]]
            elif op==9:data=checked(round_shift(a*b,22));result=None
            elif op==10:data=energy([a,b]);result=None
            else:raise AssertionError(op)
            flag=int(any(result)) if result is not None else int(data!=0)
            trace.append([op,srca,srcb,dest,length,trans,a&((1<<27)-1),b&((1<<27)-1),shift&63,data&((1<<64)-1),flag])
            if result is not None:vectors[dest]=result
            else:rf[f['dst_s']]=data
            if f['flag_s']:rf[f['flag_s']]=flag
        elif kind==2:
            if b==0:raise ArithmeticError('zero')
            result=(2*(abs(a)<<22)+abs(b))//(2*abs(b));rf[f['dst_s']]=checked(-result if (a<0)!=(b<0) else result)
        elif kind==3:
            result=math.isqrt(a);rf[f['dst_s']]=checked(result+int(4*a>=(2*result+1)**2))
        elif kind==4:rf[f['dst_s']]=f['immediate']-(1<<64) if f['immediate']&(1<<63) else f['immediate']
        elif kind==5:rf[f['dst_s']]=a
        elif kind==6:rf[f['dst_s']]=checked(-a)
        elif kind==7:rf[f['dst_s']]=1<<a.bit_length();rf[f['shift_s']]=a.bit_length()
        elif kind==8:nextpc=f['target'] if a==0 else nextpc
        elif kind==9:nextpc=f['target'] if a!=0 else nextpc
        elif kind==10:nextpc=f['target']
        elif kind==11:rf[f['dst_s']]=int(a*10000000000<=b)
        elif kind==12:rf[f['dst_s']]=a+1
        elif kind==13:nextpc=f['target'] if a>=b else nextpc
        elif kind in (14,15):fault=0 if kind==14 else 10;break
        elif kind!=0:raise AssertionError(kind)
        pc=nextpc;retired+=1
    else:fault=8
    return dict(trace=trace,x=vectors.get(10),fault=fault,iterations=rf[25],normal=rf[21],rhs=rf[19])

class SolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT/'work').mkdir(exist_ok=True);cls.temporary=tempfile.TemporaryDirectory(prefix='solver_',dir=ROOT/'work')
        cls.folder=Path(cls.temporary.name);cls.image=cls.folder/'solver.xsim.json'
        cls.compiled=compile_rtl(cls.image,'tb_solver_sequencer',[
            ROOT/'rtl/v4/control/solver_sequencer.sv',ROOT/'rtl/v4/services/scalar_service.sv',
            ROOT/'verification/v4/solver/tb_solver_sequencer.sv'],root=ROOT)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
    @classmethod
    def tearDownClass(cls):cls.temporary.cleanup()
    def simulate(self,words,oracle=None,rows=4,cols=2,budget=32,**options):
        program=self.folder/'program.hex';kernels=self.folder/'kernels.txt'
        program.write_text('\n'.join(f'{word:032x}' for word in words)+'\n')
        trace=[] if oracle is None else oracle['trace']
        kernels.write_text(''.join(' '.join(f'{v:x}' if i in (6,7,9) else str(v) for i,v in enumerate(row))+'\n' for row in trace))
        args=['+program='+program.as_posix(),'+kernels='+kernels.as_posix(),f'+rows={rows}',f'+cols={cols}',f'+budget={budget}']
        args += [f'+{key}={value}' for key,value in options.items()]
        result=run_rtl(self.image,args,root=ROOT)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS cycles=',result.stdout)
        match=re.search(r'DONE fault=(\d+) iterations=(\d+) normal=(\d+) rhs=(\d+) job=(\d+) tag=(\d+) fmt=(\d+)',result.stdout)
        if not options.get('abort'):
            self.assertIsNotNone(match,result.stdout);self.assertEqual(tuple(map(int,match.groups()[4:])),(12,123,1))
            self.last_candidate_slot=int(re.search(r'fmt=\d+ slot=(\d+)',result.stdout)[1])
        RUNS.append(dict(test=self.id(),cycles=int(re.search(r'PASS cycles=(\d+)',result.stdout)[1]),
            comparisons=len(trace),comparison_kind='golden kernel request checks',
            program_sha256=hashlib.sha256(program.read_bytes()).hexdigest(),kernel_trace_sha256=hashlib.sha256(kernels.read_bytes()).hexdigest(),
            commands=self.compiled.commands+result.commands))
        return tuple(map(int,match.groups()[:4])) if match else None
    def test_generated_program_matches_integer_lsqr_and_executes(self):
        self.assertEqual((ROOT/'rtl/v4/include/solver_interface.vh').read_text(),render())
        words,labels=lsqr_program();self.assertEqual(len(words),256)
        IMAGES.append(dict(name='lsqr_service_candidate',labels=labels,words_sha256=hashlib.sha256(b''.join(w.to_bytes(16,'little') for w in words)).hexdigest()))
        profile=Profile(Format(18,14),Format(18,16),Format(27,22),64)
        cases=[(np.eye(4)[:,:2],np.array([.25,-.375,0,0]),32),
               (np.array([[.5,.25],[.25,-.5],[.5,0],[0,.5]]),np.array([.1875,.25,.25,-.125]),32),
               (np.array([[.5,.25],[.25,.5],[.125,.375],[.25,-.25]]),np.array([.25,-.375,.125,.0625]),1),
               (np.eye(4)[:,:2],np.zeros(4),32)]
        for matrix,y,budget in cases:
            backend=IntegerLSQRKernels(matrix,y,Policy(sparsity=matrix.shape[1],ls_max_iterations=budget,ls_normal_rtol=1e-5),profile,solution_format=Format(24,20))
            try:backend.least_squares(list(range(matrix.shape[1])))
            except ArithmeticError:pass
            expected=interpret(words,[[int(v) for v in row] for row in backend.a],[int(v) for v in backend.y],budget)
            self.assertFalse(any(backend.events.values()))
            self.assertEqual(expected['x'],[int(v) for v in backend.last_candidate])
            self.assertEqual(expected['iterations'],backend.last_ls_report['steps'])
            cert=backend.last_ls_report['certificate_history'][-1]
            self.assertEqual((expected['normal'],expected['rhs']),(cert['normal_energy_raw'],cert['rhs_energy_raw']))
            got=self.simulate(words,expected,rows=len(y),cols=matrix.shape[1],budget=budget)
            self.assertEqual(got,(expected['fault'],expected['iterations'],expected['normal'],expected['rhs']))
            if expected['fault']==0:self.assertEqual(self.last_candidate_slot,10)
    def test_malformed_watchdog_certificate_and_response_faults(self):
        def program(*head):return list(head)+[encode('FAIL')]*(256-len(head))
        for words,options,fault in [
            (program(encode('SUCCESS')),{},9),(program(encode('SET',dst_s=0)),{},3),
            (program(encode('SET',dst_s=30)),{},3),(program(encode('NOP',reserved=1)),{},3),
            (program(encode('JUMP',target=0)),{'watchdog':3},8),
            (program(encode('CERT',dst_s=22,a_s=21,b_s=19)),{},9),
            (program(encode('FAIL')),{'loadmode':1},1),(program(encode('FAIL')),{'loadmode':2},1),
            (program(encode('FAIL')),{'loadmode':3},1),(program(encode('FAIL')),{'loadmode':4},1),
            (program(encode('FAIL')),{'rows':0},2),(program(encode('FAIL')),{'budget':0},2),
            (program(encode('SET',dst_s=1,immediate=(1<<64)-1),encode('SQRT',dst_s=2,a_s=1)),{},7)]:
            with self.subTest(fault=fault,options=options):self.assertEqual(self.simulate(words,**options)[0],fault)
        words,_=lsqr_program();oracle=interpret(words,[[65536,0],[0,65536],[0,0],[0,0]],[1048576,524288,0,0])
        for inject,fault in ((1,5),(2,6),(3,5),(4,4)):
            self.assertEqual(self.simulate(words,oracle,inject=inject)[0],fault)
        for delay in (1,20,80):self.simulate(words,oracle,abort=delay)
        # The certificate follows the actual narrowed destination, not algorithm slot10.
        alternate=[]
        for word in words:
            fields=decode(word);kind=fields.pop('kind')
            if kind==1 and fields['kernel']==8:fields['dst_v']=14
            if kind==1 and fields['kernel']==6 and fields['a_v']==10:fields['a_v']=14
            alternate.append(encode(kind,**fields))
        alternate_oracle=interpret(alternate,[[65536,0],[0,65536],[0,0],[0,0]],[0,0,0,0])
        self.assertEqual(self.simulate(alternate,alternate_oracle)[0],0)
        self.assertEqual(self.last_candidate_slot,14)
        stale,labels=lsqr_program();stale[labels['success']]=encode('SET',dst_s=24,immediate=1)
        stale[labels['success']+1]=encode('SUCCESS')
        stale_oracle=interpret(stale,[[65536,0],[0,65536],[0,0],[0,0]],[0,0,0,0])
        self.assertEqual(self.simulate(stale,stale_oracle)[0],9)
if __name__=='__main__':unittest.main()
