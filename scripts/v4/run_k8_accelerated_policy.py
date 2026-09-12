"""Run the numerical policy follow-up with independently checked exact reductions."""
from pathlib import Path
import sys,json,hashlib
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4 import diagnose_k8_quantization_policy as study
from scripts.v4.k8_exact_integer_acceleration import enabled,verify
from scripts.v4.diagnose_k8_quality import PROFILE,fixture
from models.v4.proximal import run,Policy
import numpy as np


def main():
    paths=[Path(__file__).resolve(),ROOT/'scripts/v4/k8_exact_integer_acceleration.py']
    before={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    count=verify(PROFILE)
    a,y,_,_=fixture(32,64,2005)
    for alg in ('FISTA','ADMM','PDHG'):
        p=Policy(max_iterations=4,inner_max_iterations=24)
        original=run(alg,a,y,p,PROFILE)
        with enabled():fast=run(alg,a,y,p,PROFILE)
        assert np.array_equal(original.x,fast.x) and np.array_equal(original.residual,fast.residual)
        assert original.events==fast.events and original.status==fast.status and original.trace==fast.trace
        count+=1
    proof=dict(status='PASS',comparisons=count,source_sha256=before,
        scope='Guarded dot/GEMV integer sums; original model rescale/clip/event handling. Random boundaries, int64 fallback and three4iteration complete model trajectories match original.')
    (study.OUT/'acceleration_verification.json').write_bytes((json.dumps(proof,indent=2)+'\n').encode())
    print('ACCELERATOR VERIFIED',count,flush=True)
    sys.argv=[sys.argv[0],'--fixed']
    with enabled():study.main()
    assert before=={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    output=study.OUT/'quantization_fixed.json';report=json.loads(output.read_text());report['acceleration']=proof
    report['source_sha256'].update(before);output.write_bytes((json.dumps(report,indent=2)+'\n').encode())
    for p in paths:
        dest=study.OUT/'quantization_sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())


if __name__=='__main__':main()
