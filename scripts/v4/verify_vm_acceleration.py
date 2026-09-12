"""Source-bound Python oracle proof and explicit wall-time diagnostic."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time
import unittest
import numpy as np
from compiler.v4.recovery_emit import PROFILE
from models.v4.fixed import Arithmetic
from verification.v4.exact_vm_gemv import BoundedGemv
from verification.v4 import test_vm_acceleration as tests

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/v4/vm_gemv_acceleration'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    sources=set()
    for folder in ('models/v4','compiler/v4'):
        sources.update(p.relative_to(ROOT).as_posix() for p in (ROOT/folder).glob('*.py'))
    sources.update(p.relative_to(ROOT).as_posix() for p in (ROOT/'config').glob('v4_*.json'))
    sources.update(['verification/v4/exact_vm_gemv.py','verification/v4/exact_model_context.py',
                    'verification/v4/recovery_program_vm.py','verification/v4/recovery_program_vm_reference.py',
                    'verification/v4/test_vm_acceleration.py','scripts/v4/verify_vm_acceleration.py',
                    'scripts/v4/run_program_vm.py','scripts/v4/k8_exact_integer_acceleration.py'])
    for module in tuple(sys.modules.values()):
        path=getattr(module,'__file__',None)
        if path and Path(path).resolve().is_relative_to(ROOT):
            sources.add(Path(path).resolve().relative_to(ROOT).as_posix())
    before={p:digest(ROOT/p) for p in sorted(sources)}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'before.json').write_text(json.dumps(before,indent=2))
    started=time.perf_counter()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(tests))
    elapsed=time.perf_counter()-started
    measurements=[]
    rng=np.random.default_rng(181819)
    a=rng.integers(-131072,131072,(128,1024),dtype=np.int64).astype(object)
    for trans in (False,True):
        v=rng.integers(-100,101,128 if trans else 1024,dtype=np.int64).astype(object)
        original=Arithmetic(PROFILE);accelerated=Arithmetic(PROFILE);backend=BoundedGemv(accelerated)
        t=time.perf_counter();prepared=backend.prepare(a);setup=time.perf_counter()-t
        original_times=[];fast_times=[]
        for _ in range(3):
            t=time.perf_counter();expected=original.matvec(a,v,PROFILE.coefficient,PROFILE.state,PROFILE.state,trans);original_times.append(time.perf_counter()-t)
            t=time.perf_counter();actual=backend.prepared_matvec(prepared,v,trans);fast_times.append(time.perf_counter()-t)
            assert np.array_equal(actual,expected) and original.events==accelerated.events
        measurements.append(dict(shape=[128,1024],transpose=trans,prepare_seconds=setup,
                                 reference_seconds=original_times,prepared_seconds=fast_times,
                                 scope='Python wall time for reused immutable operator, preparation separate; not RTL cycles'))
    changed=[p for p in before if digest(ROOT/p)!=before[p]]
    passed=result.wasSuccessful() and result.testsRun==5 and not result.skipped and not changed
    proof=dict(status='PASS' if passed else 'FAIL',tests=result.testsRun,failures=len(result.failures),
               errors=len(result.errors),skips=len(result.skipped),elapsed_seconds=elapsed,
               source_sha256=before,changed_sources=changed,records=tests.RECORDS,measurements=measurements,
               python=sys.version,numpy=np.__version__,rtl_runs=0,
               cancellation_scope='VM has no asynchronous cancel/stall interface; RTL lifecycle gates are unchanged')
    for p in before:
        dest=OUT/'source_snapshot'/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
    (OUT/'proof.json').write_text(json.dumps(proof,indent=2)+'\n')
    print(json.dumps({k:v for k,v in proof.items() if k not in ('source_sha256','records')},indent=2))
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
