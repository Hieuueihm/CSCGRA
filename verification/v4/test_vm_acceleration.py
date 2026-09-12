"""Independent original-versus-optional oracle equivalence, no RTL execution."""
import copy
import time
import unittest
import numpy as np
from compiler.v4.recovery_emit import PROFILE,compile_recovery
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from models.v4.fixed import Arithmetic,Format,Profile
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import IntegerKernels,Policy,run
from models.v4.proximal import Policy as ProximalPolicy,run as proximal_run
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute
from verification.v4.exact_vm_gemv import BoundedGemv
from verification.v4.exact_model_context import model_acceleration

ALGORITHMS=('MP','GP','IHT','OMP','GOMP','CoSaMP','SP','HTP','FISTA','PDHG','ADMM')
QR=('OMP','GOMP','CoSaMP','SP','HTP')
PROX=('FISTA','PDHG','ADMM')
RECORDS=[]

def plain(x):
    if isinstance(x,np.ndarray):return plain(x.tolist())
    if isinstance(x,dict):return {k:plain(v) for k,v in x.items()}
    if isinstance(x,(list,tuple)):return [plain(v) for v in x]
    if isinstance(x,np.generic):return x.item()
    return x

def inputs(m=16,n=32):
    matrix=lfsr32_matrix(0x12345678,m,n,scale=8192).astype(float)/65536
    truth=np.zeros(n);truth[2]=.25;truth[9]=-.125
    return matrix,matrix@truth

def package(algorithm,matrix):
    p=ProximalPolicy(max_iterations=3,inner_max_iterations=24) if algorithm in PROX else Policy(2,max_iterations=3)
    return (compile_greedy_qr(algorithm,matrix,p,qr_profile='balanced') if algorithm in QR
            else compile_recovery(algorithm,matrix,p,sparse_forward=algorithm in ('MP','GP','IHT'))),p

