"""Complete emitted non-LS programs on the real native recovery hierarchy."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import numpy as np
from compiler.v4 import recovery_program as asm
from compiler.v4.recovery_emit import compile_recovery,PROFILE
from models.v4.fixed import Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy,run
from models.v4.proximal import Policy as ProximalPolicy,run as proximal_run
from verification.v4.recovery_program_vm import execute
from verification.v4.test_recovery_engine_rtl import SOURCES,base_package,pack
from scripts.v4.xsim import compile_rtl,run_rtl
from verification.v4.recovery_cycle_profile import cycle_profile

ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
ALGORITHMS=('MP','GP','IHT','FISTA','PDHG','ADMM')


def rtl_args(fixture,trace,scale,cycle_limit,instruction_limit):
    """None leaves the testbench's 10000-instruction default intact."""
    args=['+fixture='+fixture.as_posix(),'+trace='+trace.as_posix(),'+debug=1',
          f'+scale={scale}',f'+cycle_limit={cycle_limit}']
    if instruction_limit is not None:
        if isinstance(instruction_limit,bool) or not isinstance(instruction_limit,int) or not 1<=instruction_limit<2**32:
            raise ValueError('instruction_limit must be a positive 32-bit integer or None')
        args.append(f'+instruction_limit={instruction_limit}')
    return args


class RecoveryAlgorithmsRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.attempt_index=0
        cls.path=Path(tempfile.mkdtemp(prefix='recovery_algorithms_',dir=ROOT/'work'))
        cls.binary=cls.path/'algorithms.xsim.json'
        cls.compiled=compile_rtl(cls.binary,'tb_recovery_engine',[ROOT/p for p in SOURCES],root=ROOT,timeout=300)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)

    @classmethod
    def tearDownClass(cls):
        (cls.path/'evidence.json').write_text(json.dumps(RUNS,indent=2))

    def case(self,algorithm,rows=5,n=7,zero=False,r4=None,iterations=3,inner_limit=24,sparse_forward=False,truth=False,refinements=2,sparsity=None,scale_override=None,planted=False,policy_override=None,planted_seed=None,instruction_limit=None,vm_limit=100000,cycle_limit=8000000,simulation_timeout=900,qr_profile='reference',qr_panel_min_columns=8,operand_chains=False,factor_range_template=False,factor_energy_tap=False,outer_fusion=False):
        runs=getattr(self,'run_records',RUNS)
        proximal=algorithm in ('FISTA','PDHG','ADMM')
        qr=algorithm in ('OMP','GOMP','CoSaMP','SP','HTP')
        if policy_override is not None and not proximal and sparsity is None:sparsity=policy_override.sparsity
        mode=2 if proximal else 1
        scale=4096 if rows==128 else 16384
        if scale_override is not None:scale=scale_override
        raw_phi=lfsr32_matrix(0x12345678,rows,n,scale=scale).astype(int)
        matrix=raw_phi/65536.0
        if rows==128:
            raw_y=np.array([(4096 if raw_phi[row,0]>0 else -4096)+(2048 if raw_phi[row,1]>0 else -2048) for row in range(rows)])
        else:
            raw_y=np.random.default_rng(721+rows+n).integers(-8192,8193,size=rows);raw_y[0]=8192
        if truth:raw_y=np.rint((matrix[:,3]*1.25+matrix[:,7]*0.75)*16384).astype(int)
        planted_x=None;planted_support=[];normalization_gain=1.0
        if planted:
            rng=np.random.default_rng(1909+rows+n if planted_seed is None else planted_seed)
            planted_support=sorted(map(int,rng.choice(n,sparsity,replace=False)))
            planted_x=np.zeros(n)
            planted_x[planted_support]=rng.uniform(0.5,1.0,size=sparsity)*rng.choice([-1,1],size=sparsity)
            analog_y=matrix@planted_x
            normalization_gain=0.5/float(np.max(np.abs(analog_y)))
            planted_x*=normalization_gain
            raw_y=np.rint(analog_y*normalization_gain*16384).astype(int)
        if zero:raw_y[:]=0
        y=raw_y/16384.0
        policy=ProximalPolicy(max_iterations=iterations,inner_max_iterations=inner_limit) if proximal else Policy(min(n,2) if sparsity is None else sparsity,max_iterations=iterations)
        if policy_override is not None:
            if not isinstance(policy_override,ProximalPolicy if proximal else Policy):raise TypeError("policy_override type does not match algorithm")
            policy=policy_override;iterations=policy.max_iterations
            if proximal:inner_limit=policy.inner_max_iterations
        if (isinstance(vm_limit,bool) or not isinstance(vm_limit,int) or vm_limit<1 or
            isinstance(cycle_limit,bool) or not isinstance(cycle_limit,int) or cycle_limit<1 or
            isinstance(simulation_timeout,bool) or not isinstance(simulation_timeout,int) or simulation_timeout<1):
            raise ValueError("invalid explicit watchdog limits")
        if instruction_limit is not None and vm_limit<instruction_limit:
            raise ValueError("VM trace limit must cover the explicit instruction limit")
        if qr:
            from compiler.v4.greedy_qr_emit import compile_greedy_qr
            package=compile_greedy_qr(algorithm,matrix,policy,r4=r4,max_refinements=refinements,
                                      qr_profile=qr_profile,qr_panel_min_columns=qr_panel_min_columns,
                                      operand_chains=operand_chains,
                                      factor_range_template=factor_range_template,
                                      factor_energy_tap=factor_energy_tap,outer_fusion=outer_fusion)
        else:package=compile_recovery(algorithm,matrix,policy,r4=r4,sparse_forward=sparse_forward,
                                      operand_chains=operand_chains)
        vm=execute(package,matrix,y,limit=vm_limit)
        if proximal:
            expected=proximal_run(algorithm,matrix,y,policy,PROFILE)
        elif qr:
            expected=run(algorithm,matrix,y,policy,PROFILE,ls_solver='qr',solution_format=Format(24,20),qr_max_refinements=refinements)
        else:
            # This existing provider supplies the qualified X24 store primitive.
            # MP/GP/IHT never invoke its LS routine; enforce that explicitly.
            expected=run(algorithm,matrix,y,policy,PROFILE,ls_solver='lsqr',solution_format=Format(24,20))
            self.assertEqual(expected.solver_trace,[])
        raw_x=[round(float(value)*2**22) for value in expected.x]
        raw_r=[round(float(value)*2**22) for value in expected.residual]
        quality=None
        if planted:
            floating=proximal_run(algorithm,matrix,y,policy) if proximal else run(algorithm,matrix,y,policy)
            signal=float(np.dot(planted_x,planted_x))
            def metrics(value):
                error=float(np.dot(np.asarray(value)-planted_x,np.asarray(value)-planted_x))
                return dict(nmse=error/signal,snr_db=None if error==0 else float(10*np.log10(signal/error)))
            quality=dict(fixed=metrics(expected.x),floating=metrics(floating.x),
                         floating_status=floating.status,scope='Timing fixture diagnostic against planted normalized truth; same quantized Phi/Y, not held-out application calibration')
        outer=sum(entry['phase']=='COMMIT' for entry in expected.trace)
        self.assertEqual(list(vm['x']),raw_x)
        self.assertEqual(list(vm['residual']),raw_r)
        public_status={'qr_not_converged':'ls_not_converged','rank_deficient':'numeric_fault'}.get(expected.status,expected.status)
        self.assertEqual(vm['status'],public_status)
        self.assertEqual(vm['outer'],outer)
        commits=[entry for entry in expected.trace if entry['phase']=='COMMIT']
        if qr and public_status not in ('ls_not_converged','numeric_fault'):
            self.assertEqual(vm['inner'],expected.solver_trace[-1]['steps'] if expected.solver_trace else 0)
        elif not qr and expected.status not in ('inner_not_converged','numeric_fault'):
            self.assertEqual(vm['inner'],commits[-1].get('inner_iterations',0) if commits else 0)
        if not proximal:self.assertEqual(vm['support'],expected.support)
        status=asm.ABI['statuses'][public_status.upper()]
        fault=0 if status<=5 else 2
        baseline=[7<<8]*n
        attempt=type(self).attempt_index;type(self).attempt_index+=1
        fixture=self.path/f'case{attempt}.txt';trace=self.path/f'trace{attempt}.txt'
        package_path=self.path/f'package{attempt}'
        asm.export_package(package,package_path)
        lines=[f'{rows} {n} 2']
        measurement_base=package['vectors'][package['measurement_vector']]['base']
        residual_base=package['vectors'][1]['base']
        for job,(pkg,memory) in enumerate([(base_package(n),{0:baseline}),(package,{measurement_base:[int(v)<<8 for v in raw_y]})]):
            records=asm.load_records(pkg)
            lines.append(f'{mode} 0 {int(not proximal) if job else 0} 0 {fault if job else 0} {status if job else 0}')
            lines.append(f"{len(pkg['program'])} {len(pkg['templates'])} {len(pkg['vectors'])} {len(pkg['constants'])} {len(records)}")
            lines.extend(f'{kind:x} {index:04x} {word:032x} {last:x}' for kind,index,word,last in records)
            writes=[]
            for base,values in memory.items():
                for start in range(0,len(values),32):
                    chunk=values[start:start+32]
                    writes.append(f'{base+start//32} {(1<<len(chunk))-1:08x} {pack(chunk):0216x}')
            lines.append(str(len(writes)));lines.extend(writes)
            lines.append(f'{residual_base} {rows if job and not fault else 0}')
        fixture.write_text('\n'.join(lines)+'\n')
        result=run_rtl(self.binary,rtl_args(fixture,trace,scale,cycle_limit,instruction_limit),root=ROOT,timeout=simulation_timeout)
        (self.path/f'simulation{attempt}.json').write_text(json.dumps(dict(commands=result.commands,returncode=result.returncode,stdout=result.stdout,stderr=result.stderr),indent=2))
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS cycles=',result.stdout)
        actual_x=[[],[]];actual_r=[];actual_trace=[];done=[];metadata=[];checks=0
        for line in trace.read_text().splitlines():
            f=line.split()
            if f[0]=='X':
                job=int(f[1]);raw=int(f[3],16);value=raw-(1<<27) if raw&(1<<26) else raw
                actual_x[job].append(value)
                self.assertEqual(tuple(map(int,f[4:])),(0,mode,0,100 if job==0 or fault else 101));checks+=4
            elif f[0]=='V':
                raw=int(f[3],16);actual_r.append(raw-(1<<27) if raw&(1<<26) else raw)
            elif f[0]=='T' and f[1]=='1':
                pc=int(f[2]);self.assertEqual(int(f[3],16),package['program'][pc]);checks+=1;actual_trace.append(pc)
            elif f[0]=='D':done.append(tuple(map(int,f[1:])))
            elif f[0]=='M':metadata.append(f)
            elif f[0]=='END':cycles,tbchecks,builds,kernels,scalars=map(int,f[1:]);checks+=tbchecks
        self.assertEqual(actual_x,[baseline,baseline if fault else raw_x]);checks+=2*n
        self.assertEqual(actual_r,[] if fault else raw_r);checks+=len(actual_r)
        self.assertEqual(actual_trace,vm['trace']);checks+=len(actual_trace)
        self.assertEqual(done[-1][1],fault)
        self.assertEqual(done[-1][3:7],(status,int(not fault),outer,vm['inner']));checks+=5
        if not fault:
            support=[] if proximal else expected.support
            self.assertEqual((int(metadata[-1][6]),int(metadata[-1][7]),int(metadata[-1][8],16)),(int(not proximal),len(support),pack(support,10)));checks+=3
        expected_builds=sum(asm.decode(package['program'][pc])['kind']==asm.ABI['kinds']['BUILD_B'] for pc in actual_trace)
        self.assertEqual(builds,expected_builds if sparse_forward or qr else 0)
        runs.append(dict(algorithm=algorithm,rows=rows,columns=n,zero=zero,r4=r4,scale_raw=scale,sparse_forward=sparse_forward,
            qr_profile=qr_profile,qr_panel_min_columns=package.get('qr_panel_min_columns', 0),
            operand_chains=bool(package.get('operand_chains', False)),
            factor_range_template=bool(package.get('qr_factor_range_template_enabled', False)),
            factor_energy_tap=bool(package.get('qr_factor_energy_tap_enabled', False)),
            required_kernel_revision=package.get('required_kernel_revision', 1),
            required_kernel_features=package.get('required_kernel_features', []),
            instruction_limit=instruction_limit,vm_limit=vm_limit,cycle_limit=cycle_limit,simulation_timeout=simulation_timeout,planted_seed=1909+rows+n if planted_seed is None else planted_seed,
            requested_outer_iterations=iterations,requested_sparsity=policy.sparsity if not proximal else None,
            accepted_support=list(expected.support),planted_support=planted_support,normalization_gain=normalization_gain,quality=quality,
            raw_phi_sha256=hashlib.sha256(np.asarray(raw_phi,dtype='<i4').tobytes()).hexdigest(),
            raw_y_sha256=hashlib.sha256(np.asarray(raw_y,dtype='<i4').tobytes()).hexdigest(),
            output_raw_x_sha256=hashlib.sha256(np.asarray(raw_x,dtype='<i4').tobytes()).hexdigest(),
            output_raw_r_sha256=hashlib.sha256(np.asarray(raw_r,dtype='<i4').tobytes()).hexdigest(),
            normalization_exponent=0,storage=package['candidate_storage'],policy=package['policy'],
            status=expected.status,outer_iterations=outer,inner_iterations=vm['inner'],
            cycles=cycles,job_cycles=done[-1][-1],comparisons=checks,retired_instructions=len(actual_trace),
            kernels=kernels,scalars=scalars,builds=builds,
            qr_reuse_enabled=bool(package.get('qr_reuse_enabled', False)),
            factor_init_calls=sum(asm.decode(package['program'][pc])['kind']==1 and asm.decode(package['program'][pc])['kernel']==13 for pc in actual_trace),
            factor_extend_calls=sum(asm.decode(package['program'][pc])['kind']==1 and asm.decode(package['program'][pc])['kernel']==19 for pc in actual_trace),
            simulator='Vivado xsim',
            cycle_profile=cycle_profile(trace.read_text()),
            comparison_kind='existing_fixed_algorithm_model_X_residual_support_status_counters_and_existing_program_VM_PC_trace',
            source_scope='real Householder QR outer program, no mocked services or LSQR fallback' if qr else 'six non-LS programs; no QR/LSQR RTL or mocked kernel/scalar service',
            commands=self.compiled.commands+result.commands,returncode=result.returncode,stdout=result.stdout,
            package_sha256=hashlib.sha256((package_path/'package.json').read_bytes()).hexdigest(),
            fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))
        (self.path/'evidence.json').write_text(json.dumps(runs,indent=2))

    def test_six_complete_programs_match_existing_fixed_models(self):
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):self.case(algorithm)

    def test_zero_measurement_all_six_programs(self):
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):self.case(algorithm,zero=True,iterations=2)

    def test_nonzero_maximum_full_pool_all_six_programs(self):
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):self.case(algorithm,rows=128,n=1024,iterations=2,inner_limit=64)

    def test_explicit_r1_r4_programs_and_inner_failure_policy(self):
        for r4 in (False,True):self.case('GP',rows=7,n=35,r4=r4,iterations=2)
        self.case('ADMM',inner_limit=1)



if __name__=='__main__':unittest.main()
