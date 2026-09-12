"""Paired empirical generator comparison; no RIP or hardware cost claims."""
from __future__ import annotations
from collections import Counter
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from models.v4.generated_operator import generated_matrix
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import ALGORITHMS, Policy, run
from models.v4.quality import metrics
from scripts.v4.numeric_screen import digest, sanitized


def describe(a):
    signs=a>0
    packed=np.packbits(signs,axis=0)
    groups=Counter(min(packed[:,j].tobytes(),np.packbits(~signs[:,j]).tobytes()) for j in range(a.shape[1]))
    gram=(a.T@a)/(np.linalg.norm(a,axis=0)[:,None]*np.linalg.norm(a,axis=0)[None,:])
    off=gram[np.triu_indices(a.shape[1],1)]
    return {'positive_fraction':float(signs.mean()),
        'duplicate_or_negated_pairs':sum(v*(v-1)//2 for v in groups.values()),
        'mutual_coherence':float(np.max(np.abs(off))),
        'off_diagonal_mean':float(np.mean(off)),
        'off_diagonal_abs_p95':float(np.quantile(np.abs(off),.95))}


def main():
    seeds=[23,47,101]; m,n=128,1024
    path=ROOT/'reports/v4/generator_comparison.json'
    sources=[Path(__file__),ROOT/'models/v4/generated_operator.py',ROOT/'models/v4/lfsr_operator.py',
             ROOT/'models/v4/recovery.py',ROOT/'models/v4/quality.py',ROOT/'scripts/v4/numeric_screen.py']
    hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
    report={'scope':'paired_empirical_generated_Phi_float_recovery_calibration','complete':False,
        'seeds':seeds,'M':m,'N':n,'scale':1/math.sqrt(m),'source_sha256':hashes,
        'generator_ids':['threefry2x32_20_revision1','lfsr32_v2_taps_columnmajor_revision1'],
        'matrix_quality':[],'recovery_rows':[],'selected_generator':None,
        'RIP_proven':False,'synthesis_or_throughput_measured':False,
        'shared_trial_policy':'same x/support and standardized noise direction; y recomputed with each A; paired by seed/trial',
        'absolute_synthetic_SNR_floor_db_diagnostic':20,
        'no_seed_filtering':True}
    def save(): path.write_text(json.dumps(sanitized(report),indent=2,allow_nan=False)+'\n',encoding='utf-8')
    for family,factory in [('threefry',generated_matrix),('lfsr32',lfsr32_matrix)]:
        for seed in seeds:
            a=factory(seed,m,n,1/math.sqrt(m)); spectral=float(np.linalg.norm(a,2)**2)
            q={'generator':family,'seed':seed,'operator_sha256':digest(a),**describe(a),'sampled_supports':[]}
            for size in [8,32,96]:
                cond=[]; mins=[]; maxs=[]
                rng=np.random.default_rng(seed+size*100)
                for _ in range(8):
                    ids=rng.choice(n,size,replace=False)
                    singular=np.linalg.svd(a[:,ids],compute_uv=False)
                    cond.append(float(singular[0]/singular[-1])); mins.append(float(singular[-1]**2));maxs.append(float(singular[0]**2))
                q['sampled_supports'].append({'S':size,'samples':8,'max_condition':max(cond),
                    'min_sigma_squared':min(mins),'max_sigma_squared':max(maxs),
                    'empirical_delta_lower_bound':max(1-min(mins),max(maxs)-1),
                    'not_RIP_upper_bound':True})
            report['matrix_quality'].append(q); save()
            for sparsity in [8,32]:
                for trial in [0,1]:
                    rng=np.random.default_rng(seed*100000+sparsity*100+trial)
                    support=rng.choice(n,sparsity,replace=False)
                    x=np.zeros(n);x[support]=rng.uniform(.2,.5,sparsity)*rng.choice([-1,1],sparsity)
                    clean=a@x;direction=rng.normal(size=m);noise=direction/np.linalg.norm(direction)*np.linalg.norm(clean)*10**(-30/20)
                    y=clean+noise
                    for algorithm in ALGORITHMS:
                        p=Policy(sparsity,max_iterations=sparsity if algorithm in ('OMP','GOMP') else 32,
                                 step_size=.9/spectral,residual_atol=1e-6)
                        r=run(algorithm,a,y,p)
                        quality=metrics(x,r.x)
                        report['recovery_rows'].append({'generator':family,'seed':seed,'sparsity':sparsity,'trial':trial,
                            'algorithm':algorithm,'policy':asdict(p),'status':r.status,
                            'truth_sha256':digest(x),'noise_direction_sha256':digest(direction),'measurement_sha256':digest(y),
                            'quality':quality,'synthetic_snr20_pass':quality['snr_db']>=20,
                            'top_k_support_recall':len(set(np.argsort(-np.abs(r.x),kind='stable')[:sparsity])&set(support))/sparsity})
                    save()
            print(f'{family} seed{seed}: coherence={q["mutual_coherence"]:.6f}',flush=True)
    report['summary']={f:{str(k):{'rows':sum(r['generator']==f and r['sparsity']==k for r in report['recovery_rows']),
        'snr20_pass':sum(r['synthetic_snr20_pass'] for r in report['recovery_rows'] if r['generator']==f and r['sparsity']==k)}
        for k in [8,32]} for f in ['threefry','lfsr32']}
    report['source_unchanged_during_run']=all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
    report['complete']=True;save();print(json.dumps(report['summary']),flush=True)
    if not report['source_unchanged_during_run']: raise RuntimeError('Source changed during run')


if __name__=='__main__': main()
