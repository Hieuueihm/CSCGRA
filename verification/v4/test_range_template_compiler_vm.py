"""Feature7 RANGE_TEMPLATE compiler/VM checks; not RTL evidence."""
import copy
import unittest
import numpy as np
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_program import ABI, decode, encode, unpack
from compiler.v4.recovery_emit import Program
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.recovery_program_vm_reference import execute as reference_execute

def fixture(rows=32, columns=64):
    return (lfsr32_matrix(0x12345678,rows,columns,scale=8192)/65536.0,
            np.random.default_rng(177).integers(-4096,4097,rows)/16384.0)

def range_pcs(package):
    return [pc for pc,word in enumerate(package['program'])
            if decode(word)['kind']==ABI['kinds']['KERNEL'] and decode(word)['kernel']==22]

class RangeTemplateCompilerVmTests(unittest.TestCase):
    def _micro(self, op, output, mode, length, scalar):
        matrix,measurement=fixture(64,64);p=Program('OMP',matrix,Policy(2,max_iterations=1),None)
        p.t['range']=p.a.template('range',op,output,bind_b=0xffffffff,mode=mode,shift=22 if output=='LAST_ACC' else 0)
        dst='D' if output=='LAST_ACC' else 'R'
        if dst=='D':p.vec('D',32)
        p.set(1,scalar);p.call('RANGE_TEMPLATE',dst,'R','X',length=length,template='range',out=5,sb=1)
        p.a.emit('HALT_STATUS',dst_v=p.v['X'],a_v=p.v['Y'],b_v=p.v['S'],immediate=ABI['statuses']['MAX_ITERATIONS'])
        return p.finish(),matrix,measurement

    def test_generic_each_last_acc_sum_acc_and_modes_execute(self):
        for args in (('MUL','EACH',0,33,1<<16),('MAC','LAST_ACC',1,64,1<<22),('MAC','SUM_ACC',1,3,1)):
            package,matrix,measurement=self._micro(*args)
            for runner in (execute,reference_execute):
                self.assertEqual(runner(package,matrix,measurement,limit=10000)['status'],'max_iterations')

    def test_view_replaces_qr_slices_and_matches_streamed(self):
        matrix,measurement=fixture();policy=Policy(8,max_iterations=2,residual_atol=0)
        streamed=compile_greedy_qr('CoSaMP',matrix,policy,qr_profile='streamed')
        view=compile_greedy_qr('CoSaMP',matrix,policy,qr_profile='view')
        self.assertEqual(view['required_kernel_revision'],7);self.assertTrue(view['qr_range_template_enabled'])
        self.assertGreaterEqual(len(range_pcs(view)),3);self.assertLess(len(view['program']),len(streamed['program']))
        baseline=execute(streamed,matrix,measurement,limit=2_000_000)
        for result in (execute(view,matrix,measurement,limit=2_000_000),reference_execute(view,matrix,measurement,limit=2_000_000)):
            self.assertEqual((list(result['x']),list(result['residual']),result['support'],result['status'],result['outer'],result['inner']),
                             (list(baseline['x']),list(baseline['residual']),baseline['support'],baseline['status'],baseline['outer'],baseline['inner']))

    def test_view_m32_and_m64_raw_equivalence(self):
        for rows,columns,seed in ((32,64,177),(64,256,311)):
            with self.subTest(rows=rows,columns=columns):
                matrix,measurement=fixture(rows,columns)
                measurement=np.random.default_rng(seed).integers(-4096,4097,rows)/16384.0
                policy=Policy(8,max_iterations=2,residual_atol=0)
                baseline=execute(compile_greedy_qr('CoSaMP',matrix,policy,qr_profile='streamed'),matrix,measurement,limit=4_000_000)
                view=compile_greedy_qr('CoSaMP',matrix,policy,qr_profile='view')
                for result in (execute(view,matrix,measurement,limit=4_000_000),reference_execute(view,matrix,measurement,limit=4_000_000)):
                    self.assertEqual((list(result['x']),list(result['residual']),result['support'],result['status'],result['outer'],result['inner']),
                                     (list(baseline['x']),list(baseline['residual']),baseline['support'],baseline['status'],baseline['outer'],baseline['inner']))

    def test_view_omp_refinement_and_gomp_support96(self):
        matrix,measurement=fixture(16,32);measurement=np.random.default_rng(1).integers(-4096,4097,16)/16384.0
        policy=Policy(4,max_iterations=3,residual_atol=0,ls_normal_rtol=1e-6)
        streamed=compile_greedy_qr('OMP',matrix,policy,qr_profile='streamed');view=compile_greedy_qr('OMP',matrix,policy,qr_profile='view')
        baseline=execute(streamed,matrix,measurement,limit=3_000_000);result=execute(view,matrix,measurement,limit=3_000_000)
        self.assertEqual((list(result['x']),list(result['residual']),result['support'],result['status'],result['outer'],result['inner']),
                         (list(baseline['x']),list(baseline['residual']),baseline['support'],baseline['status'],baseline['outer'],baseline['inner']))
        self.assertGreaterEqual(sum(pc==view['labels']['qr_solve'] for pc in result['trace']),3)
        self.assertGreater(sum(pc in set(range_pcs(view)) for pc in result['trace']),0)
        matrix=lfsr32_matrix(0x12345678,128,128,scale=4096)/65536.0;measurement=np.random.default_rng(911).integers(-8192,8193,128)/16384.0
        policy=Policy(2,max_iterations=2,group_size=48,residual_atol=0)
        streamed=compile_greedy_qr('GOMP',matrix,policy,qr_profile='streamed');view=compile_greedy_qr('GOMP',matrix,policy,qr_profile='view')
        baseline=execute(streamed,matrix,measurement,limit=5_000_000);result=execute(view,matrix,measurement,limit=5_000_000)
        self.assertEqual((list(result['x']),list(result['residual']),result['support'],result['status'],result['outer'],result['inner']),
                         (list(baseline['x']),list(baseline['residual']),baseline['support'],baseline['status'],baseline['outer'],baseline['inner']))
        self.assertEqual(len(result['support']),96)

    def test_range_template_rejects_payload_and_reserved_context(self):
        matrix,measurement=fixture();package=compile_greedy_qr('CoSaMP',matrix,Policy(8,max_iterations=2,residual_atol=0),qr_profile='view')
        pc=range_pcs(package)[0];bad=copy.deepcopy(package);fields=decode(bad['program'][pc]);fields['target']=1
        bad['program'][pc]=encode('KERNEL',**{key:fields[key] for key in ABI['allowed_fields']['KERNEL']})
        template=unpack(ABI['service_immediate_fields'],decode(package['program'][pc])['immediate'])['template']
        malformed=copy.deepcopy(package);malformed['templates'][template]['contexts'][0]|=1<<63
        for runner in (execute,reference_execute):
            with self.assertRaises(AssertionError):runner(bad,matrix,measurement,limit=2_000_000)
            with self.assertRaises(ValueError):runner(malformed,matrix,measurement,limit=2_000_000)

if __name__=='__main__':unittest.main()



