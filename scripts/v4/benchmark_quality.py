"""Source-bound quality-policy replay through the real Vivado recovery engine.

Run from an isolated snapshot. Each invocation archives all local Python/RTL
inputs before execution; the shared helper checks X/R/support/status/PC exactly.
"""
import os
for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS'):
    os.environ[key]='1'
import argparse,hashlib,json,shutil,sys,time,traceback,unittest
from pathlib import Path
import numpy as np
from compiler.v4.quality_policy import candidate_policy
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE
from models.v4.fixed import Arithmetic,Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import run as model_run
from verification.v4 import test_recovery_algorithms_rtl as helper
from verification.v4.exact_model_context import model_acceleration
from verification.v4.recovery_program_vm import execute as vm_execute
from verification.v4.recovery_program_vm_reference import execute as reference_vm_execute
from scripts.v4.benchmark_k8 import quality_comparison

ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
OBSERVED={}

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,indent=2,default=lambda v:v.tolist() if hasattr(v,'tolist') else v.item()),encoding='utf-8')
def canonical(v):return json.dumps(v,sort_keys=True,default=lambda x:x.tolist() if hasattr(x,'tolist') else x.item())
def raw_hash(values):return hashlib.sha256(np.asarray(values,dtype='<i4').tobytes()).hexdigest()
def imported_outside_snapshot(hashes):
    untracked=[]
    for module in tuple(sys.modules.values()):
        value=getattr(module,'__file__',None)
        if value and getattr(module,'__name__','').split('.')[0] in ('compiler','models','verification','scripts'):
            p=Path(value).resolve()
            if not p.is_relative_to(ROOT) or p.relative_to(ROOT).as_posix() not in hashes:untracked.append(str(p))
    return sorted(set(untracked))

