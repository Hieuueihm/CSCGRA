"""Small reproducible calibration screen. Never freezes a production profile.

All requested rows, including failures, are emitted. Application cases measure
original signals through Phi*Psi; they are not oracle-sparsified before sensing.
"""
from __future__ import annotations
import argparse
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import platform
import sys
import time
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4 import recovery, proximal
from models.v4.fixed import Profile, Format
from models.v4.quality import compare, signed_dot_width

PROFILES = {
    'compact': Profile(Format(16,12), Format(16,14), Format(24,16), signed_dot_width(24,24,1024)),
    'dsp_candidate': Profile(Format(18,14), Format(18,16), Format(27,19), signed_dot_width(27,27,1024)),
    'wide_control': Profile(Format(20,16), Format(18,16), Format(32,24), signed_dot_width(32,32,1024)),
}

THRESHOLDS = {'max_snr_loss_db': 0.5, 'max_nmse_ratio': 1.1}
LASSO_OBJECTIVE = '0.5*||A*x-y||_2^2 + regularization*||x||_1'


def digest(values):
    a = np.asarray(values, dtype='<f8')
    return hashlib.sha256(a.tobytes(order='C')).hexdigest()


def problem(name, signal, basis, m, k, seed, source):
    signal = np.asarray(signal, dtype=float).reshape(-1)
    basis = np.asarray(basis, dtype=float)
    if (not signal.size or basis.shape != (signal.size, signal.size)
            or not np.all(np.isfinite(signal)) or not np.all(np.isfinite(basis))):
        raise ValueError('finite signal[N] and square basis[N,N] required')
    if not np.allclose(basis.T @ basis, np.eye(signal.size), rtol=1e-10, atol=1e-12):
        raise ValueError('restoration contract requires an orthonormal basis')
    if not (isinstance(m, int) and isinstance(k, int)
            and 0 < m <= signal.size and 0 < k <= signal.size):
        raise ValueError('m and k must be positive integers no larger than N')
    rng = np.random.default_rng(seed)
    mean = float(np.mean(signal)) if name != 'synthetic' else 0.0
    scale = 0.5/max(float(np.max(np.abs(signal-mean))), 1e-12)
    scaled = (signal-mean)*scale
    phi = rng.choice([-1.,1.], (m,len(signal))) / math.sqrt(m)
    a0 = phi @ basis
    column_norm = np.linalg.norm(a0, axis=0)
    if np.any(column_norm == 0):
        raise ValueError('zero operator column')
    a = a0/column_norm
    noiseless = phi @ scaled
    noise = rng.standard_normal(m)
    noise *= np.linalg.norm(noiseless)*10**(-30/20)/np.linalg.norm(noise)
    y = noiseless+noise
    return {'name': name, 'a': a, 'y': y, 'truth': signal, 'basis': basis,
            'column_norm': column_norm, 'scale': scale, 'mean': mean, 'k': k,
            'manifest': {'source': source, 'split': 'calibration_only', 'seed': seed,
                'n': len(signal), 'm': m, 'k_policy': k, 'measurement_snr_db': 30,
                'mean_side_information': mean, 'amplitude_scale': scale,
                'truth_sha256': digest(signal), 'operator_sha256': digest(a),
                'measurement_sha256': digest(y), 'basis_sha256': digest(basis),
                'lasso_objective': LASSO_OBJECTIVE,
                'operator_contract': 'A=(Phi@basis)/column_norm; x_A=column_norm*x_basis',
                'restoration_contract': 'signal=(basis@(x_A/column_norm))/scale+mean',
                'oracle_sparsified_before_measurement': False}}


def cases(suite):
    x = np.zeros(32)
    x[[2,11,25]] = [.5,-.35,.2]
    result = [problem('synthetic', x, np.eye(32), 24, 3, 20260908,
                      {'kind': 'synthetic_exact_sparse', 'indices': [2,11,25]})]
    if suite == 'applications':
        import scipy
        import skimage
        from scipy import datasets
        from scipy.fft import idct
        from skimage import data
        camera = data.camera().astype(float)/255
        basis8 = idct(np.eye(8), norm='ortho', axis=0)
        result.append(problem('camera_patch', camera[192:200,240:248], np.kron(basis8,basis8),
            40,8,20260909, {'kind':'image','loader':'skimage.data.camera',
            'package':'scikit-image','package_version':skimage.__version__,
            'url':'https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.camera',
            'selection':'rows192:200, columns240:248; predeclared one patch',
            'source_array_sha256':digest(camera)}))
        ecg = datasets.electrocardiogram()
        result.append(problem('ecg_segment', ecg[3600:3664], idct(np.eye(64), norm='ortho', axis=0),
            40,8,20260910, {'kind':'ecg','loader':'scipy.datasets.electrocardiogram',
            'package':'scipy','package_version':scipy.__version__,
            'url':'https://docs.scipy.org/doc/scipy/reference/generated/scipy.datasets.electrocardiogram.html',
            'selection':'samples3600:3664 in record208 excerpt; not patient-held-out',
            'source_array_sha256':digest(ecg)}))
    return result


def restored(case, coefficients):
    return (case['basis'] @ (coefficients/case['column_norm']))/case['scale']+case['mean']


