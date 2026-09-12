"""Verify selected shared application policies with unchanged integer models.

Float policy selection happens in a separate, completed calibration artifact.
SVD instrumentation observes stored LS returns only; it never changes the solve.
"""
from __future__ import annotations
import os
for _thread_var in ('OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS', 'OMP_NUM_THREADS'):
    os.environ[_thread_var] = '1'

import argparse
from contextlib import contextmanager, nullcontext
from dataclasses import asdict, replace
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import sys
import time
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4 import recovery, proximal, lsqr
from models.v4.fixed import Format, Profile
from models.v4.normalization import Normalization
from models.v4.quality import compare
from scripts.v4.generated_numeric_study import outer_cases
from scripts.v4.numeric_screen import digest
from scripts.v4.lfsr_outer_contract_study import json_ready, result_record


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes(accelerated, wavelet):
    paths = list((ROOT/'models/v4').glob('*.py')) + [Path(__file__),
        ROOT/'scripts/v4/generated_numeric_study.py', ROOT/'scripts/v4/numeric_screen.py',
        ROOT/'scripts/v4/solver_study.py',
        ROOT/'scripts/v4/lfsr_outer_contract_study.py', ROOT/'config/v4_design.json']
    if accelerated:
        paths.append(ROOT/'scripts/v4/fast_integer_study.py')
    if wavelet:
        paths.append(ROOT/'scripts/v4/lfsr_basis_feasibility.py')
    return {p.relative_to(ROOT).as_posix(): file_hash(p) for p in sorted(paths)}


def relative(numerator, denominator):
    n, d = float(np.linalg.norm(numerator)), float(np.linalg.norm(denominator))
    return n/d if d else (0.0 if n == 0 else math.inf)


@contextmanager
def observe_ls(audits):
    reference = lsqr.IntegerLSQRKernels
    class Observed(reference):
        def least_squares(self, support):
            answer = None
            try:
                answer = super().least_squares(support)
                return answer
            finally:
                audit = {'ordered_support': list(support), 'runtime_returned': answer is not None,
                         'status': self.last_ls_report.get('status'),
                         'diagnostic_accepted': False}
                try:
                    self.observe_return(audit, support, answer)
                except Exception as exc:
                    # Diagnostic work must never change a return or a solver failure.
                    audit.update(diagnostic_accepted=False,
                                 diagnostic_exception={'type':type(exc).__name__, 'message':str(exc)})
                audits.append(audit)

        def observe_return(self, audit, support, answer):
                if support and answer is not None:
                    # Outside the recurrence/certificate: observe exactly what was returned.
                    b = self.arithmetic.decode(self.a[:, support], self.profile.coefficient)
                    y = self.decode(self.y)
                    x = self.decode(answer)
                    oracle, _, rank, singular = np.linalg.lstsq(b, y, rcond=None)
                    coefficient_error = relative(x-oracle, oracle)
                    normal = relative(b.T @ (y-b@x), b.T @ y)
                    audit.update(rank=int(rank), coefficient_relative_error=coefficient_error,
                        normal_relative_float64=normal,
                        condition_number=float(singular[0]/singular[-1]) if singular[-1] else math.inf,
                        quantized_B_sha256=digest(b), quantized_y_sha256=digest(y),
                        stored_X_sha256=digest(x),
                        diagnostic_accepted=bool(rank == len(support) and coefficient_error <= 1e-3
                                                 and normal <= self.policy.ls_normal_rtol))
                elif not support and answer is not None:
                    audit['diagnostic_accepted'] = True
    lsqr.IntegerLSQRKernels = Observed
    try:
        yield
    finally:
        lsqr.IntegerLSQRKernels = reference


def restore_case(meta, legacy):
    if meta.get('basis_name'):
        from scripts.v4.lfsr_basis_feasibility import build_case
        case = build_case(meta['source_case'], meta['basis_name'])
    else:
        case = legacy[meta['name']]
    for field, key in [('a','operator_sha256'), ('y','measurement_sha256'),
                       ('truth','truth_sha256'), ('original','original_sha256')]:
        assert digest(case[field]) == meta[key], (meta['name'], field)
    return case


