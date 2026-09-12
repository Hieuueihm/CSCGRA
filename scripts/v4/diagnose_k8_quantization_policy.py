"""Predeclared quantization-aware proximal policy; no production-source edits."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import fixture, solve, assess, digest, PROFILE
from models.v4.proximal import Policy
import numpy as np
import json
import argparse
import time

OUT=ROOT/'reports/v4/k8_quality_policy_20260909'


def configured(a,algorithm,budget):
    l=float(np.linalg.norm(a,2)**2)
    tau_fista=.95/l
    # Same LASSO objective for all three algorithms. Threshold at >=16 output
    # LSBs in the smallest-step algorithm bounds single-store threshold error
    # to <=1/32 of shrinkage; this is not a convergence/error theorem.
    lam=max(.01,16/16384/tau_fista)
    return Policy(regularization=lam,max_iterations=budget,
        step_size=tau_fista if algorithm=='FISTA' else 8.,
        pd_sigma=.90/(8*l),admm_rho=.3,inner_max_iterations=64,inner_rtol=1e-4)


def main():
    from dataclasses import asdict
    parser=argparse.ArgumentParser();parser.add_argument('--fixed',action='store_true');args=parser.parse_args()
    paths=[Path(__file__).resolve(),ROOT/'scripts/v4/diagnose_k8_quality.py']+sorted((ROOT/'models/v4').glob('*.py'))
    before={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    result=[];selected={};training=[];started=time.time()
    for m,n in ((64,256),(32,64)):
        for algorithm in ('FISTA','ADMM','PDHG'):
            # Stopping budget selected from observable KKT stationarity on four
            # training truths, never their coefficient error or true support.
            budget=1024
            for count in (128,256,512,1024):
                worst=0.
                for seed in (4101,4102,4103,4104):
                    a,y,x,meta=fixture(m,n,seed);p=configured(a,algorithm,count)
                    q=assess(solve(algorithm,a,y,p),a,y,x,p)
                    threshold=max(4/16384, .05*p.regularization)
                    worst=max(worst,q['kkt_inf']/threshold)
                    training.append(dict(m=m,algorithm=algorithm,seed=seed,budget=count,kkt_inf=q['kkt_inf'],threshold=threshold,status=q['status']))
                if worst<=1:budget=count;break
            selected[f'{m}:{algorithm}']=budget
            # 7101/7102 have not been consulted in either earlier policy screen.
            for seed in (1909+m+n,7101,7102):
                a,y,x,meta=fixture(m,n,seed);p=configured(a,algorithm,budget)
                floating=assess(solve(algorithm,a,y,p),a,y,x,p)
                # Bounded fixed follow-up: original + first fresh seed. Second
                # seed remains float-only and is explicitly not fixed-qualified.
                fixed=assess(solve(algorithm,a,y,p,True),a,y,x,p) if args.fixed and seed!=7102 else None
                ratio=None if fixed is None else fixed['nmse']/floating['nmse']
                loss=None if ratio is None else float(10*np.log10(ratio))
                row=dict(m=m,n=n,algorithm=algorithm,fixture=meta,policy=asdict(p),floating=floating,fixed=fixed,nmse_ratio=ratio,snr_loss_db=loss,
                    quality_pass=None if fixed is None else max(fixed['nmse'],floating['nmse'])<=.01 and ratio<=1.1 and loss<=.5)
                result.append(row);print(json.dumps(row),flush=True)
                (OUT/'quantization_progress.json').write_bytes((json.dumps(dict(cases=result,selected=selected),indent=2)+'\n').encode())
    assert before=={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    report=dict(policy_scope='Same fixed-step FISTA, primal-dual PDHG and shifted-CG ADMM. Common regularization derived from D18 store precision; training KKT budget selection. Runtime outer KKT stop not currently implemented.',
        training=training,selected=selected,cases=result,elapsed_seconds=time.time()-started,source_sha256=before,source_stable=True)
    (OUT/('quantization_fixed.json' if args.fixed else 'quantization_float.json')).write_bytes((json.dumps(report,indent=2)+'\n').encode())
    for p in paths:
        dest=OUT/'quantization_sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())


if __name__=='__main__':main()
