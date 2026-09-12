"""Numerical-only policy study on preserved K8 fixtures; never invokes RTL tools."""
from pathlib import Path
import os
for key in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ[key] = '1'
import argparse
from dataclasses import asdict
import hashlib
import json
import sys
import time
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy, run
from models.v4.proximal import Policy as ProxPolicy, run as prox_run
from models.v4.fixed import Format, Profile

OUT = ROOT / 'reports/v4/k8_quality_policy_20260909'
PROFILE = Profile(Format(18, 14), Format(18, 16), Format(27, 22), 64)
ALGORITHMS = ('IHT', 'HTP', 'FISTA', 'ADMM', 'PDHG')
TRAIN = (4101, 4102, 4103, 4104)
HOLDOUT = (6101, 6102)


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def fixture(m, n, seed):
    scale = 8192 if m == 64 else 11585
    raw = lfsr32_matrix(0x12345678, m, n, scale=scale).astype(int)
    a = raw / 65536.
    rng = np.random.default_rng(seed)
    support = sorted(map(int, rng.choice(n, 8, replace=False)))
    x = np.zeros(n)
    x[support] = rng.uniform(.5, 1, 8) * rng.choice([-1, 1], 8)
    analog = a @ x
    gain = .5 / np.max(np.abs(analog))
    x *= gain
    yraw = np.rint(analog * gain * 16384).astype(int)
    return a, yraw / 16384., x, dict(seed=seed, support=support, gain=gain,
        raw_phi_sha256=hashlib.sha256(raw.astype('<i4').tobytes()).hexdigest(),
        raw_y_sha256=hashlib.sha256(yraw.astype('<i4').tobytes()).hexdigest())


def policy(algorithm, a, choice, budget):
    l = float(np.linalg.norm(a, 2)**2)
    column_norm = float(np.max(np.sum(a*a, axis=0)))
    # Quantization-only measurement error is bounded by half one D18F14 LSB.
    noise_bound = np.sqrt(a.shape[0]) / 32768.
    if algorithm in ('IHT', 'HTP'):
        step = .95/l if choice == 'global' else float(choice)/column_norm
        return Policy(8, max_iterations=budget, residual_atol=2*noise_bound,
                      step_size=step, ls_normal_rtol=1e-4)
    # Static noise scale and operator norm only; never uses planted coefficients.
    regularization = 4/16384*np.sqrt(2*np.log(a.shape[1]))*np.sqrt(column_norm)
    return ProxPolicy(regularization=float(regularization), max_iterations=budget,
        step_size=.95/l if algorithm == 'FISTA' else float(choice) if algorithm=='PDHG' else .1,
        pd_sigma=.90/(float(choice)*l) if algorithm=='PDHG' else 1., admm_rho=float(choice) if algorithm == 'ADMM' else 1.,
        inner_max_iterations=64, inner_rtol=1e-4)


def solve(algorithm, a, y, p, fixed=False):
    if algorithm in ('IHT', 'HTP'):
        options = dict(ls_solver='qr', qr_max_refinements=2) if fixed and algorithm=='HTP' else {}
        if fixed:
            options.update(solution_format=Format(24,20), ls_solver='qr' if algorithm=='HTP' else 'lsqr')
        return run(algorithm, a, y, p, PROFILE if fixed else None,
                   **options)
    return prox_run(algorithm, a, y, p, PROFILE if fixed else None)


