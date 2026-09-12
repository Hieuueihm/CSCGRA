"""Bounded float-only LFSR application calibration with shared domain policies.

Signals, measurements, noise and operators come unchanged from outer_cases.
Policies are selected jointly over each domain's calibration windows. This does
not establish held-out quality, fixed-point precision or FPGA performance.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import importlib.metadata
import itertools
import json
import math
from pathlib import Path
import platform
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4 import proximal, recovery
from models.v4.quality import metrics
from scripts.v4.generated_numeric_study import outer_cases
from scripts.v4.numeric_screen import digest, sanitized

ALGORITHMS = recovery.ALGORITHMS + proximal.ALGORITHMS
SEEDS = (23, 47, 101)


def source_hashes():
    files = [Path(__file__), *sorted((ROOT / 'models/v4').glob('*.py')),
             ROOT / 'scripts/v4/generated_numeric_study.py',
             ROOT / 'scripts/v4/solver_study.py', ROOT / 'scripts/v4/numeric_screen.py']
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def domain(case):
    return 'synthetic' if case['name'].startswith('synthetic') else ('ecg' if case['name'].startswith('ecg') else 'camera')


def recipes(algorithm, family):
    ks = [8] if family == 'synthetic' else [16, 24, 32]
    if algorithm in ('OMP', 'GOMP'):
        return [dict(sparsity=k, iterations=k, step_multiplier=.9) for k in ks]
    if algorithm in ('MP', 'GP'):
        return [dict(sparsity=ks[-1], iterations=n, step_multiplier=.9) for n in [64, 192, 384]]
    if algorithm == 'IHT':
        return [dict(sparsity=k, iterations=n, step_multiplier=s)
                for k, n, s in itertools.product(ks, [64, 192, 384], [.9, 1.8])]
    if algorithm in ('CoSaMP', 'SP', 'HTP'):
        return [dict(sparsity=k, iterations=n, step_multiplier=s)
                for k, n, s in itertools.product(ks, [24, 64], [.9, 1.8] if algorithm == 'HTP' else [.9])]
    return [dict(regularization=l, iterations=n, step_multiplier=.9, pd_sigma=.9, admm_rho=r)
            for l, n, r in itertools.product([.001, .003, .01], [96, 256, 512], [.1, 1.] if algorithm == 'ADMM' else [1.])]


def make_policy(algorithm, recipe, spectral_sq):
    step = recipe['step_multiplier'] / spectral_sq
    if algorithm in recovery.ALGORITHMS:
        return recovery.Policy(sparsity=recipe['sparsity'], max_iterations=recipe['iterations'],
            residual_atol=1e-6, step_size=step, group_size=2,
            ls_max_iterations=128, ls_normal_rtol=1e-5)
    return proximal.Policy(regularization=recipe['regularization'], max_iterations=recipe['iterations'],
        step_size=step, pd_sigma=recipe['pd_sigma'], admm_rho=recipe['admm_rho'],
        inner_max_iterations=128, inner_rtol=1e-4)


def run_one(case, algorithm, recipe, recipe_id):
    policy = make_policy(algorithm, recipe, case['spectral_sq'])
    row = {'case': case['name'], 'domain': domain(case), 'algorithm': algorithm,
           'recipe_id': recipe_id, 'recipe': recipe, 'policy': asdict(policy),
           'exception': None, 'no_numeric_fault': False, 'capacity_eligible': False,
           'full_original_quality': None, 'centered_original_quality': None}
    start = time.perf_counter()
    try:
        result = (recovery.run(algorithm, case['a'], case['y'], policy)
                  if algorithm in recovery.ALGORITHMS else proximal.run(algorithm, case['a'], case['y'], policy))
        reconstructed = case['restore'](result.x)
        full = metrics(case['original'], reconstructed)
        centered = metrics(case['original'] - case.get('mean', 0), reconstructed - case.get('mean', 0))
        ls_supports = [item['support'] for item in result.trace if item.get('phase') == 'LS']
        persisted_sizes = [len(item['support']) for item in result.trace
                           if item.get('phase') in ('COMMIT', 'INITIALIZE') and 'support' in item]
        largest_persisted = max([len(result.support), *persisted_sizes])
        largest_ls = max([0, *map(len, ls_supports)])
        # Dense proximal programs use N-wide vectors and no indexed active-list
        # memory. Their nonzero set is diagnostic, not a 96-entry support list.
        active_list_used = algorithm in recovery.ALGORITHMS
        capacity = largest_ls <= 96 and (not active_list_used or largest_persisted <= 96)
        energies = [item['residual_energy_raw'] for item in result.trace if item.get('phase') == 'COMMIT' and 'residual_energy_raw' in item]
        nofault = not any(result.events.values()) and not any(item.get('phase') == 'FAULT' for item in result.trace)
        row.update(status=result.status, events=result.events, no_numeric_fault=nofault,
            full_original_quality=full, centered_original_quality=centered,
            x=result.x.tolist(), support=list(result.support), final_support_size=len(result.support),
            indexed_active_list_used=active_list_used, max_persisted_support_size=largest_persisted,
            max_ls_support_size=largest_ls, ls_supports=ls_supports, capacity_eligible=capacity,
            commits=sum(item.get('phase') == 'COMMIT' for item in result.trace),
            trace_sha256=hashlib.sha256(json.dumps(sanitized(result.trace), sort_keys=True).encode()).hexdigest(),
            fault_trace=[item for item in result.trace if item.get('phase') == 'FAULT'],
            residual_energy_sequence=energies,
            residual_increases=sum(b > a * (1 + 1e-12) for a, b in zip(energies, energies[1:])),
            final_measurement_residual_norm=float(np.linalg.norm(result.residual)),
            float_snr20_pass=bool(nofault and full['snr_db'] >= 20),
            shortlist_snr20_pass=bool(nofault and capacity and full['snr_db'] >= 20),
            shortlist_margin20_5_pass=bool(nofault and capacity and full['snr_db'] >= 20.5),
            pdhg_tau_sigma_L=(policy.step_size * policy.pd_sigma * case['spectral_sq'] if algorithm == 'PDHG' else None))
    except Exception as exc:
        row.update(status='exception', exception={'type': type(exc).__name__, 'message': str(exc)},
                   float_snr20_pass=False, shortlist_snr20_pass=False, shortlist_margin20_5_pass=False)
    row['model_elapsed_seconds'] = time.perf_counter() - start
    return row


def selections(report, finished_groups):
    selected = []
    for family, algorithm in finished_groups:
        rows = [r for r in report['rows'] if r['domain'] == family and r['algorithm'] == algorithm]
        groups = {}
        for row in rows:
            groups.setdefault(row['recipe_id'], []).append(row)
        candidates = []
        expected = sum(c['domain'] == family for c in report['cases'])
        for key, group in groups.items():
            eligible = len(group) == expected and all(r['no_numeric_fault'] and r['capacity_eligible'] for r in group)
            minimum = min((r['full_original_quality']['snr_db'] if r['full_original_quality'] else -math.inf) for r in group)
            recipe = group[0]['recipe']
            candidates.append({'recipe_id': key, 'recipe': recipe, 'eligible': eligible,
                'minimum_full_snr_db': minimum, 'all_margin20_5': eligible and minimum >= 20.5,
                'all_snr20': eligible and minimum >= 20, 'cost_order': [recipe['iterations'], recipe.get('sparsity', 0)],
                'case_results': [{'case': r['case'], 'policy': r['policy'], 'snr_db': None if r['full_original_quality'] is None else r['full_original_quality']['snr_db'],
                                  'centered_snr_db': None if r['centered_original_quality'] is None else r['centered_original_quality']['snr_db'],
                                  'status': r['status'], 'max_persisted_support_size': r.get('max_persisted_support_size'),
                                  'max_ls_support_size': r.get('max_ls_support_size'), 'capacity_eligible': r['capacity_eligible']} for r in group]})
        margin = [c for c in candidates if c['all_margin20_5']]
        floor = [c for c in candidates if c['all_snr20']]
        eligible = [c for c in candidates if c['eligible']]
        bucket = margin or floor or eligible or candidates
        winner = (min(bucket, key=lambda c: (c['cost_order'], -c['minimum_full_snr_db'], c['recipe_id']))
                  if margin or floor else max(bucket, key=lambda c: c['minimum_full_snr_db']))
        selected.append({'domain': family, 'algorithm': algorithm,
            'selection_rule': 'lowest iteration budget then K among shared >=20.5dB; else shared >=20dB; otherwise highest worst-window SNR; capacity<=96 required',
            'selected_for_fixed_check': winner['all_snr20'], 'winner': winner, 'candidates': candidates})
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'reports/v4/lfsr_application_float_tuning.json')
    parser.add_argument('--algorithms', nargs='+', choices=ALGORITHMS, default=list(ALGORITHMS))
    args = parser.parse_args()
    cases = [c for c in outer_cases(SEEDS, False, 'lfsr32') if c['a'].shape[1] == 256] + outer_cases(SEEDS, True, 'lfsr32')
    # Include the coefficient quantizer magnitude in a shared float/fixed-safe
    # spectral bound without altering A. LFSR columns have one common magnitude.
    for case in cases:
        original = float(np.linalg.norm(case['a'], 2) ** 2)
        magnitude = float(abs(case['a'][0, 0]))
        q = math.floor(magnitude * (1 << 16) + .5) / (1 << 16)
        case['spectral_sq_original'] = original
        case['spectral_sq'] = max(original, original * (q / magnitude) ** 2)
    hashes = source_hashes()
    report = {'schema': 'v4-lfsr-application-float-tuning-v1', 'complete': False,
        'scope': 'calibration_only_existing_7_windows_fixed_measurements', 'fixed_point_run': False,
        'configuration': {**vars(args), 'output': args.output.as_posix()}, 'source_sha256': hashes,
        'python': platform.python_version(), 'packages': {n: importlib.metadata.version(n) for n in ['numpy', 'scipy', 'scikit-image']},
        'limits': {'M': 128, 'N': 1024, 'configured_K': 32, 'indexed_active_list_capacity': 96, 'LS_support_capacity': 96},
        'thresholds': {'full_original_snr_min_db': 20, 'preferred_margin_db': 20.5},
        'selection_is_shared_per_domain_algorithm': True, 'held_out_validation': False,
        'original_signals_sparsified': False, 'raw_signal_PhiPsi_hardware_claim': False,
        'fixed_budget_completion_is_not_convergence': True, 'hardware_performance_claim': False,
        'MP_GP_K_not_enforced_by_existing_semantics': True,
        'proximal_dense_nonzero_set_is_not_an_indexed_active_list': True,
        'cases': [{'name': c['name'], 'domain': domain(c), 'track': c['track'], 'seed': c['seed'],
                   'M': c['a'].shape[0], 'N': c['a'].shape[1], 'operator_sha256': digest(c['a']),
                   'measurement_sha256': digest(c['y']), 'truth_sha256': digest(c['truth']), 'original_sha256': digest(c['original']),
                   'original': c['original'].tolist(), 'truth': c['truth'].tolist(), 'measurement': c['y'].tolist(),
                   'source': c['source'], 'mean': c.get('mean', 0), 'scale': c.get('scale', 1),
                   'spectral_sq_original': c['spectral_sq_original'], 'spectral_sq': c['spectral_sq'],
                   'measurement_snr_db': 30} for c in cases], 'rows': [], 'selected_policies': []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.output.write_text(json.dumps(sanitized(report), indent=2, allow_nan=False) + '\n', encoding='utf-8')
    save()
    finished = []
    for family in ['synthetic', 'ecg', 'camera']:
        for algorithm in args.algorithms:
            grid = recipes(algorithm, family)
            for index, recipe in enumerate(grid):
                rid = f'{family}_{algorithm}_{index:02d}'
                for case in [c for c in cases if domain(c) == family]:
                    report['rows'].append(run_one(case, algorithm, recipe, rid))
                if index % 3 == 0:
                    save()
            finished.append((family, algorithm))
            report['selected_policies'] = selections(report, finished)
            save()
            selection = report['selected_policies'][-1]
            print(f"{family} {algorithm}: minSNR={selection['winner']['minimum_full_snr_db']:.3f} eligible20={selection['selected_for_fixed_check']} recipe={selection['winner']['recipe']}", flush=True)
    report['source_unchanged_during_run'] = source_hashes() == hashes
    report['complete'] = True
    report['summary'] = {'rows': len(report['rows']), 'domain_algorithm_pairs': len(finished),
        'shared_policies_snr20_pass': sum(s['selected_for_fixed_check'] for s in report['selected_policies']),
        'shared_policies_margin20_5_pass': sum(s['winner']['all_margin20_5'] for s in report['selected_policies']),
        'exception_rows': sum(r['exception'] is not None for r in report['rows']),
        'capacity_ineligible_rows': sum(not r['capacity_eligible'] for r in report['rows'])}
    save()
    print(json.dumps(report['summary']), flush=True)
    if not report['source_unchanged_during_run']:
        raise RuntimeError('executed source changed during study')


if __name__ == '__main__':
    main()
