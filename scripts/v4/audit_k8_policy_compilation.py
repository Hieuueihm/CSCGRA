"""Check deployable constants/images without changing production compiler or RTL."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import fixture,solve,assess,digest
from scripts.v4.diagnose_k8_quantization_policy import configured
from compiler.v4.recovery_emit import compile_recovery
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from models.v4.recovery import Policy
import numpy as np
from dataclasses import asdict
import json


def main():
    out=ROOT/'reports/v4/k8_quality_policy_20260909';rows=[]
    files=[Path(__file__).resolve()]+sorted((ROOT/'compiler/v4').glob('*.py'))+sorted((ROOT/'models/v4').glob('*.py'))+sorted((ROOT/'config').glob('v4_*interface.json'))
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in files}
    selected=json.loads((out/'quantization_float.json').read_text())['selected']
    for m,n in ((64,256),(32,64)):
        a,y,x,meta=fixture(m,n,1909+m+n)
        for alg in ('IHT','HTP','FISTA','ADMM','PDHG'):
            if alg in ('IHT','HTP'):
                candidates=[]
                for step in ((.2,.3,.4,.5) if alg=='IHT' else (.4,.6,.8,1.)):
                    p=Policy(8,max_iterations=128,step_size=step/np.max(np.sum(a*a,axis=0)),residual_atol=float(np.ceil(np.sqrt(m)))/16384)
                    scores=[]
                    for seed in (4101,4102,4103,4104):
                        ta,ty,tx,_=fixture(m,n,seed);scores.append(float(np.linalg.norm(solve(alg,ta,ty,p).residual)))
                    candidates.append((max(scores),step,p))
                _,_,p=min(candidates,key=lambda t:t[:2])
                f=assess(solve(alg,a,y,p),a,y,x,p);q=assess(solve(alg,a,y,p,True),a,y,x,p)
            else:p=configured(a,alg,selected[f'{m}:{alg}']);f=q=None
            try:
                package=compile_greedy_qr(alg,a,p,max_refinements=2) if alg=='HTP' else compile_recovery(alg,a,p,sparse_forward=alg=='IHT')
                compiled=dict(status='PASS',program_words=len(package['program']),vector_descriptors=len(package['vectors']),constants=len(package['constants']))
            except Exception as error:compiled=dict(status='FAIL',error=str(error))
            rows.append(dict(m=m,n=n,algorithm=alg,policy=asdict(p),compiler=compiled,floating=f,fixed=q,fixture=meta))
            print(json.dumps(rows[-1]),flush=True)
    assert hashes=={p.relative_to(ROOT).as_posix():digest(p) for p in files}
    (out/'compiler_policy_audit.json').write_bytes((json.dumps(dict(scope='Image construction only, no VM/xsim qualification. Greedy original cases rerun with dyadic residual threshold.',cases=rows,source_sha256=hashes,source_stable=True),indent=2)+'\n').encode())
    for p in files:
        dest=out/'compiler_policy_sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())


if __name__=='__main__':main()