def oracle_preflight(args,out,oracle_mode):
    """Prove the runner's HTP oracle choices before any RTL invocation."""
    algorithm='HTP'
    matrix=lfsr32_matrix(0x12345678,args.rows,args.columns,scale=args.scale).astype(int)/65536.
    policy=candidate_policy(algorithm,matrix)
    rng=np.random.default_rng(1909+args.rows+args.columns if args.seed is None else args.seed)
    support=sorted(map(int,rng.choice(args.columns,8,replace=False)))
    planted=np.zeros(args.columns);planted[support]=rng.uniform(.5,1.,size=8)*rng.choice([-1,1],size=8)
    analog=matrix@planted;planted*=.5/float(np.max(np.abs(analog)))
    y=np.rint((matrix@planted)*16384).astype(int)/16384.
    package=compile_greedy_qr(algorithm,matrix,policy,qr_profile='balanced')
    default_vm=reference_vm_execute(package,matrix,y,limit=1000000)
    accelerated_vm=vm_execute(package,matrix,y,limit=1000000,accelerate_gemv=True,gemv_stats={})
    if canonical(default_vm)!=canonical(accelerated_vm):raise AssertionError('optional VM backend changed HTP raw output or PC trace')
    original_methods=(Arithmetic.dot_raw,Arithmetic.matvec)
    fixed=model_run(algorithm,matrix,y,policy,PROFILE,ls_solver='qr',solution_format=Format(24,20),qr_max_refinements=2)
    with model_acceleration():
        accelerated_fixed=model_run(algorithm,matrix,y,policy,PROFILE,ls_solver='qr',solution_format=Format(24,20),qr_max_refinements=2)
    if (Arithmetic.dot_raw,Arithmetic.matvec)!=original_methods:raise AssertionError('model context leaked methods')
    if canonical(vars(fixed))!=canonical(vars(accelerated_fixed)):raise AssertionError('scoped model backend changed fixed HTP result')
    floating=model_run(algorithm,matrix,y,policy)
    signal=float(np.dot(planted,planted))
    def metrics(value):
        error=float(np.dot(np.asarray(value)-planted,np.asarray(value)-planted))
        return dict(nmse=error/signal,snr_db=None if error==0 else float(10*np.log10(signal/error)))
    quality=dict(fixed=metrics(fixed.x),floating=metrics(floating.x))
    quality.update(quality_comparison(quality))
    if not quality['threshold_pass']:raise AssertionError(quality)
    proof=dict(status='PASS',algorithm=algorithm,oracle_mode=oracle_mode,rtl_runs=0,
        policy=vars(policy),raw_phi_sha256=raw_hash(np.rint(matrix*65536)),raw_y_sha256=raw_hash(np.rint(y*16384)),
        vm_raw_x_sha256=raw_hash(default_vm['x']),vm_raw_residual_sha256=raw_hash(default_vm['residual']),
        vm_support=default_vm['support'],vm_status=default_vm['status'],vm_outer=default_vm['outer'],
        vm_inner=default_vm['inner'],vm_trace_sha256=hashlib.sha256(canonical(default_vm['trace']).encode()).hexdigest(),
        fixed_raw_x_sha256=raw_hash([round(float(v)*2**22) for v in fixed.x]),
        fixed_raw_residual_sha256=raw_hash([round(float(v)*2**22) for v in fixed.residual]),
        quality=quality,scope='Oracle-only preflight: same HTP candidate policy, raw VM outputs/PC trace and quality. No RTL execution.')
    dump(out/'oracle_preflight.json',proof)
    return proof

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--algorithms',nargs='+',required=True)
    parser.add_argument('--rows',type=int,default=64)
    parser.add_argument('--columns',type=int,default=256)
    parser.add_argument('--scale',type=int,default=8192)
    parser.add_argument('--seed',type=int)
    parser.add_argument('--report',required=True)
    parser.add_argument('--fast-elaboration',action='store_true',help='Vivado debug off/O3; simulation runtime only')
    parser.add_argument('--accelerated-oracle',action='store_true',help='Use only the proven optional VM GEMV and scoped fixed-model integer backends')
    parser.add_argument('--oracle-preflight',action='store_true',help='Check HTP oracle equivalence and quality without invoking RTL; requires --accelerated-oracle')
    args=parser.parse_args()
    out=ROOT/'reports/v4'/args.report
    if out.exists():raise ValueError('choose a new immutable report directory')
    out.mkdir(parents=True)
    files=[]
    for folder in ('compiler/v4','models/v4','verification/v4','scripts/v4','rtl/v4','config'):
        files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.py','.sv','.vh','.json','.f') and '__pycache__' not in p.parts)
    files.extend(ROOT/f'{p}/__init__.py' for p in ('compiler','models','verification','scripts') if (ROOT/f'{p}/__init__.py').exists())
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in sorted(set(files))}
    for name in hashes:
        dest=out/'source_snapshot'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,dest)
    oracle_mode=dict(
        vm_gemv='optional_bounded_c18_s27_acc64' if args.accelerated_oracle else 'default_arithmetic_matvec',
        fixed_model='scoped_integer_reductions' if args.accelerated_oracle else 'default_model_methods',
        floating_model='default_model_methods',
        enabled=bool(args.accelerated_oracle),
        scope='VM GEMV plus fixed-model run/proximal_run only; no RTL, numerical policy, or floating-model substitution')
    dump(out/'manifest.json',dict(execution_root=str(ROOT),arguments=vars(args),oracle_mode=oracle_mode,sources=hashes))
    if args.oracle_preflight:
        if not args.accelerated_oracle:raise ValueError('--oracle-preflight requires --accelerated-oracle')
        proof=oracle_preflight(args,out,oracle_mode)
        changed=[name for name,value in hashes.items() if digest(ROOT/name)!=value]
        untracked=imported_outside_snapshot(hashes)
        if changed or untracked:raise AssertionError(dict(changed_sources=changed,untracked_imports=untracked))
        summary=dict(status='PASS',cases=[],expected_cases=0,elapsed_seconds=0.0,failures=0,errors=0,
            changed_sources=changed,untracked_imports=untracked,source_sha256=hashes,source_hashes_stable=True,
            oracle_mode=oracle_mode,oracle_preflight=proof,
            scope='Oracle-only preflight; no RTL execution, cycle or timing claim')
        dump(out/'summary.json',summary)
        print(out,flush=True)
        return 0
    if args.fast_elaboration:
        original_compile=helper.compile_rtl
        def compile_fast(*a,**kw):return original_compile(*a,**kw,debug='off',optimization=3)
        helper.compile_rtl=compile_fast
    if args.accelerated_oracle:
        original_execute=helper.execute
        def execute_accelerated(*a,**kw):
            if 'accelerate_gemv' in kw:raise TypeError('quality runner owns accelerate_gemv mode')
            return original_execute(*a,**kw,accelerate_gemv=True)
        helper.execute=execute_accelerated
    for name in ('run','proximal_run'):
        original=getattr(helper,name)
        def capture(*a,_fn=original,**kw):
            profile=a[4] if len(a)>4 else kw.get('profile')
            if args.accelerated_oracle and profile is not None:
                with model_acceleration():result=_fn(*a,**kw)
            else:result=_fn(*a,**kw)
            OBSERVED['fixed' if profile is not None else 'floating']=result
            return result
        setattr(helper,name,capture)
    class QualityPrograms(unittest.TestCase):
        run_records=RUNS
        setUpClass=classmethod(helper.RecoveryAlgorithmsRtlTests.setUpClass.__func__)
        def test_quality(self):
            matrix=lfsr32_matrix(0x12345678,args.rows,args.columns,scale=args.scale).astype(int)/65536.
            for algorithm in args.algorithms:
                with self.subTest(algorithm=algorithm):
                    OBSERVED.clear()
                    try:
                        policy=candidate_policy(algorithm,matrix)
                        helper.RecoveryAlgorithmsRtlTests.case(self,algorithm,rows=args.rows,n=args.columns,
                            policy_override=policy,planted=True,planted_seed=args.seed,sparsity=8,
                            scale_override=args.scale,sparse_forward=algorithm in ('MP','GP','IHT'),
                            qr_profile='balanced',instruction_limit=1000000,vm_limit=1000000,
                            cycle_limit=50000000,simulation_timeout=3600)
                    except Exception:
                        print(f'QUALITY FAILURE {algorithm} M{args.rows} N{args.columns}',flush=True)
                        traceback.print_exc()
                        raise
                    record=RUNS[-1]
                    fixed=OBSERVED['fixed'];floating=OBSERVED['floating']
                    record.update(fixed_numeric_events=fixed.events,fixed_model_trace=fixed.trace,
                        fixed_solver_trace=fixed.solver_trace,floating_model_trace=floating.trace,
                        fixture_seed=args.seed if args.seed is not None else 1909+args.rows+args.columns,
                        qr_profile='balanced',quality_policy_authority='config/v4_quality_policy.json',
                        oracle_mode=oracle_mode)
                    record['quality'].update(quality_comparison(record['quality']))
                    dump(out/'progress.json',RUNS)
                    print(f"QUALITY {algorithm} M{args.rows} N{args.columns} cycles={record['job_cycles']} outer={record['outer_iterations']} SNR={record['quality']['fixed']['snr_db']} pass={record['quality']['threshold_pass']}",flush=True)
                    self.assertTrue(record['quality']['threshold_pass'],record['quality'])
                    self.assertFalse(any(fixed.events.values()),fixed.events)
                    self.assertIn(fixed.status,('max_iterations','residual_tolerance','paper_iteration_limit','residual_not_decreased'))
    started=time.monotonic()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(QualityPrograms))
    changed=[name for name,value in hashes.items() if digest(ROOT/name)!=value]
    untracked=imported_outside_snapshot(hashes)
    passed=result.wasSuccessful() and len(RUNS)==len(args.algorithms) and not changed and not untracked and not result.skipped
    summary=dict(status='PASS' if passed else 'FAIL',cases=RUNS,expected_cases=len(args.algorithms),
        elapsed_seconds=time.monotonic()-started,failures=len(result.failures),errors=len(result.errors),
        changed_sources=changed,untracked_imports=untracked,source_sha256=hashes,
        source_hashes_stable=not changed,oracle_mode=oracle_mode,
        scope='Real xsim loaded programs; changed numerical policy, not same-work baseline speedup; no board timing or application dataset claim')
    dump(out/'summary.json',summary)
    if hasattr(QualityPrograms,'path'):shutil.copytree(QualityPrograms.path,out/'execution',dirs_exist_ok=True)
    print(out,flush=True)
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
