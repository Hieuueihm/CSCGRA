"""Outer-program integration checks independent of LSQR recurrence details."""
import unittest
import numpy as np

from models.v4.fixed import Format, Profile
from models.v4.recovery import Policy, run


class LSQRIntegrationTests(unittest.TestCase):
    def test_omp_identity_matches_analytic_solution_and_records_solver(self):
        a=np.eye(8); y=np.array([0.,.5,0.,0.,-.25,0.,0.,0.])
        p=Profile(Format(18,14),Format(18,16),Format(27,19),64)
        r=run('OMP',a,y,Policy(2,max_iterations=2),p,ls_solver='lsqr')
        np.testing.assert_array_equal(r.x,y)
        self.assertEqual(r.status,'residual_tolerance')
        self.assertTrue(r.solver_trace)
        self.assertFalse(any(r.events.values()))

    def test_first_failed_ls_preserves_zero_committed_result(self):
        rng=np.random.default_rng(938)
        a=rng.normal(size=(12,16)); a/=np.linalg.norm(a,axis=0)
        x=np.zeros(16); x[[2,7]]=[.4,-.3]
        y=a@x+rng.normal(size=12)*.001
        p=Profile(Format(24,20),Format(18,16),Format(32,24),74)
        r=run('CoSaMP',a,y,Policy(2,max_iterations=2,ls_max_iterations=1,ls_normal_rtol=1e-8),p,ls_solver='lsqr')
        self.assertTrue(any(t['phase']=='FAULT' for t in r.trace))
        np.testing.assert_array_equal(r.x,np.zeros(16))
        self.assertEqual(r.support,[])
        self.assertFalse(any(t['phase']=='COMMIT' for t in r.trace))
        self.assertTrue(r.solver_trace)

    def test_invalid_solver_rejected(self):
        with self.assertRaises(ValueError):
            run('OMP',np.eye(2),np.ones(2),Policy(1),ls_solver='unknown')


if __name__=='__main__':
    unittest.main()
