"""Numerical candidate QR boundaries; these are not RTL or LSQR equivalence tests."""
import unittest
import numpy as np
from models.v4.fixed import Format,Profile
from models.v4.qr import IntegerQRKernels
from models.v4.recovery import Policy

PROFILE=Profile(Format(18,14),Format(18,16),Format(27,22),64)

class QRNumericTests(unittest.TestCase):
    def backend(self,a,y,refinements=2):
        return IntegerQRKernels(a,y,Policy(len(a[0]),ls_normal_rtol=1e-5),PROFILE,max_refinements=refinements)

    def test_identity_and_negative_diagonal_exact_storage(self):
        for sign in (-1,1):
            b=self.backend(sign*np.eye(3),[.25,-.125,.0625])
            result=b.least_squares([0,1,2])
            self.assertEqual(list(result),[sign*(1<<20),-sign*(1<<19),sign*(1<<18)])
            self.assertTrue(b.last_ls_report['certificate_history'][-1]['passed'])
            self.assertLess(b.diagnostics([0,1,2])['factor_relative_residual'],1e-12)

    def test_rectangular_reflectors_and_certificate(self):
        a=np.array([[.5,.125],[.25,-.5],[-.5,.25],[.125,.5]])
        b=self.backend(a,a@np.array([.25,-.125]))
        result=b.least_squares([0,1])
        self.assertTrue(all(int(v)%4==0 for v in result))
        diagnostics=b.diagnostics([0,1])
        self.assertEqual(diagnostics['rank'],2)
        self.assertLess(diagnostics['factor_relative_residual'],1e-5)
        self.assertLess(diagnostics['orthogonality_frobenius'],1e-5)
        self.assertLess(diagnostics['coefficient_relative_error'],1e-3)

    def test_rank_deficient_and_near_singular_do_not_fake_success(self):
        b=self.backend([[1,1],[0,0]],[.5,0])
        with self.assertRaisesRegex(ArithmeticError,'rank_deficient'):b.least_squares([0,1])
        b=self.backend([[1,1],[0,1/65536]],[.5,.5])
        with self.assertRaisesRegex(ArithmeticError,'numeric_fault'):b.least_squares([0,1])

    def test_empty_support_and_profile_rejection(self):
        b=self.backend([[1]],[0]);self.assertEqual(len(b.least_squares([])),0)
        with self.assertRaises(ValueError):
            IntegerQRKernels([[1]],[0],Policy(1),PROFILE,solution_format=Format(18,14))

if __name__=='__main__':unittest.main()
