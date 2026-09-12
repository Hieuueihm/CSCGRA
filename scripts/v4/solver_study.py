"""Isolate existing v4 fixed CGLS from support selection; this is not a release gate.

The production model is called unchanged. Candidate capture adds diagnostics,
never a fallback, altered tolerance, regularization, or accepted failed result.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import platform
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4.fixed import Arithmetic
from models.v4.quality import compare
from models.v4.recovery import IntegerKernels, Policy
from scripts.v4.numeric_screen import PROFILES, digest, sanitized

NORMAL_RTOL = 1e-4
ITERATION_BUDGET = 128


def relative_norm(numerator, denominator):
    """Preserve an impossible nonzero/zero comparison; no hidden epsilon floor."""
    n, d = float(np.linalg.norm(numerator)), float(np.linalg.norm(denominator))
    return n/d if d else (0.0 if n == 0 else float('inf'))


def normal_diagnostics(a, y, x):
    residual = y-a@x
    gradient = a.T@residual
    return {'normal_relative': relative_norm(gradient, a.T@y),
            'normal_norm': float(np.linalg.norm(gradient)),
            'residual_norm': float(np.linalg.norm(residual))}


def data_rounding_bound(a, data_format):
    """Componentwise |A.T A| * (Delta_D/2); requires no clipping on storage."""
    return np.abs(a.T@a) @ np.full(a.shape[1], 0.5/data_format.scale)


class ObservedCGLS(IntegerKernels):
    """Observe the unchanged CGLS implementation through its existing hooks."""
    def __init__(self, matrix, measurement, policy, profile):
        super().__init__(matrix, measurement, policy, profile)
        self.candidates = []
        self.last_pre_storage = None

    def store(self, value):
        self.last_pre_storage = self.decode(value).copy()
        return super().store(value)

    def certificate(self, coefficients, support, rhs_energy):
        accepted = super().certificate(coefficients, support, rhs_energy)
        aq = self.arithmetic.decode(self.a[:, support], self.profile.coefficient)
        yq, x = self.decode(self.y), self.decode(coefficients)
        self.candidates.append({
            'iteration': self.ls_steps, 'model_certificate': bool(accepted),
            'x': x.copy(),
            'pre_storage': None if self.last_pre_storage is None
                else self.last_pre_storage.copy(),
            **normal_diagnostics(aq, yq, x),
        })
        return accepted


def cases(seed=20260918):
    """One fixed support; extra columns ensure we exercise the support interface."""
    rng = np.random.default_rng(seed)
    m, n = 32, 13
    support = [1, 3, 5, 7, 8, 10, 11, 12]
    basis, _ = np.linalg.qr(rng.normal(size=(m, len(support))))
    base = rng.normal(size=(m, n))
    base /= np.linalg.norm(base, axis=0)
    truth = rng.uniform(-0.45, 0.45, size=len(support))
    truth[0:2] = [0.35, -0.21]
    noise_direction = rng.normal(size=m)
    noise_direction /= np.linalg.norm(noise_direction)
    result = []
    for name, epsilon in [('well_conditioned', None),
                          ('near_collinear', 1e-3), ('rank_deficient', 0.0)]:
        a = base.copy()
        restricted = basis.copy()
        if epsilon is not None:
            restricted[:, 1] = (basis[:, 0]+epsilon*basis[:, 1])/np.sqrt(1+epsilon**2)
        a[:, support] = restricted
        clean = restricted@truth
        y = clean + noise_direction*np.linalg.norm(clean)*10**(-30/20)
        result.append({'name': name, 'seed': seed, 'a': a, 'y': y,
                       'support': support.copy(), 'truth': truth.copy()})
    return result


def isolate_cgls(case, profile):
    """Run support-only unregularized CGLS and compare with independent SVD/QR."""
    a, y, support = case['a'], case['y'], case['support']
    policy = Policy(sparsity=len(support), ls_normal_rtol=NORMAL_RTOL,
                    ls_max_iterations=ITERATION_BUDGET)
    kernel = ObservedCGLS(a, y, policy, profile)
    aq = kernel.arithmetic.decode(kernel.a[:, support], profile.coefficient)
    yq = kernel.decode(kernel.y)
    original = a[:, support]
    oracle, _, rank, singular = np.linalg.lstsq(aq, yq, rcond=None)
    original_oracle, _, original_rank, _ = np.linalg.lstsq(original, y, rcond=None)
    status, accepted = 'certified', None
    try:
        if any(kernel.events.values()):
            raise ArithmeticError('numeric_fault')
        accepted = kernel.decode(kernel.least_squares(support))
        if any(kernel.events.values()):
            status, accepted = 'numeric_fault', None
    except ArithmeticError as exc:
        status = str(exc)
    # Inspect the last candidate after failure, but never promote it to a result.
    candidate = kernel.candidates[-1] if kernel.candidates else None
    rounded_arithmetic = Arithmetic(profile)
    rounded = rounded_arithmetic.decode(
        rounded_arithmetic.quantize(oracle, profile.data), profile.data)
    bound = data_rounding_bound(aq, profile.data)
    observed_change = aq.T@aq@(rounded-oracle)
    row = {
        'case': case['name'], 'profile_id': profile.name, 'status': status,
        'accepted': accepted is not None, 'inner_iterations': kernel.ls_steps,
        'events': dict(kernel.events), 'rank_quantized': int(rank),
        'rank_original': int(original_rank),
        'condition_quantized': float(singular[0]/singular[-1]),
        'condition_original': float(np.linalg.cond(original)),
        'oracle': {'method': 'numpy.linalg.lstsq; rcond=None; SVD minimum norm',
                   'coefficient_norm': float(np.linalg.norm(oracle)),
                   **normal_diagnostics(aq, yq, oracle)},
        'operator_input_only': {
            'coefficient_error_vs_original_svd': relative_norm(oracle-original_oracle, original_oracle),
            'operator_error_frobenius': float(np.linalg.norm(aq-original)),
            'input_error_norm': float(np.linalg.norm(yq-y)),
        },
        'oracle_rounded_to_D': {
            'events': dict(rounded_arithmetic.events),
            **normal_diagnostics(aq, yq, rounded),
            'coefficient_error_vs_quantized_svd': relative_norm(rounded-oracle, oracle),
            'gradient_change_bound_l2': float(np.linalg.norm(bound)),
            'gradient_change_observed_l2': float(np.linalg.norm(observed_change)),
            'componentwise_bound_valid_no_clipping': not any(rounded_arithmetic.events.values()),
            'bound_holds': bool(np.all(np.abs(observed_change) <= bound+1e-14)),
            'synthetic_coefficient_quality': compare(case['truth'], oracle, rounded),
        },
        'last_candidate': None,
        'certificate_history': [{k:v for k,v in c.items() if k not in ('x', 'pre_storage')}
                                for c in kernel.candidates],
    }
    if rank == len(support):
        q, r = np.linalg.qr(aq, mode='reduced')
        qr_solution = np.linalg.solve(r, q.T@yq)
        row['oracle']['qr_relative_difference'] = relative_norm(qr_solution-oracle, oracle)
    else:
        row['oracle']['qr_relative_difference'] = None
    if candidate is not None:
        x = candidate['x']
        row['last_candidate'] = {
            **{k:v for k,v in candidate.items() if k not in ('x', 'pre_storage')},
            'diagnostic_only_if_failed': accepted is None,
            'coefficient_error_vs_quantized_svd': relative_norm(x-oracle, oracle),
            'coefficient_error_vs_original_svd': relative_norm(x-original_oracle, original_oracle),
            'prediction_error_vs_quantized_svd': relative_norm(aq@(x-oracle), aq@oracle),
            'synthetic_coefficient_quality': compare(case['truth'], original_oracle, x),
            'pre_storage_normal': None if candidate['pre_storage'] is None else
                normal_diagnostics(aq, yq, candidate['pre_storage']),
        }
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profiles', nargs='+', choices=PROFILES, default=list(PROFILES))
    parser.add_argument('--seed', type=int, default=20260918)
    parser.add_argument('--output', type=Path, default=ROOT/'reports/v4/solver_study.json')
    args = parser.parse_args()
    dataset = cases(args.seed)
    sources = [Path(__file__), ROOT/'scripts/v4/numeric_screen.py',
               ROOT/'models/v4/recovery.py', ROOT/'models/v4/fixed.py', ROOT/'models/v4/quality.py']
    report = {
        'schema_version': 1, 'scope': 'isolated_cgls_calibration_diagnostics',
        'selected_production_profile': None, 'synthesis_allowed': False,
        'application_quality_established': False,
        'python': platform.python_version(), 'numpy': np.__version__,
        'policy': {'ls_normal_rtol': NORMAL_RTOL, 'ls_max_iterations': ITERATION_BUDGET,
                   'initial_x': 'zero', 'regularization': 0},
        'profiles': {name:asdict(PROFILES[name]) for name in args.profiles},
        'source_sha256': {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sources},
        'cases': [{'name':c['name'], 'seed':c['seed'], 'support':c['support'],
                   'M':c['a'].shape[0], 'N':c['a'].shape[1], 'measurement_snr_db':30,
                   'operator_sha256':digest(c['a']), 'measurement_sha256':digest(c['y']),
                   'truth_sha256':digest(c['truth'])} for c in dataset],
        'rows': [],
    }
    for case in dataset:
        for name in args.profiles:
            row = isolate_cgls(case, PROFILES[name])
            row['profile'] = name
            report['rows'].append(row)
    report['summary'] = {
        'rows': len(report['rows']),
        'certified': sum(row['accepted'] for row in report['rows']),
        'failed': sum(not row['accepted'] for row in report['rows']),
        'D_rounding_exceeds_normal_rtol': sum(
            row['oracle_rounded_to_D']['normal_relative'] > NORMAL_RTOL
            for row in report['rows']),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(sanitized(report), indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps(report['summary'], sort_keys=True))
    print(f'Diagnostic report: {args.output}')


if __name__ == '__main__':
    main()