def sanitized(value):
    if isinstance(value, float) and not math.isfinite(value):
        return 'nan' if math.isnan(value) else 'inf' if value > 0 else '-inf'
    if isinstance(value, dict):
        return {k:sanitized(v) for k,v in value.items()}
    if isinstance(value, (list,tuple)):
        return [sanitized(v) for v in value]
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['synthetic','applications'], default='synthetic')
    parser.add_argument('--profiles', nargs='+', choices=PROFILES, default=list(PROFILES))
    parser.add_argument('--algorithms', nargs='+', choices=recovery.ALGORITHMS+proximal.ALGORITHMS,
                        default=list(recovery.ALGORITHMS+proximal.ALGORITHMS))
    parser.add_argument('--output', type=Path, default=ROOT/'reports/v4/numeric_screen.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    dataset = cases(args.suite)
    report = {'schema_version':1, 'scope':'initial_calibration_screen',
        'selected_production_profile':None, 'paper_claim_ready':False,
        'synthesis_allowed':False, 'absolute_application_floors_frozen':False,
        'python':platform.python_version(), 'numpy':np.__version__,
        'thresholds': dict(THRESHOLDS),
        'configuration': {'suite':args.suite, 'profiles':list(args.profiles),
                          'algorithms':list(args.algorithms)},
        'profiles': {name:asdict(PROFILES[name]) for name in args.profiles},
        'cases':[{'name':c['name'], **c['manifest']} for c in dataset], 'rows':[]}
    relevant = [Path(__file__), *sorted((ROOT/'models/v4').glob('*.py'))]
    report['source_sha256'] = {str(p.relative_to(ROOT)).replace('\\','/'):
                              hashlib.sha256(p.read_bytes()).hexdigest() for p in relevant}
    source_manifest = json.dumps(report['source_sha256'], sort_keys=True).encode('utf-8')
    report['combined_source_sha256'] = hashlib.sha256(source_manifest).hexdigest()
    def save():
        args.output.write_text(json.dumps(sanitized(report), indent=2, allow_nan=False)+'\n', encoding='utf-8')
    for c in dataset:
        spectral_sq = float(np.linalg.norm(c['a'],2)**2)
        for algorithm in args.algorithms:
            if algorithm in recovery.ALGORITHMS:
                budget = c['k'] if algorithm in ('OMP','GOMP') else 32
                policy = recovery.Policy(c['k'], max_iterations=budget,
                    step_size=.9/spectral_sq, residual_atol=1e-6)
                runner = recovery.run
            else:
                policy = proximal.Policy(regularization=.01, max_iterations=48,
                    step_size=.9/spectral_sq, pd_sigma=.9)
                runner = proximal.run
            try:
                floating = runner(algorithm,c['a'],c['y'],policy)
                float_reference_valid = not any(
                    phase['phase'] == 'FAULT' for phase in floating.trace
                )
            except (ArithmeticError, ValueError) as exc:
                for label in args.profiles:
                    row = {'case':c['name'],'algorithm':algorithm,'profile':label,
                           'profile_id':PROFILES[label].name,
                           'screen_pass':False,'float_reference_valid':False,
                           'reference_exception':str(exc),'policy':asdict(policy),
                           'model_elapsed_seconds':0.0}
                    report['rows'].append(row)
                    save()
                    print(f"{c['name']} {algorithm} {label}: FAIL", flush=True)
                continue
            for label in args.profiles:
                started = time.perf_counter()
                try:
                    fixed = runner(algorithm,c['a'],c['y'],policy,PROFILES[label])
                    quality = compare(
                        c['truth'], restored(c,floating.x), restored(c,fixed.x),
                        **THRESHOLDS,
                    )
                    fault = (any(fixed.events.values()) or any(p['phase']=='FAULT' for p in fixed.trace)
                             or not float_reference_valid)
                    row = {'case':c['name'],'algorithm':algorithm,'profile':label,
                        'profile_id':PROFILES[label].name,'policy':asdict(policy),
                        'float_reference_valid':float_reference_valid,
                        'float_status':floating.status,'fixed_status':fixed.status,
                        'events':fixed.events,'same_support_diagnostic':floating.support==fixed.support,
                        'quality':quality,'screen_pass':quality['arithmetic_quality_pass'] and not fault,
                        'centered_signal_quality':compare(
                            c['truth']-c['mean'], restored(c,floating.x)-c['mean'],
                            restored(c,fixed.x)-c['mean'], **THRESHOLDS,
                        ),
                        'mean_restored_in_primary_quality':True,
                        'phase_count':len(fixed.trace)}
                except (ArithmeticError,ValueError) as exc:
                    row = {'case':c['name'],'algorithm':algorithm,'profile':label,
                           'profile_id':PROFILES[label].name,
                           'float_reference_valid':float_reference_valid,
                           'float_status':floating.status,
                           'screen_pass':False,'exception':str(exc),'policy':asdict(policy)}
                row['model_elapsed_seconds'] = time.perf_counter()-started
                report['rows'].append(row)
                save()
                print(f"{c['name']} {algorithm} {label}: {'PASS' if row['screen_pass'] else 'FAIL'}",flush=True)
    report['complete']=True
    report['summary'] = {p:{'passed':sum(r['screen_pass'] for r in report['rows'] if r['profile']==p),
                            'total':sum(r['profile']==p for r in report['rows'])} for p in args.profiles}
    save()
    print(json.dumps(report['summary']))
    return 0  # a screen records failures; it is never a release gate


if __name__ == '__main__':
    raise SystemExit(main())