def run_selected(case, float_row, profile, xformat, thresholds):
    algorithm = float_row['algorithm']
    is_recovery = algorithm in recovery.ALGORITHMS
    floating_policy = (recovery.Policy if is_recovery else proximal.Policy)(**float_row['policy'])
    normalization = Normalization.derive(case['y'])
    fixed_policy = (replace(floating_policy, residual_atol=normalization.scale_residual_atol(floating_policy.residual_atol))
                    if is_recovery else replace(floating_policy,
                        regularization=normalization.scale_lasso_lambda(floating_policy.regularization)))
    audits = []
    started = time.perf_counter()
    result, exception = None, None
    try:
        with observe_ls(audits):
            result = (recovery.run(algorithm, case['a'], normalization.encode(case['y']), fixed_policy,
                        profile, ls_solver='lsqr', solution_format=xformat)
                      if is_recovery else proximal.run(algorithm, case['a'], normalization.encode(case['y']),
                                                      fixed_policy, profile))
    except Exception as exc:
        exception = {'type': type(exc).__name__, 'message': str(exc)}
    runtime = time.perf_counter()-started
    quality, centered = None, None
    persisted, largest_ls = 0, 0
    if result is not None:
        floating_signal = case['restore'](np.asarray(float_row['x']))
        fixed_signal = case['restore'](normalization.decode(result.x))
        quality = compare(case['original'], floating_signal, fixed_signal, **thresholds)
        if not np.any(np.asarray(case['original']) != 0):
            quality['application_quality_pass'] = quality['paper_quality_pass'] = False
        mean = case.get('mean', 0)
        centered = compare(case['original']-mean, floating_signal-mean, fixed_signal-mean,
                           **{k:v for k,v in thresholds.items() if k != 'absolute_snr_min_db'})
        persisted = max([len(result.support), *[len(t['support']) for t in result.trace
                        if t.get('phase') in ('COMMIT','INITIALIZE') and 'support' in t]])
        largest_ls = max([0, *[len(a['ordered_support']) for a in audits]])
    fixed = result_record(result, normalized=True, gain=normalization.gain)
    capacity = largest_ls <= 96 and (not is_recovery or persisted <= 96)
    nofault = exception is None and fixed.get('returned_without_numeric_fault') is True
    ls_ok = all(a['diagnostic_accepted'] for a in audits)
    quality_ok = bool(quality and quality['paper_quality_pass'])
    return {'case': case['name'], 'algorithm': algorithm, 'domain': float_row['domain'],
        'recipe_id': float_row['recipe_id'], 'float_policy': asdict(floating_policy),
        'fixed_policy': asdict(fixed_policy), 'normalization': normalization.descriptor,
        'profile': asdict(profile), 'solution_format': asdict(xformat) if is_recovery else asdict(profile.data),
        'proximal_storage': 'unchanged_D' if not is_recovery else None,
        'float_quality_from_selection': float_row['full_original_quality'],
        'quality_full_original_units': quality, 'quality_centered_original_units': centered,
        'float_status': float_row.get('status'), 'fixed_result': fixed, 'exception': exception,
        'capacity_eligible': capacity, 'max_persisted_support_size': persisted, 'max_ls_support_size': largest_ls,
        'LS_observations': audits, 'LS_diagnostic_pass': ls_ok,
        'quality_and_no_fault_pass': quality_ok and nofault and float_row['no_numeric_fault'],
        'combined_pass': quality_ok and nofault and capacity and ls_ok and float_row['no_numeric_fault'],
        'model_seconds': runtime, 'heldout_qualified': False, 'convergence_qualified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--float-report', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--domains', nargs='+')
    parser.add_argument('--algorithms', nargs='+')
    parser.add_argument('--accelerated', action='store_true')
    args = parser.parse_args()
    args.float_report = args.float_report.resolve()
    args.output = args.output.resolve()
    source = json.loads(args.float_report.read_text(encoding='utf-8'))
    assert source['complete'] and source['source_unchanged_during_run']
    config = json.loads((ROOT/'config/v4_design.json').read_text(encoding='utf-8'))['numerical']
    shortlist = config['working_shortlist_not_production']
    profile = Profile(Format(**shortlist['data']), Format(**shortlist['coefficient']),
                      Format(**shortlist['state']), shortlist['accumulator_width'])
    xformat = Format(**shortlist['solution'])
    thresholds = {k:config[k] for k in ('max_snr_loss_db','max_nmse_ratio')}
    thresholds['absolute_snr_min_db'] = config['application_quality']['absolute_snr_min_db']
    selections = [s for s in source['selected_policies'] if s['selected_for_fixed_check']
                  and (not args.domains or s['domain'] in args.domains)
                  and (not args.algorithms or s['algorithm'] in args.algorithms)]
    rows = [r for s in selections for r in source['rows'] if r['recipe_id'] == s['winner']['recipe_id']]
    assert rows
    metas = {m['name']: m for m in source['cases']}
    wavelet = any(m.get('basis_name') for m in metas.values())
    legacy = {c['name']: c for c in outer_cases((23,47,101),False,'lfsr32')
              + outer_cases((23,47,101),True,'lfsr32')}
    cases = {r['case']: restore_case(metas[r['case']], legacy) for r in rows}
    hashes = source_hashes(args.accelerated, wavelet)
    report = {'schema':'v4-lfsr-selected-fixed-application-v1', 'complete':False,
        'scope':'selected_shared_calibration_policies_no_heldout', 'source_sha256':hashes,
        'selection_report': args.float_report.relative_to(ROOT).as_posix(),
        'selection_report_sha256': file_hash(args.float_report), 'accelerated': args.accelerated,
        'python':platform.python_version(),
        'packages':{k:importlib.metadata.version(k) for k in ('numpy','scipy','scikit-image','PyWavelets')},
        'configuration':{**vars(args), 'profile':asdict(profile), 'solution_format':asdict(xformat)},
        'thresholds':thresholds, 'LS_coefficient_diagnostic_rtol':1e-3,
        'selected_policies':selections, 'cases':[metas[name] for name in cases],
        'rows_expected':len(rows), 'rows':[], 'selected_production_profile':None,
        'synthesis_allowed':False, 'raw_signal_transform_hardware_claim':False}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    def save():
        args.output.write_text(json.dumps(json_ready(report),indent=2,allow_nan=False)+'\n',encoding='utf-8')
    save()
    context = nullcontext()
    if args.accelerated:
        from scripts.v4.fast_integer_study import accelerated_arithmetic
        context = accelerated_arithmetic()
    with context:
        for row in rows:
            result = run_selected(cases[row['case']], row, profile, xformat, thresholds)
            report['rows'].append(result)
            save()
            q = result['quality_full_original_units']
            print(row['case'],row['algorithm'], 'fixed_SNR',q['fixed']['snr_db'] if q else None,
                  'pass',result['combined_pass'],'seconds',round(result['model_seconds'],2),flush=True)
    report['source_unchanged_during_run'] = hashes == source_hashes(args.accelerated, wavelet)
    assert file_hash(args.float_report) == report['selection_report_sha256'], 'selection changed during fixed run'
    report['complete'] = report['source_unchanged_during_run'] and len(report['rows']) == len(rows)
    report['summary'] = {'rows':len(rows), 'combined_pass':sum(r['combined_pass'] for r in report['rows']),
        'quality_no_fault_pass':sum(r['quality_and_no_fault_pass'] for r in report['rows']),
        'LS_diagnostic_fail_rows':sum(not r['LS_diagnostic_pass'] for r in report['rows'])}
    save()
    assert report['complete']
    print(report['summary'],flush=True)


if __name__ == '__main__':
    main()