def assess(result, a, y, truth, p):
    nmse = float(np.sum((result.x-truth)**2)/np.sum(truth**2))
    residual = y-a@result.x
    gradient = a.T@(-residual)
    lam = getattr(p, 'regularization', 0.)
    # KKT diagnostic is observable without truth; it is not implemented as a stop.
    kkt = np.where(np.abs(result.x)>0, np.abs(gradient+lam*np.sign(result.x)),
                   np.maximum(np.abs(gradient)-lam, 0))
    return dict(nmse=nmse, snr_db=None if nmse == 0 else float(-10*np.log10(nmse)),
        residual_norm=float(np.linalg.norm(residual)), kkt_inf=float(np.max(kkt)),
        status=result.status, events=result.events, support=list(map(int,result.support)),
        outer=sum(v.get('phase')=='COMMIT' for v in result.trace),
        inner=sum(v.get('inner_iterations',0) for v in result.trace),
        qr_calls=len(result.solver_trace))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fixed', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    paths = [Path(__file__).resolve()] + sorted((ROOT/'models/v4').glob('*.py'))
    before = {p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    results, selected, training, operators = [], {}, [], []
    start = time.time()
    for m,n in ((64,256),(32,64)):
        a,_,_,_ = fixture(m,n,1909+m+n)
        gram = a.T@a
        norms = np.sqrt(np.diag(gram)); corr = gram/np.outer(norms,norms)
        np.fill_diagonal(corr,0)
        operators.append(dict(m=m,n=n,lipschitz=float(np.linalg.norm(a,2)**2),
            coherence=float(np.max(np.abs(corr))),rank=int(np.linalg.matrix_rank(a))))
        for algorithm in ALGORITHMS:
            choices = ('global','.2','.3','.4','.5') if algorithm=='IHT' else ('.4','.6','.8','1.0') if algorithm=='HTP' else ('.1','.3','1.0') if algorithm=='ADMM' else ('1.0','4.0','8.0') if algorithm=='PDHG' else ('operator',)
            budget = 128 if algorithm in ('IHT','HTP') else 512
            candidates=[]
            for choice in choices:
                scores=[]
                for seed in TRAIN:
                    a,y,x,meta=fixture(m,n,seed);p=policy(algorithm,a,choice,budget)
                    r=solve(algorithm,a,y,p);q=assess(r,a,y,x,p)
                    # Selection uses only observation residual and numerical status.
                    score=q['residual_norm'] if r.status in ('max_iterations','residual_tolerance') else float('inf')
                    scores.append(score)
                    training.append(dict(m=m,n=n,algorithm=algorithm,choice=choice,seed=seed,policy=asdict(p),metrics=q,selection_score=score))
                candidates.append((max(scores),choice))
            _,choice=min(candidates)
            selected[f'{m}x{n}:{algorithm}']=dict(choice=choice,budget=budget,selection='minimum worst training residual; fixed choices/no truth or SNR in score')
            for seed in (1909+m+n,)+HOLDOUT:
                a,y,x,meta=fixture(m,n,seed);p=policy(algorithm,a,choice,budget)
                original=seed==1909+m+n
                if original:
                    prior=json.loads((ROOT/f'reports/v4/k8_m{m}_n{n}_rtl_20260909/summary.json').read_text())
                    assert all(c['raw_phi_sha256']==meta['raw_phi_sha256'] and c['raw_y_sha256']==meta['raw_y_sha256'] for c in prior['cases'])
                floating=assess(solve(algorithm,a,y,p),a,y,x,p)
                fixed=assess(solve(algorithm,a,y,p,True),a,y,x,p) if args.fixed and floating['nmse']<=.01 else None
                ratio=None if fixed is None else fixed['nmse']/floating['nmse'] if floating['nmse'] else (1 if fixed['nmse']==0 else None)
                loss=None if ratio is None else float(10*np.log10(ratio)) if ratio>0 else -999.
                row=dict(m=m,n=n,algorithm=algorithm,role='original' if original else 'holdout',fixture=meta,
                    true_support_condition=float(np.linalg.cond(a[:,meta['support']])),policy=asdict(p),floating=floating,fixed=fixed,nmse_ratio=ratio,snr_loss_db=loss,
                    fixed_not_run_reason='float quality below20dB; no fixed qualification claimed' if args.fixed and fixed is None else None,
                    quality_pass=None if fixed is None else max(fixed['nmse'],floating['nmse'])<=.01 and ratio is not None and ratio<=1.1 and loss<=.5)
                results.append(row)
                print(json.dumps(dict(m=m,algorithm=algorithm,seed=seed,float_snr=floating['snr_db'],fixed_snr=None if fixed is None else fixed['snr_db'],status=None if fixed is None else fixed['status'])),flush=True)
                (OUT/'progress.json').write_text(json.dumps(dict(selected=selected,cases=results),indent=2))
    after={p.relative_to(ROOT).as_posix():digest(p) for p in paths}
    assert before==after,'sources changed'
    output=dict(scope='Numerical policy study, not RTL/cycle qualification. Original fixture byte hashes matched. Held-out synthetic truths on the same operators, not held-out real application domains.',
        training_seeds=TRAIN,holdout_seeds=HOLDOUT,operators=operators,selected=selected,training=training,cases=results,
        elapsed_seconds=time.time()-start,source_sha256=before,source_stable=True,
        stop_scope='Greedy existing residual_atol stop supported. Proximal outer convergence stop absent from current model/compiler; max_iterations only. KKT is diagnostic, not claimed runtime control.')
    name='stage2_fixed.json' if args.fixed else 'stage2_float.json'
    (OUT/name).write_bytes((json.dumps(output,indent=2)+'\n').encode())
    for p in paths:
        dest=OUT/'stage2_sources'/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())


if __name__=='__main__':
    main()
