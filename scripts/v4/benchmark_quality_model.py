"""Immutable fixed-versus-float quality study without RTL execution.

The optional integer reductions are scoped to each fixed model call. Floating
reference calls retain the model's normal arithmetic. This records quality by
seed and does not rank algorithms or claim RTL cycles.
"""
import argparse
from dataclasses import replace
import hashlib
import json
import os
import shutil
import sys
import time
from pathlib import Path
for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS'):
    os.environ[key]='1'
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from compiler.v4.quality_policy import candidate_policy
from compiler.v4.recovery_emit import PROFILE
from models.v4.fixed import Arithmetic,Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.proximal import run as proximal_run
from verification.v4.exact_model_context import model_acceleration
from scripts.v4.benchmark_k8 import quality_comparison

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def dump(path,value):path.write_text(json.dumps(value,indent=2,default=lambda x:x.tolist() if hasattr(x,'tolist') else x.item()),encoding='utf-8')
def raw_hash(values):return hashlib.sha256(np.asarray(values,dtype='<i4').tobytes()).hexdigest()

def freeze_sources(out):
    files=[]
    for folder in ('compiler/v4','models/v4','verification/v4','scripts/v4','config'):
        files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.py','.json') and '__pycache__' not in p.parts)
    files.extend(ROOT/f'{name}/__init__.py' for name in ('compiler','models','verification','scripts') if (ROOT/f'{name}/__init__.py').exists())
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in sorted(set(files))}
    for name in hashes:
        target=out/'source_snapshot'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,target)
    return hashes

def fixture(rows,columns,scale,seed):
    matrix=lfsr32_matrix(0x12345678,rows,columns,scale=scale).astype(int)/65536.
    rng=np.random.default_rng(seed)
    support=sorted(map(int,rng.choice(columns,8,replace=False)))
    planted=np.zeros(columns);planted[support]=rng.uniform(.5,1.,size=8)*rng.choice([-1,1],size=8)
    analog=matrix@planted
    gain=.5/float(np.max(np.abs(analog)))
    planted*=gain
    raw_y=np.rint(analog*gain*16384).astype(int)
    return matrix,raw_y/16384.,planted,support,gain

def solve(algorithm,matrix,y,policy,profile):
    return proximal_run(algorithm,matrix,y,policy,profile)

def study_case(algorithm,rows,columns,scale,seed,authority,outer_budget):
    matrix,y,planted,planted_support,gain=fixture(rows,columns,scale,seed)
    policy=candidate_policy(algorithm,matrix,authority=authority)
    if outer_budget is not None:policy=replace(policy,max_iterations=outer_budget)
    before=(Arithmetic.dot_raw,Arithmetic.matvec)
    with model_acceleration():fixed=solve(algorithm,matrix,y,policy,PROFILE)
    if (Arithmetic.dot_raw,Arithmetic.matvec)!=before:raise AssertionError('model acceleration context leaked methods')
    floating=solve(algorithm,matrix,y,policy,None)
    signal=float(np.dot(planted,planted))
    def metrics(value):
        error=float(np.dot(np.asarray(value)-planted,np.asarray(value)-planted))
        return dict(nmse=error/signal,snr_db=None if error==0 else float(10*np.log10(signal/error)))
    quality=dict(fixed=metrics(fixed.x),floating=metrics(floating.x))
    quality.update(quality_comparison(quality))
    allowed=('max_iterations','residual_tolerance','paper_iteration_limit','residual_not_decreased')
    if fixed.status not in allowed or floating.status not in allowed:raise AssertionError(dict(fixed=fixed.status,floating=floating.status))
    if any(fixed.events.values()):raise AssertionError(dict(fixed_events=fixed.events))
    return dict(seed=seed,planted_support=planted_support,normalization_gain=gain,policy=vars(policy),outer_budget_override=outer_budget,
        raw_phi_sha256=raw_hash(np.rint(matrix*65536)),raw_y_sha256=raw_hash(np.rint(y*16384)),
        fixed_raw_x_sha256=raw_hash([round(float(v)*2**22) for v in fixed.x]),
        fixed_raw_residual_sha256=raw_hash([round(float(v)*2**22) for v in fixed.residual]),
        floating_raw_x_sha256=raw_hash([round(float(v)*2**22) for v in floating.x]),
        fixed_status=fixed.status,floating_status=floating.status,fixed_events=fixed.events,
        floating_events=floating.events,quality=quality)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--algorithm',choices=('FISTA','PDHG','ADMM'),required=True)
    parser.add_argument('--seeds',type=int,nargs='+',required=True)
    parser.add_argument('--rows',type=int,default=64)
    parser.add_argument('--columns',type=int,default=256)
    parser.add_argument('--scale',type=int,default=8192)
    parser.add_argument('--policy-authority',default='config/v4_quality_policy.json')
    parser.add_argument('--outer-budget',type=int,help='ADMM study-only outer-iteration override; does not edit the candidate policy file')
    parser.add_argument('--report',required=True)
    args=parser.parse_args()
    if args.outer_budget is not None and (args.algorithm!='ADMM' or args.outer_budget<1):
        parser.error('--outer-budget requires ADMM and an integer >=1')
    authority=Path(args.policy_authority)
    authority=(ROOT/authority).resolve() if not authority.is_absolute() else authority.resolve()
    if not authority.is_relative_to(ROOT):raise ValueError('policy authority must be inside this isolated snapshot')
    out=ROOT/'reports/v4'/args.report
    if out.exists():raise ValueError('choose a new immutable report directory')
    out.mkdir(parents=True)
    hashes=freeze_sources(out)
    started=time.monotonic();cases=[]
    for seed in args.seeds:
        try:
            record=study_case(args.algorithm,args.rows,args.columns,args.scale,seed,authority,args.outer_budget)
            cases.append(record);dump(out/'progress.json',cases)
            print(f"MODEL QUALITY {args.algorithm} seed={seed} fixed={record['quality']['fixed']['snr_db']} float={record['quality']['floating']['snr_db']} pass={record['quality']['threshold_pass']}",flush=True)
            if not record['quality']['threshold_pass']:raise AssertionError(record['quality'])
        except Exception:
            print(f'MODEL QUALITY FAILURE {args.algorithm} seed={seed}',flush=True)
            raise
    changed=[name for name,value in hashes.items() if digest(ROOT/name)!=value]
    untracked=[]
    for module in tuple(sys.modules.values()):
        path=getattr(module,'__file__',None)
        if path and getattr(module,'__name__','').split('.')[0] in ('compiler','models','verification','scripts'):
            source=Path(path).resolve()
            if not source.is_relative_to(ROOT) or source.relative_to(ROOT).as_posix() not in hashes:untracked.append(str(source))
    passed=len(cases)==len(args.seeds) and not changed and not untracked
    summary=dict(status='PASS' if passed else 'FAIL',arguments=vars(args),policy_authority=str(authority.relative_to(ROOT)),
        execution_environment=dict(thread_settings={key:os.environ[key] for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS')}),
        oracle_mode=dict(fixed_model='scoped_integer_reductions',floating_model='default_model_methods',rtl_runs=0),
        cases=cases,expected_cases=len(args.seeds),elapsed_seconds=time.monotonic()-started,
        changed_sources=changed,untracked_imports=sorted(set(untracked)),source_sha256=hashes,
        source_hashes_stable=not changed,scope='Numerical policy study by independent seeds; no RTL execution, cycle ranking, production bit lock, or board timing claim')
    dump(out/'summary.json',summary);print(out,flush=True)
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
