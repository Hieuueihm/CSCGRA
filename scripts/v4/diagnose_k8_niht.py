"""Explicit NIHT candidate; no changes to fixed-step IHT or production models.

Reference: Blumensath and Davies, Normalised Iterative Hard Thresholding,
https://www.pure.ed.ac.uk/ws/portalfiles/portal/17821481/BD_NIHT09.pdf
Equations13/14: restricted-gradient quotient, support-change line search.
Finite-point additions: stored-X24 proposals, checked events, bounded16 halvings,
and exact measured residual nonincrease even when the support is unchanged.
The paper's real-arithmetic convergence theorem is not claimed for this variant.
"""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.v4.diagnose_k8_quality import fixture,PROFILE,digest
from models.v4.recovery import FloatKernels,IntegerKernels,Policy,rank
from models.v4.fixed import Format
import numpy as np
import json
from fractions import Fraction

OUT=ROOT/'reports/v4/k8_quality_policy_20260909'


class StoredX(IntegerKernels):
    def store(self,value):
        return np.array([self.arithmetic.rescale(self.arithmetic.rescale(int(v),22,Format(24,20)),20,PROFILE.state) for v in value],dtype=object)


def niht(a,y,fixed=False,budget=128):
    tol=float(np.ceil(np.sqrt(len(y))))/16384
    p=Policy(8,max_iterations=budget,residual_atol=tol)
    b=StoredX(a,y,p,PROFILE) if fixed else FloatKernels(a,y,p)
    x=b.zeros(a.shape[1]);r=b.y.copy();support=[];trace=[];status='max_iterations';calls=0
    for iteration in range(budget):
        if b.done(r):status='residual_tolerance';break
        g=b.mv(r,True);calls+=1
        current=support if support else sorted(rank(g,8))
        direction=b.zeros(len(x));direction[current]=g[current]
        ag=b.mv(direction);calls+=1
        numerator,denominator=b.dot(direction,direction),b.dot(ag,ag)
        if numerator<=0 or denominator<=0:status='stationary';break
        mu=b.ratio(numerator,denominator);old_energy=b.dot(r,r)
        accepted=False
        for backtrack in range(17):
            tentative=b.add(x,b.scale(g,mu));next_support=sorted(rank(tentative,8))
            proposed=b.zeros(len(x));proposed[next_support]=tentative[next_support];proposed=b.store(proposed)
            delta=b.sub(proposed,x);ad=b.mv(delta);nr=b.sub(b.y,b.mv(proposed));calls+=2
            ed,e_ad,new_energy=b.dot(delta,delta),b.dot(ad,ad),b.dot(nr,nr)
            if any(b.events.values()):status='numeric_fault';break
            if ed==0:status='stationary';break
            sufficient=(int(mu)*int(e_ad)*16<=15*int(ed)*(1<<22)) if fixed else mu*e_ad<=15/16*ed
            if (next_support==current or sufficient) and new_energy<=old_energy:
                accepted=True;break
            mu=int(b.arithmetic.round_shift(int(mu),1)) if fixed else mu/2
        if not accepted:
            if status=='max_iterations':status='line_search_failed'
            break
        x,r,support=proposed,nr,next_support
        trace.append(dict(iteration=iteration,backtracks=backtrack,step=float(mu)/(1<<22) if fixed else float(mu),residual_energy=int(new_energy) if fixed else float(new_energy),support=support))
    if b.done(r):status='residual_tolerance'
    return dict(x=b.decode(x).tolist(),residual=b.decode(r).tolist(),support=support,status=status,events=b.events,iterations=len(trace),gemv_calls=calls,trace=trace)


def main():
    paths=[Path(__file__).resolve(),ROOT/'scripts/v4/diagnose_k8_quality.py']+sorted((ROOT/'models/v4').glob('*.py'))
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in paths};rows=[]
    for m,n in ((64,256),(32,64)):
        # No tuning; c=1/16, half-step, budget128 fixed before fresh seeds.
        for seed in (1909+m+n,9101,9102):
            a,y,x,meta=fixture(m,n,seed);floating=niht(a,y);fixed=niht(a,y,True)
            for result in (floating,fixed):
                nmse=float(np.sum((np.array(result['x'])-x)**2)/np.sum(x*x));result['nmse']=nmse;result['snr_db']=float(-10*np.log10(nmse))
            ratio=fixed['nmse']/floating['nmse']
            row=dict(m=m,n=n,fixture=meta,algorithm='NIHT_stored_X24_bounded',floating=floating,fixed=fixed,nmse_ratio=ratio,quality_pass=max(fixed['nmse'],floating['nmse'])<=.01 and ratio<=1.1)
            rows.append(row);print(json.dumps({k:v for k,v in row.items() if k not in ('floating','fixed')}|dict(float_snr=floating['snr_db'],fixed_snr=fixed['snr_db'],iterations=fixed['iterations'],status=fixed['status'])),flush=True)
            (OUT/'niht_progress.json').write_bytes((json.dumps(rows,indent=2)+'\n').encode())
    assert hashes=={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    report=dict(scope='Explicit normalized/backtracked IHT variant; new numerical candidate, no compiler/RTL qualification; distinct from fixed-step IHT and GP',reference='https://www.pure.ed.ac.uk/ws/portalfiles/portal/17821481/BD_NIHT09.pdf',c='1/16',halving='1/2',backtrack_limit=16,outer_limit=128,stop='stored-X residual norm <= ceil(sqrt(M))/16384; stationary/fault explicitly separate',cases=rows,source_sha256=hashes,source_stable=True)
    (OUT/'niht.json').write_bytes((json.dumps(report,indent=2)+'\n').encode())
    for p in paths:
        dest=OUT/'niht_sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())


if __name__=='__main__':main()
