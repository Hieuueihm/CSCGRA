"""Original fixture MP/GP candidate budget64; no algorithm substitution."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import fixture,PROFILE,assess,digest
from scripts.v4.k8_exact_integer_acceleration import enabled
from models.v4.recovery import Policy,run
from models.v4.fixed import Format

def main():
    paths=[Path(__file__).resolve(),ROOT/'scripts/v4/diagnose_k8_quality.py',ROOT/'scripts/v4/k8_exact_integer_acceleration.py']+sorted((ROOT/'models/v4').glob('*.py'))
    before={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    out=ROOT/'reports/v4/k8_quality_policy_20260909/mp_gp64';out.mkdir(parents=True,exist_ok=True)
    a,y,x,meta=fixture(64,256,2229);rows=[]
    for alg in ('MP','GP'):
        p=Policy(8,max_iterations=64,residual_atol=1/2048,ls_normal_rtol=1e-4)
        f=assess(run(alg,a,y,p),a,y,x,p)
        with enabled():q=assess(run(alg,a,y,p,PROFILE,solution_format=Format(24,20),ls_solver='lsqr'),a,y,x,p)
        row=dict(algorithm=alg,policy=p.__dict__,fixture=meta,floating=f,fixed=q,nmse_ratio=q['nmse']/f['nmse'],quality_pass=max(q['nmse'],f['nmse'])<=.01 and q['nmse']/f['nmse']<=1.1 and not any(q['events'].values()))
        rows.append(row);print(json.dumps(row),flush=True)
    assert before=={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    (out/'report.json').write_bytes((json.dumps(dict(cases=rows,source_sha256=before,source_stable=True,scope='No LS calls in MP/GP; unchanged GP restricted-gradient equation. Budget64 allows at most64 accepted support indices, fitsM64. Original fixture only.'),indent=2)+'\n').encode())
    for p in paths:
        dest=out/'sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())

if __name__=='__main__':main()