class VmAccelerationTests(unittest.TestCase):
    def compare_matvec(self,matrix,vector,transpose=False,profile=PROFILE,formats=None,fast_expected=None):
        left,right=Arithmetic(profile),Arithmetic(profile)
        # Existing event state must not be reset by the optional backend.
        left.events['divide_by_zero']=right.events['divide_by_zero']=2
        formats=formats or (profile.coefficient,profile.state,profile.state)
        stats={};backend=BoundedGemv(right,stats)
        def call(fn):
            try:return ('value',plain(fn(matrix,vector,*formats,transpose)))
            except Exception as error:return ('error',type(error).__name__,str(error))
        self.assertEqual(call(left.matvec),call(backend.matvec))
        self.assertEqual(left.events,right.events)
        if fast_expected is not None:self.assertEqual(stats.get('fast_calls',0),int(fast_expected))
        RECORDS.append(dict(kind='matvec',shape=list(np.shape(matrix)),transpose=bool(transpose),stats=stats))

    def test_maximum_shapes_extremes_rounding_and_events(self):
        rng=np.random.default_rng(908271)
        for m,n in ((1,1),(7,9),(33,35),(128,96),(128,1024)):
            a=rng.integers(-(1<<17),1<<17,(m,n),dtype=np.int64)
            for trans in (False,True):
                v=rng.integers(-(1<<26),1<<26,m if trans else n,dtype=np.int64)
                self.compare_matvec(a.astype(object),v.astype(object),trans,fast_expected=True)
                self.compare_matvec(np.full((m,n),-(1<<17),dtype=np.int64),
                                    np.full(len(v),-(1<<26),dtype=np.int64),trans,fast_expected=True)
        # Exact half ties, sign cancellation and S27 saturation boundaries.
        self.compare_matvec([[1],[1],[-1],[-1]],[32768],fast_expected=True)
        self.compare_matvec([[131071,-131072],[131071,-131072]],[-67108864,-67108864],fast_expected=True)

    def test_safe_fallback_preserves_errors_formats_and_large_integers(self):
        cases=[([[1<<80]], [1]), ([[1<<63]], [1]), ([[131072]],[1]),([[-131073]],[1]),
               ([[1]],[1<<26]),([[1]],[-(1<<26)-1]),([[1.0]],[1]),([[True]],[1]),
               ([[1]],[False]),([[1,2]],[1]),([1,2],[1,2]),([[1]],[[1]]),
               (np.zeros((1,0),dtype=np.int64),np.zeros(0,dtype=np.int64)),
               (np.ones((1,1025),dtype=np.int64),np.ones(1025,dtype=np.int64)),
               (np.array([[1<<63]],dtype=np.uint64),np.array([1],dtype=np.uint64))]
        for a,v in cases:self.compare_matvec(a,v,fast_expected=False)
        self.compare_matvec([[1]],[1],formats=(PROFILE.coefficient,PROFILE.state,Format(24,20)),fast_expected=False)
        self.compare_matvec([[131071]],[67108863],profile=Profile(PROFILE.data,PROFILE.coefficient,PROFILE.state,32),fast_expected=False)
        self.compare_matvec([[1]],[1],transpose=1,fast_expected=False)

    def test_all_eleven_complete_programs_default_and_accelerated(self):
        for m,n in ((16,32),(33,35)):
            matrix,y=inputs(m,n)
            for algorithm in ALGORITHMS:
                p,_=package(algorithm,matrix)
                original_start=time.perf_counter()
                original=reference_execute(p,matrix,y,limit=1000000)
                original_seconds=time.perf_counter()-original_start
                self.assertEqual(plain(original),plain(execute(p,matrix,y,limit=1000000)))
                stats={};start=time.perf_counter()
                fast=execute(p,matrix,y,limit=1000000,accelerate_gemv=True,gemv_stats=stats)
                self.assertEqual(plain(original),plain(fast))
                self.assertGreater(stats.get('fast_calls',0),0)
                RECORDS.append(dict(kind='complete_program',algorithm=algorithm,shape=[m,n],
                                    instructions=len(fast['trace']),status=fast['status'],
                                    stats=stats,reference_seconds=original_seconds,accelerated_seconds=time.perf_counter()-start))

    def test_vm_errors_and_input_mutation_are_not_hidden(self):
        matrix,y=inputs();p,_=package('ADMM',matrix)
        for limit,measurement in ((1,y),(100000,y*100000)):
            def outcome(fast):
                try:execute(p,matrix,measurement,limit,accelerate_gemv=fast)
                except Exception as error:return type(error).__name__,str(error)
                return None
            self.assertIsNotNone(outcome(False));self.assertEqual(outcome(False),outcome(True))
        ar=Arithmetic(PROFILE);backend=BoundedGemv(ar)
        a=np.array([[1]],dtype=object);v=np.array([65536],dtype=object)
        self.assertEqual(list(backend.matvec(a,v,PROFILE.coefficient,PROFILE.state,PROFILE.state)),[1])
        a[0,0]=-1
        self.assertEqual(list(backend.matvec(a,v,PROFILE.coefficient,PROFILE.state,PROFILE.state)),[-1])
        prepared=backend.prepare(a)
        a[0,0]=2
        self.assertEqual(list(backend.prepared_matvec(prepared,v)),[-1])
        self.assertEqual(list(backend.prepared_matvec(backend.prepare(a),v)),[2])
        self.assertFalse(prepared.data.flags.writeable)
        self.assertIsNone(backend.prepare([[131072]]))
        with self.assertRaises(TypeError):backend.prepared_matvec(np.array([[131072]]),v)
        for invalid in ([67108864],[1.5],[True],[[1]]):
            left=Arithmetic(PROFILE);right=Arithmetic(PROFILE);fast=BoundedGemv(right)
            def outcome(fn):
                try:return ('value',plain(fn()))
                except Exception as error:return ('error',type(error).__name__,str(error))
            self.assertEqual(outcome(lambda:left.matvec([[-1]],invalid,PROFILE.coefficient,PROFILE.state,PROFILE.state)),
                             outcome(lambda:fast.prepared_matvec(fast.prepare([[-1]]),invalid)))
            self.assertEqual(left.events,right.events)

    def test_model_context_trajectories_nested_exception_and_restoration(self):
        matrix,y=inputs()
        originals=(Arithmetic.dot_raw,Arithmetic.matvec)
        kernel_originals=(IntegerKernels.__init__,IntegerKernels.mv)
        with model_acceleration():pass
        self.assertEqual((Arithmetic.dot_raw,Arithmetic.matvec),originals)
        self.assertEqual((IntegerKernels.__init__,IntegerKernels.mv),kernel_originals)
        try:
            with model_acceleration():
                accelerated=(Arithmetic.dot_raw,Arithmetic.matvec)
                accelerated_kernels=(IntegerKernels.__init__,IntegerKernels.mv)
                with model_acceleration():pass
                self.assertEqual((Arithmetic.dot_raw,Arithmetic.matvec),accelerated)
                self.assertEqual((IntegerKernels.__init__,IntegerKernels.mv),accelerated_kernels)
                raise RuntimeError('intentional unwind')
        except RuntimeError:pass
        self.assertEqual((Arithmetic.dot_raw,Arithmetic.matvec),originals)
        self.assertEqual((IntegerKernels.__init__,IntegerKernels.mv),kernel_originals)
        caller_matrix=matrix.copy();policy=ProximalPolicy(max_iterations=1,inner_max_iterations=24)
        with model_acceleration():
            kernel=IntegerKernels(caller_matrix,y,policy,PROFILE)
            vector=np.zeros(matrix.shape[1],dtype=object);vector[0]=1<<22
            expected=kernel.mv(vector)
            caller_matrix[0,0]*=-1
            self.assertTrue(np.array_equal(expected,kernel.mv(vector)))
            alias=kernel.a[:, :]
            with self.assertRaises(ValueError):kernel.a[0,0]=0
            with self.assertRaises(ValueError):alias[0,0]=0
            reassigned=kernel.a.copy();reassigned[0,0]*=-1;kernel.a=reassigned
            direct=kernel.arithmetic.matvec(reassigned,vector,PROFILE.coefficient,PROFILE.state,PROFILE.state)
            self.assertTrue(np.array_equal(direct,kernel.mv(vector)))
            self.assertFalse(np.array_equal(expected,direct))
        self.assertEqual((IntegerKernels.__init__,IntegerKernels.mv),kernel_originals)
        for algorithm in ALGORITHMS:
            _,policy=package(algorithm,matrix)
            def solve():
                return (proximal_run(algorithm,matrix,y,policy,PROFILE) if algorithm in PROX else
                        run(algorithm,matrix,y,policy,PROFILE,ls_solver='qr' if algorithm in QR else 'lsqr',solution_format=Format(24,20)))
            original=solve()
            with model_acceleration():fast=solve()
            self.assertEqual(plain(vars(original)),plain(vars(fast)))
            self.assertEqual((Arithmetic.dot_raw,Arithmetic.matvec),originals)
            RECORDS.append(dict(kind='complete_model',algorithm=algorithm,status=fast.status))

if __name__=='__main__':unittest.main()
