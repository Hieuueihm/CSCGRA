"""Loaded scalar templates retain S27 rounding and reject RAM operands."""
import unittest
import numpy as np
from compiler.v4.recovery_emit import Program
from compiler.v4.recovery_program import decode, encode, unpack, service_immediate, ABI
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute


class ScalarTemplateProgramTests(unittest.TestCase):
    def package(self,op,left,right):
        p=Program('MP',np.array([[.25]]),Policy(1,max_iterations=1),None)
        p.set(1,left);p.set(2,right);p.scalar_template(op,3,1,2);p.halt('MAX_ITERATIONS')
        return p.finish()

    def test_signed_rounding_bounds_and_no_vector_output(self):
        for op,left,right in [('MOV',-(1<<26),0),('MOV',(1<<26)-1,0),
                              ('ADD',17,-39),('SUB',-17,39),
                              ('MUL',1,1<<21),('MUL',-1,1<<21),
                              ('MUL',67108863,4194304),('MUL',-67108864,4194304)]:
            with self.subTest(op=op,left=left,right=right):
                product=left*right
                rounded=((abs(product)+(1<<21))>>22)*(1 if product>=0 else -1)
                expected=left if op=='MOV' else left+right if op=='ADD' else left-right if op=='SUB' else rounded
                result=execute(self.package(op,left,right),np.array([[.25]]),np.array([0.]))
                self.assertEqual(result['scalar_registers'][3],expected)
                self.assertEqual(list(result['x']),[0])
                self.assertEqual(list(result['residual']),[0])

    def test_overflow_is_fault_not_truncation(self):
        for op,left,right in [('ADD',67108863,1),('SUB',-67108864,1),
                              ('MUL',67108863,8388608),('MOV',67108864,0)]:
            with self.subTest(op=op):
                with self.assertRaises(ArithmeticError):execute(self.package(op,left,right),np.array([[.25]]),np.array([0.]))

    def test_unbound_operand_and_length_are_rejected(self):
        for mutation in ('unbound','length','output','mode'):
            package=self.package('MUL',3,5)
            pc=next(i for i,w in enumerate(package['program']) if decode(w)['kind']==1 and decode(w)['kernel']==16)
            fields=decode(package['program'][pc]);imm=unpack(ABI['service_immediate_fields'],fields['immediate'])
            template=package['templates'][imm['template']]
            if mutation=='unbound':template['bind_b']=0
            elif mutation=='output':template['descriptor']|=16
            elif mutation=='mode':template['contexts'][0]&=~32
            else:
                imm['length']=2;fields['immediate']=service_immediate(**imm)
                package['program'][pc]=encode('KERNEL',**{k:v for k,v in fields.items() if k in ABI['allowed_fields']['KERNEL']})
            with self.subTest(mutation=mutation):
                with self.assertRaises(AssertionError):execute(package,np.array([[.25]]),np.array([0.]))


if __name__=='__main__':unittest.main()
