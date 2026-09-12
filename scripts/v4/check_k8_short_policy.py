"""Bounded fixed/float policy checks; unchanged models, guarded exact reductions."""
from pathlib import Path
import sys,json,time,argparse
from dataclasses import asdict
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import fixture,solve,assess,digest
from scripts.v4.diagnose_k8_quantization_policy import configured
from scripts.v4.k8_exact_integer_acceleration import enabled
import numpy as np

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--algorithm',required=True,choices=['ADMM','PDHG'])
    parser.add_argument('--budgets',nargs='+',type=int,required=True)
    parser.add_argument('--seeds',nargs='+',type=int,required=True)
    parser.add_argument('--name',required=True);args=parser.parse_args()
    paths=[Path(__file__).resolve(),ROOT/'scripts/v4/diagnose_k8_quality.py',ROOT/'scripts/v4/diagnose_k8_quantization_policy.py',ROOT/'scripts/v4/k8_exact_integer_acceleration.py']+sorted((ROOT/'models/v4').glob('*.py'))
    before={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    out=ROOT/'reports/v4/k8_quality_policy_20260909'/args.name;out.mkdir(parents=True,exist_ok=True)
    rows=[];started=time.time()
    for budget in args.budgets:
        for seed in args.seeds:
            a,y,x,meta=fixture(64,256,seed);policy=configured(a,args.algorithm,budget)
            floating=assess(solve(args.algorithm,a,y,policy),a,y,x,policy)
            with enabled():fixed=assess(solve(args.algorithm,a,y,policy,True),a,y,x,policy)
            ratio=fixed['nmse']/floating['nmse'];loss=float(10*np.log10(ratio))
            row=dict(algorithm=args.algorithm,fixture=meta,policy=asdict(policy),floating=floating,fixed=fixed,nmse_ratio=ratio,snr_loss_db=loss,quality_pass=min(fixed['snr_db'],floating['snr_db'])>=20 and ratio<=1.1 and loss<=.5 and not any(fixed['events'].values()))
            rows.append(row);print(json.dumps(row),flush=True)
            (out/'progress.json').write_bytes((json.dumps(rows,indent=2)+'\n').encode())
    assert before=={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    report=dict(cases=rows,source_stable=True,source_sha256=before,elapsed_seconds=time.time()-started,acceleration='Study-only exact guarded int64; see acceleration_verification.json 72 comparisons. No RTL cycle claim.')
    (out/'report.json').write_bytes((json.dumps(report,indent=2)+'\n').encode())
    for p in paths:
        dest=out/'sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())

if __name__=='__main__':main()
