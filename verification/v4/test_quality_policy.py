"""Candidate policy configuration checks; no RTL simulation."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('isolated_quality_policy',ROOT/'compiler/v4/quality_policy.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
from models.v4.lfsr_operator import lfsr32_matrix
from compiler.v4.recovery_emit import compile_recovery


class QualityPolicyTests(unittest.TestCase):
    def test_greedy_quantization_stop_and_budgets(self):
        a=lfsr32_matrix(0x12345678,64,256,scale=8192)/65536.
        for alg,budget in [('OMP',8),('GOMP',4),('CoSaMP',8),('SP',8),('HTP',128),('MP',64),('GP',64)]:
            p=module.candidate_policy(alg,a)
            self.assertEqual((p.sparsity,p.max_iterations,p.residual_atol),(8,budget,1/2048))
            self.assertEqual(p.ls_normal_rtol,1e-4)
            if alg in ('MP','GP'):
                package=compile_recovery(alg,a,p,sparse_forward=True)
                self.assertLessEqual(len(package['program']),1024)

    def test_proximal_limits_use_actual_operator(self):
        for m,n,scale in [(64,256,8192),(32,64,11585)]:
            a=lfsr32_matrix(0x12345678,m,n,scale=scale)/65536.;l=np.linalg.norm(a,2)**2
            f=module.candidate_policy('FISTA',a);p=module.candidate_policy('PDHG',a)
            tau=round(f.step_size*2**22)/2**22
            self.assertLessEqual(tau*l,1.)
            self.assertLess((round(p.step_size*2**22)/2**22)*(round(p.pd_sigma*2**22)/2**22)*l,1.)
            self.assertEqual(f.regularization,.01)
            self.assertEqual(f.regularization,p.regularization)

    def test_admm64_policy_and_numerical_scope(self):
        a=lfsr32_matrix(0x12345678,64,256,scale=8192)/65536.
        p=module.candidate_policy('ADMM',a)
        self.assertEqual((p.regularization,p.max_iterations,p.admm_rho,p.inner_max_iterations,p.inner_rtol),(.01,64,.3,64,1e-4))
        evidence=module.candidate_qualification('ADMM',a)
        self.assertEqual(evidence['training_signal_support_seeds'],[4101,4102,4103,4104])
        self.assertEqual(evidence['reserved_signal_support_seeds'],[10001,10002])
        self.assertIn('same Phi',evidence['scope'])
        changed_sign=a.copy();changed_sign[0,0]*=-1
        with self.assertRaises(ValueError):module.candidate_qualification('ADMM',changed_sign)
        with self.assertRaises(ValueError):module.candidate_qualification('ADMM',a[:32])

    def test_iht_regime_and_dyadic_constants(self):
        a=lfsr32_matrix(0x12345678,128,256,scale=5793)/65536.
        p=module.candidate_policy('IHT',a)
        self.assertEqual(p.residual_atol,12/16384)
        package=compile_recovery('IHT',a,p,sparse_forward=True)
        self.assertLessEqual(len(package['program']),1024)
        with self.assertRaises(ValueError):module.candidate_policy('IHT',a[:64])

    def test_unsupported_operator_rejected(self):
        a=np.ones((64,256))*.125
        a[0,0]=.25
        with self.assertRaises(ValueError):module.candidate_policy('FISTA',a)
        with self.assertRaises(ValueError):module.candidate_policy('FISTA',np.zeros((64,256)))
        with self.assertRaises(ValueError):module.candidate_policy('FISTA',np.ones((64,256))*(.125+.5/65536))
        with self.assertRaises(ValueError):module.candidate_policy('NIHT',np.ones((64,256))*.125)


if __name__=='__main__':unittest.main()
