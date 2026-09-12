"""Actual loaded QR schedules against the independent Householder numeric model."""
import unittest
import numpy as np
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE,Program
from compiler.v4.qr_program import emit_qr
from models.v4.qr import IntegerQRKernels
from compiler.v4.recovery_program import decode,encode,unpack,ABI,service_immediate
from models.v4.fixed import Format
from models.v4.recovery import Policy,run
from verification.v4.recovery_program_vm import execute

class QrProgramTests(unittest.TestCase):
    def compare(self,algorithm,matrix,measurement,policy,refinements=2):
        package=compile_greedy_qr(algorithm,matrix,policy,max_refinements=refinements)
        actual=execute(package,matrix,measurement,limit=1000000)
        expected=run(algorithm,matrix,measurement,policy,PROFILE,ls_solver='qr',solution_format=Format(24,20),qr_max_refinements=refinements)
        self.assertEqual(list(actual['x']),[round(float(x)*2**22) for x in expected.x])
        self.assertEqual(list(actual['residual']),[round(float(x)*2**22) for x in expected.residual])
        # The generic ABI reports solver failure without naming its algorithm.
        self.assertEqual(actual['status'],{'qr_not_converged':'ls_not_converged','rank_deficient':'numeric_fault'}.get(expected.status,expected.status))
        self.assertEqual(actual['support'],expected.support)
        self.assertEqual(actual['outer'],sum(t['phase']=='COMMIT' for t in expected.trace))
        return package,actual
    def test_all_five_complete_programs_and_zero_refinement_ablation(self):
        rng=np.random.default_rng(991)
        for m,n in [(16,32),(33,35)]:
            matrix=rng.choice([-1.,1.],(m,n))*.125
            x=np.zeros(n);x[2]=.25;x[9]=-.125;y=matrix@x
            for algorithm in ('OMP','GOMP','CoSaMP','SP','HTP'):
                for bound in (0,2):
                    with self.subTest(algorithm=algorithm,m=m,bound=bound):self.compare(algorithm,matrix,y,Policy(2,max_iterations=3),bound)
    def test_zero_measurement_and_tail_zero_reflectors(self):
        matrix=np.array([[1.,1.],[1.,-1.]])*.25
        for algorithm in ('OMP','GOMP','CoSaMP','SP','HTP'):
            self.compare(algorithm,matrix,np.zeros(2),Policy(1,max_iterations=1,group_size=1))
        self.compare('OMP',np.array([[.25]]),np.array([.0625]),Policy(1,max_iterations=1))
    def test_maximum_shape_package_liveness_and_program_bound(self):
        matrix=np.random.default_rng(871).choice([-1.,1.],(128,1024))/16
        for algorithm in ('OMP','GOMP','CoSaMP','SP','HTP'):
            package=compile_greedy_qr(algorithm,matrix,Policy(16,max_iterations=16))
            self.assertLessEqual(len(package['program']),1024)
            self.assertLessEqual(len(package['vectors']),32)
            self.assertLessEqual(max(v['base']+(v['capacity']+31)//32 for v in package['vectors']),480)
    def test_failed_certificate_exact_correction_bound_preserves_result(self):
        rng=np.random.default_rng(812)
        matrix=rng.choice([-1.,1.],(16,32))*.25
        y=rng.integers(-1024,1024,16)/16384
        for bound in (0,2):
            _,actual=self.compare('OMP',matrix,y,Policy(2,max_iterations=3,ls_normal_rtol=1e-8),bound)
            self.assertEqual(actual['status'],'ls_not_converged')
            self.assertEqual(actual['inner'],bound+1)
            self.assertEqual(actual['outer'],1)
            self.assertTrue(any(actual['x']))
    def test_normalize_loaded_context_contract_is_enforced(self):
        matrix=np.random.default_rng(991).choice([-1.,1.],(16,32))*.125
        y=matrix[:,2]*.25
        package=compile_greedy_qr('OMP',matrix,Policy(1,max_iterations=1))
        pc=next(i for i,w in enumerate(package['program']) if decode(w)['kind']==1 and decode(w)['kernel']==2)
        word=decode(package['program'][pc]);fields=unpack(ABI['service_immediate_fields'],word['immediate'])
        fields['template']=next(i for i,t in enumerate(package['templates']) if t['name']=='copy')
        word['immediate']=service_immediate(**fields)
        package['program'][pc]=encode('KERNEL',**{k:v for k,v in word.items() if k in ABI['allowed_fields']['KERNEL']})
        with self.assertRaisesRegex(AssertionError,'loaded MAC mode'):execute(package,matrix,y)
    def test_dynamic_support_factor_loops_and_preserved_outer_registers(self):
        for m,s in [(33,17),(128,96)]:
            with self.subTest(m=m,s=s):self.dynamic_support(m,s)
    def dynamic_support(self,m,s):
        matrix=np.random.default_rng(4481).choice([-1.,1.],(m,s))*.125
        y=np.random.default_rng(997).integers(-1024,1024,m)/16384
        policy=Policy(2,max_iterations=3);p=Program('OMP',matrix,policy,None);a=p.a
        p.vec('PX',96);p.vec('IDX',1);p.set(28,s);p.set(29,s);p.set(26,17)
        preserved={r:r*113 for r in list(range(16,25))+[27,30,31]}
        for r,value in preserved.items():p.set(r,value)
        p.op('zero','S',length=s);p.set(1,0);p.set(2,1)
        a.label('indices');p.op('scalar','IDX',length=1,scalar=1)
        p.call('REPLACE_RANGE','S','S',length=s,aux_v=p.v['IDX'],index_s=1,aux_length_s=2)
        p.inc(1);p.branch('BR_COMPARE','indices',a_s=1,b_s=28,immediate=2)
        a.emit('BUILD_B',a_v=p.v['S'],a_s=28);p.branch('CALL','qr')
        p.op('copy','X','PX',length=s);p.halt('MAX_ITERATIONS')
        a.label('failed');p.halt('LS_NOT_CONVERGED')
        emit_qr(p,'qr',result_vector='PX',residual_vector='R',failure_label='failed',max_refinements=2)
        actual=execute(p.finish(),matrix,y,limit=1000000)
        model=IntegerQRKernels(matrix,y,policy,PROFILE,max_refinements=2)
        expected=model.least_squares(list(range(s)))
        self.assertEqual(list(actual['x']),list(expected));self.assertEqual(actual['outer'],17)
        for r,value in preserved.items():self.assertEqual(actual['scalar_registers'][r],value)
        self.assertEqual(actual['support'],list(range(s)));self.assertEqual(actual['inner'],model.ls_steps)
        self.assertEqual(list(actual['residual']),list(model.sub(model.y,model.mv(expected,support=list(range(s))))))

if __name__=='__main__':unittest.main()
