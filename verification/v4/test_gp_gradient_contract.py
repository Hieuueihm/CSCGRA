"""Independent gradient, directional minimum and fixed-point GP regressions."""
import unittest
import numpy as np
from compiler.v4.recovery_emit import PROFILE, compile_recovery
from models.v4.fixed import Arithmetic, Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute


class GpGradientContractTests(unittest.TestCase):
    def test_negative_gradient_and_directional_line_minimum(self):
        matrix=lfsr32_matrix(0x12345678,7,11,scale=11585)/65536.0
        rng=np.random.default_rng(0)
        y=rng.integers(-8192,8193,7)/16384.0
        x=rng.uniform(-0.1,0.1,11)
        residual=y-matrix@x
        gradient=matrix.T@residual
        objective=lambda value:0.5*float((y-matrix@value)@(y-matrix@value))
        epsilon=1e-6
        for index in range(11):
            offset=np.zeros(11);offset[index]=epsilon
            measured=(objective(x+offset)-objective(x-offset))/(2*epsilon)
            self.assertAlmostEqual(measured,-gradient[index],delta=1e-9)
        direction=np.zeros(11);direction[[1,4,7]]=gradient[[1,4,7]]
        projected=matrix@direction
        alpha=float(residual@projected)/float(projected@projected)
        minimum=x+alpha*direction
        self.assertAlmostEqual(float(projected@(y-matrix@minimum)),0.0,delta=1e-14)
        for delta in (-0.01,0.01):
            self.assertGreater(objective(x+(alpha+delta)*direction),objective(minimum))

    def test_fixed_q_numerator_cannot_be_replaced_by_gradient_energy(self):
        raw_matrix=lfsr32_matrix(0x12345678,7,11,scale=11585).astype(int)
        raw_y=np.random.default_rng(0).integers(-8192,8193,7)
        residual=raw_y.astype(object)*256
        ar=Arithmetic(PROFILE);state=PROFILE.state
        gradient=ar.matvec(raw_matrix,residual,PROFILE.coefficient,state,state,True)
        selected=max(range(11),key=lambda index:(abs(gradient[index]),-index))
        direction=np.zeros(11,dtype=object);direction[selected]=gradient[selected]
        projected=ar.matvec(raw_matrix,direction,PROFILE.coefficient,state,state)
        numerator=ar.dot_raw(residual,projected)
        denominator=ar.dot_raw(projected,projected)
        alpha=ar.ratio(numerator,denominator,0,state)
        alternate=ar.ratio(ar.dot_raw(direction,direction),denominator,0,state)
        def stored(step):
            raw=ar.mul(direction,step,state,state,state)
            return ar.rescale(ar.rescale(raw,22,Format(24,20)),20,state)
        expected=stored(alpha)
        # This fixture differs by two X24 units under the invalid substitution.
        self.assertEqual((selected,numerator,alpha),(5,1074976788480,19174798))
        self.assertNotEqual(int(expected[selected]),int(stored(alternate)[selected]))
        expected_residual=ar.sub(residual,ar.matvec(raw_matrix,expected,PROFILE.coefficient,state,state),state)
        for sparse in (False,True):
            actual=execute(compile_recovery('GP',raw_matrix/65536.0,Policy(2,max_iterations=1),
                                           sparse_forward=sparse),raw_matrix/65536.0,raw_y/16384.0)
            np.testing.assert_array_equal(actual['x'],expected)
            np.testing.assert_array_equal(actual['residual'],expected_residual)
            self.assertEqual(actual['support'],[selected])
        self.assertFalse(any(ar.events.values()))

    def test_reselection_retains_support_instead_of_forcing_new_atoms(self):
        rows,n=32,128
        matrix=lfsr32_matrix(0x12345678,rows,n,scale=11585)/65536.0
        rng=np.random.default_rng(1909+rows+n)
        support=sorted(map(int,rng.choice(n,2,replace=False)))
        truth=np.zeros(n);truth[support]=rng.uniform(0.5,1.0,2)*rng.choice([-1,1],2)
        y=matrix@truth;y=np.rint(y*(0.5/max(abs(y)))*16384)/16384.0
        results=[execute(compile_recovery('GP',matrix,Policy(2,max_iterations=8),sparse_forward=s),matrix,y)
                 for s in (False,True)]
        for result in results:
            self.assertEqual(result['outer'],7)
            self.assertEqual(sorted(result['support']),support)
            self.assertGreater(result['outer'],len(result['support']))
            self.assertEqual(result['status'],'residual_tolerance')
        np.testing.assert_array_equal(results[0]['x'],results[1]['x'])
        np.testing.assert_array_equal(results[0]['residual'],results[1]['residual'])


if __name__=='__main__':unittest.main()
