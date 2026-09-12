"""Explicit numerical candidate policies; no algorithm or arithmetic substitution."""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from models.v4.recovery import Policy
from models.v4.proximal import Policy as ProximalPolicy

ROOT=Path(__file__).resolve().parents[2]


def candidate_qualification(algorithm,matrix,*,authority=None):
    """Return evidence only for the exact operator used by its study."""
    candidate_policy(algorithm,matrix,authority=authority)
    config=json.loads((ROOT/'config/v4_quality_policy.json' if authority is None else Path(authority)).read_text())
    m,n=np.asarray(matrix).shape
    evidence=config.get('numerical_qualification',{}).get(f'{m}x{n}',{}).get(algorithm)
    if evidence is None:raise ValueError('algorithm/geometry has no recorded numerical qualification')
    marker='raw Phi SHA256 '
    if marker not in evidence['operator']:raise ValueError('numerical qualification lacks operator identity')
    expected=evidence['operator'].split(marker,1)[1]
    raw=np.rint(np.asarray(matrix,dtype=float)*65536).astype('<i4')
    actual=hashlib.sha256(raw.tobytes()).hexdigest()
    if actual!=expected:raise ValueError('numerical qualification applies only to its recorded raw Phi')
    return evidence


def candidate_policy(algorithm,matrix,*,authority=None):
    config=json.loads((ROOT/'config/v4_quality_policy.json' if authority is None else Path(authority)).read_text())
    a=np.asarray(matrix,dtype=float)
    if a.ndim!=2 or not np.all(np.isfinite(a)):raise ValueError('finite matrix required')
    m,n=a.shape
    rule=config['regimes'].get(f'{m}x{n}',{}).get(algorithm)
    if rule is None:raise ValueError('algorithm/geometry has no accepted candidate policy')
    scaled=a*65536
    if np.any(scaled<-(1<<17)) or np.any(scaled>((1<<17)-1)):raise ValueError('C18 coefficient overflow')
    raw=np.rint(scaled).astype(np.int64)
    if np.any(scaled!=raw):raise ValueError('candidate requires exact C18 input grid; no implicit quantization')
    if not raw.size or np.any(np.abs(raw)!=abs(int(raw.flat[0]))) or raw.flat[0]==0:
        raise ValueError('candidate study requires uniform nonzero signed coefficients')
    actual=raw/65536.
    norm=float(np.max(np.sum(actual*actual,axis=0)))
    if algorithm in ('IHT','HTP','OMP','GOMP','CoSaMP','SP','MP','GP'):
        return Policy(config['k'],max_iterations=rule.get('budget',config['greedy_budget']),
            step_size=rule.get('step_over_column_norm',.1)/norm,
            residual_atol=math.ceil(math.sqrt(m))/16384,
            ls_normal_rtol=config['ls_normal_rtol'])
    values=config['proximal'];l=float(np.linalg.norm(actual,2)**2)
    tau=values['fista_lipschitz_fraction']/l
    regularization=max(values['regularization_floor'],values['minimum_shrinkage_output_lsbs']/16384/tau)
    return ProximalPolicy(regularization=regularization,max_iterations=rule['budget'],
        step_size=tau if algorithm=='FISTA' else values['pdhg_tau'],
        pd_sigma=values['pdhg_product_bound']/(values['pdhg_tau']*l),
        admm_rho=values['admm_rho'],inner_max_iterations=values['inner_max_iterations'],
        inner_rtol=values['inner_rtol'])
