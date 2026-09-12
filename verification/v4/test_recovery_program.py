"""Decode and execute complete candidate programs against existing numeric models."""
import unittest
import numpy as np
from compiler.v4.recovery_emit import compile_recovery,PROFILE,mapping_estimate,mapping_selection,CALIBRATED_LIVE_PHI_R4
from compiler.v4.recovery_program import decode,unpack,ABI
from models.v4.fixed import Format
from models.v4.recovery import Policy,run
from models.v4.proximal import Policy as ProximalPolicy,run as proximal_run
from verification.v4.recovery_program_vm import execute


class RecoveryProgramTests(unittest.TestCase):
    def compare(self,algorithm,a,y,policy):
        package=compile_recovery(algorithm,a,policy)
        actual=execute(package,a,y)
        if algorithm in ('FISTA','PDHG','ADMM'):
            expected=proximal_run(algorithm,a,y,policy,PROFILE)
        else:
            expected=run(algorithm,a,y,policy,PROFILE,ls_solver='lsqr',solution_format=Format(24,20))
        self.assertEqual(list(actual['x']),[round(float(x)*2**22) for x in expected.x],algorithm)
        self.assertEqual(list(actual['residual']),[round(float(x)*2**22) for x in expected.residual],algorithm)
        self.assertEqual(actual['status'],expected.status,algorithm)
        self.assertEqual(actual['outer'],sum(t['phase']=='COMMIT' for t in expected.trace),algorithm)
        if algorithm in ('MP','GP','IHT'):self.assertEqual(actual['support'],expected.support)
        return actual,package

    def test_complete_six_programs_random_small_phi(self):
        rng=np.random.default_rng(90123)
        for m,n in ((3,2),(5,7),(9,5)):
            a=rng.choice([-1.,1.],size=(m,n))*.25
            y=rng.integers(-1024,1025,size=m)/16384
            for algorithm in ('MP','GP','IHT','FISTA','PDHG','ADMM'):
                policy=ProximalPolicy(max_iterations=4,inner_max_iterations=24) if algorithm in ('FISTA','PDHG','ADMM') else Policy(min(n,2),max_iterations=4)
                with self.subTest(algorithm=algorithm,m=m,n=n):self.compare(algorithm,a,y,policy)

    def test_zero_measurement_and_iteration_termination(self):
        a=np.array([[1.,1.],[1.,-1.]])*.5
        for algorithm in ('MP','GP','IHT'):
            actual,_=self.compare(algorithm,a,np.zeros(2),Policy(1,max_iterations=1))
            self.assertEqual(actual['outer'],0)
        for algorithm in ('FISTA','PDHG','ADMM'):
            self.compare(algorithm,a,np.zeros(2),ProximalPolicy(max_iterations=2))

    def test_admm_inner_not_converged_preserves_candidate(self):
        a=np.array([[1.,1.,1.],[1.,-1.,1.],[-1.,1.,1.],[1.,1.,-1.]])*.25
        self.compare('ADMM',a,np.array([.125,.0625,-.03125,.015625]),
                     ProximalPolicy(max_iterations=3,inner_max_iterations=1,inner_rtol=1e-5))

    def test_maximum_pool_liveness_and_r4_configuration(self):
        a=np.ones((128,1024))/16
        p=compile_recovery('ADMM',a,ProximalPolicy(max_iterations=3),r4=True)
        self.assertLessEqual(max(v['base']+(v['capacity']+31)//32 for v in p['vectors']),480)
        self.assertLessEqual(len(p['vectors']),32)
        self.assertLessEqual(len(p['program']),1024)
        for word in p['program']:
            f=decode(word)
            if f['kind']==1:self.assertEqual(unpack(ABI['service_immediate_fields'],f['immediate'])['r4'],int(f['kernel']==1))

    def test_unavailable_qr_and_unsupported_operator_reject(self):
        with self.assertRaisesRegex(ValueError,'no LSQR fallback'):
            compile_recovery('OMP',np.ones((2,2))*.5,Policy(1))
        with self.assertRaisesRegex(ValueError,'one nonzero'):
            compile_recovery('MP',np.eye(2),Policy(1))

    def test_mapping_selector_uses_only_exact_live_phi_measurements(self):
        for (rows, columns, transpose), expected in CALIBRATED_LIVE_PHI_R4.items():
            decision=mapping_selection(rows,columns,transpose=transpose)
            self.assertEqual(decision['r4'],expected)
            self.assertEqual(decision['selection'],'measured_exact_live_phi')
            self.assertTrue(decision['calibration']['exact_shape'])
            # Calibration matches the previously emitted mapping bit for every
            # qualified target shape, so existing load images retain their words.
            self.assertEqual(expected,min(decision['estimates'],key=lambda item:item['estimated_ticks'])['r4'])
        for rows,columns in ((32,64),(64,256)):
            decision=mapping_selection(rows,columns,dense=True)
            self.assertEqual(decision['selection'],'legacy_estimate_unqualified_fallback')
            self.assertEqual(decision['calibration']['reason'],'runtime_dynamic_restricted_dense_width')
        explicit=mapping_selection(32,64,transpose=True,r4=False)
        self.assertFalse(explicit['r4'])
        self.assertEqual(explicit['selection'],'explicit_ablation_override')

    def test_mapping_estimates_include_striped_tail_frames(self):
        for reductions in (1,7,8,9,20,31,32,33,96,128,1024):
            choices=mapping_estimate(33,reductions)
            self.assertEqual(choices[0]['frames'],2*reductions)
            self.assertEqual(choices[1]['frames'],5*(8*(reductions//32)+min(reductions%32,8)))
        self.assertFalse(min(mapping_estimate(128,1024),key=lambda x:x['estimated_ticks'])['r4'])
        self.assertTrue(min(mapping_estimate(128,1024,True),key=lambda x:x['estimated_ticks'])['r4'])
        for trans in (False,True):
            self.assertFalse(min(mapping_estimate(128,96,trans,True),key=lambda x:x['estimated_ticks'])['r4'])


if __name__=='__main__':unittest.main()
