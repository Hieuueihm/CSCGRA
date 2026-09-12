"""Explicit measurement-budget tradeoff, not replacement of original fixtures."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import solve,assess,digest
from scripts.v4.diagnose_k8_quantization_policy import configured
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy
import numpy as np
from dataclasses import asdict
import json

OUT=ROOT/'reports/v4/k8_quality_policy_20260909'


def fixture(m,n,seed):
    scale=round(65536/np.sqrt(m))
    a=lfsr32_matrix(0x12345678,m,n,scale=scale).astype(int)/65536.
    rng=np.random.default_rng(seed);support=sorted(map(int,rng.choice(n,8,replace=False)))
    x=np.zeros(n);x[support]=rng.uniform(.5,1,8)*rng.choice([-1,1],8)
    y=a@x;gain=.5/np.max(np.abs(y));x*=gain;y=np.rint(y*gain*16384)/16384
    return a,y,x,dict(seed=seed,scale_raw=scale,support=support,gain=gain)


def main():
    files=[Path(__file__).resolve(),ROOT/'scripts/v4/diagnose_k8_quality.py',ROOT/'scripts/v4/diagnose_k8_quantization_policy.py']+sorted((ROOT/'models/v4').glob('*.py'))
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in files}
    records=[];training=[];operators=[]
    for m,n in ((64,128),(128,256)):
        a,_,_,_=fixture(m,n,4101);g=a.T@a;norm=float(np.max(np.diag(g)));np.fill_diagonal(g,0)
        operators.append(dict(m=m,n=n,coherence=float(np.max(np.abs(g)))/norm,rank=int(np.linalg.matrix_rank(a)),lipschitz=float(np.linalg.norm(a,2)**2)))
        for alg in ('IHT','HTP','FISTA','ADMM','PDHG'):
            choice=.4
            if alg in ('IHT','HTP'):
                scores=[]
                for step in ((.2,.3,.4,.5) if alg=='IHT' else (.4,.6,.8,1.)):
                    residuals=[]
                    for seed in (4101,4102,4103,4104):
                        a,y,x,meta=fixture(m,n,seed)
                        p=Policy(8,max_iterations=128,step_size=step/norm,residual_atol=float(np.ceil(np.sqrt(m)))/16384)
                        q=assess(solve(alg,a,y,p),a,y,x,p);residuals.append(q['residual_norm'])
                        training.append(dict(m=m,algorithm=alg,step=step,seed=seed,residual=q['residual_norm']))
                    scores.append((max(residuals),step))
                choice=min(scores)[1]
            # These seeds are new to every earlier study.
            for seed in (8101,8102):
                a,y,x,meta=fixture(m,n,seed)
                p=Policy(8,max_iterations=128,step_size=choice/norm,residual_atol=float(np.ceil(np.sqrt(m)))/16384) if alg in ('IHT','HTP') else configured(a,alg,512)
                f=assess(solve(alg,a,y,p),a,y,x,p)
                # Bounded independent integer check for both greedy algorithms;
                # proximal measurement-regime rows remain float exploration.
                q=assess(solve(alg,a,y,p,True),a,y,x,p) if alg in ('IHT','HTP') and f['nmse']<=.01 else None
                ratio=None if q is None else q['nmse']/f['nmse']
                records.append(dict(m=m,n=n,algorithm=alg,fixture=meta,policy=asdict(p),floating=f,fixed=q,
                    support_condition=float(np.linalg.cond(a[:,meta['support']])),nmse_ratio=ratio,
                    quality_pass=None if q is None else max(q['nmse'],f['nmse'])<=.01 and ratio<=1.1))
                print(json.dumps(records[-1]),flush=True)
    # Independent exact-measurement l1 diagnostic on the disclosed difficult
    # old geometry/seed, not a replacement recovery algorithm or policy input.
    from scripts.v4.diagnose_k8_quality import fixture as old_fixture
    a,y,x,meta=old_fixture(32,64,7102)
    from models.v4.proximal import Policy as PP, run as prun
    candidate=prun('FISTA',a,a@x,PP(regularization=1e-5,max_iterations=8192,step_size=.95/np.linalg.norm(a,2)**2)).x
    alternative=candidate+a.T@np.linalg.solve(a@a.T,a@x-a@candidate)
    diagnostic=dict(scope='Post-hoc feasible l1 witness, not proof of optimum; never policy selection',
        true_l1=float(np.sum(np.abs(x))),alternative_l1=float(np.sum(np.abs(alternative))),
        smaller_l1=bool(np.sum(np.abs(alternative))<np.sum(np.abs(x))-1e-8),
        alternative_nmse=float(np.sum((alternative-x)**2)/np.sum(x*x)),
        exact_measurement_residual=float(np.linalg.norm(a@alternative-a@x)),alternative=alternative.tolist())
    assert hashes=={p.relative_to(ROOT).as_posix():digest(p) for p in files}
    out=dict(scope='Predeclared M64/N128/K8 and M128/N256/K8 unit-norm operator regime; different measurement budget, never replaces original benchmark',training_seeds=[4101,4102,4103,4104],holdout_seeds=[8101,8102],operators=operators,training=training,cases=records,l1_diagnostic=diagnostic,source_sha256=hashes,source_stable=True)
    (OUT/'measurement_regime.json').write_bytes((json.dumps(out,indent=2)+'\n').encode())
    for p in files:
        dest=OUT/'measurement_sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())


if __name__=='__main__':main()
