"""Actual QR greedy recovery trajectories under frozen calibration policies.

Recorded orthonormal transforms permit coefficient-error energy to measure
signal error without fetching data or regenerating a wavelet transform.
This is a numerical calibration study, not RTL or held-out qualification.
"""
import os
for _name in ('OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS', 'OMP_NUM_THREADS'):
    os.environ[_name] = '1'
import argparse
import ast
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import time
import numpy as np
from models.v4.fixed import Format, Profile
from models.v4.recovery import Policy, run
from scripts.v4.generated_numeric_study import make_matrix
from scripts.v4.numeric_screen import digest
import models.v4.qr as qr_module

ROOT = Path(__file__).resolve().parents[2]
ALGORITHMS = ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP')


def cache_signature(profile,rtol,refinements):
    return json.dumps(dict(profile=profile,storage=dict(width=24,frac=20),
                           rtol=str(rtol),refinements=refinements),sort_keys=True)


def memoized_backend(study,reports,refinements):
    """Reuse only exact QR solves; outer decisions and certificates execute now."""
    original=qr_module.IntegerQRKernels;cache={};stats=dict(hits=0,misses=0,fresh_certificates=0)
    policies={}
    for path in reports:
        for row in json.loads(path.read_text())['rows']:
            policies[(row['case'],row['algorithm'])]=row
    for row in study['rows']:
        if row['report']['status']!='success' or row['raw_x'] is None:continue
        old=policies[(row['case'],row['algorithm'])]
        signature=cache_signature(old['profile'],old['fixed_policy']['ls_normal_rtol'],study['max_refinements'])
        key=(row['quantized_B_sha256'],row['quantized_y_sha256'],tuple(row['ordered_support']),signature)
        value=dict(raw_x=row['raw_x'],report=row['report'])
        if key in cache and cache[key]!=value:raise ValueError('inconsistent QR cache duplicate')
        cache[key]=value
    class CachedQR(original):
        def least_squares(self,support):
            profile=dict(data=dict(width=self.profile.data.width,frac=self.profile.data.frac),
                         coefficient=dict(width=self.profile.coefficient.width,frac=self.profile.coefficient.frac),
                         state=dict(width=self.profile.state.width,frac=self.profile.state.frac),accumulator_width=self.profile.accumulator_width)
            key=(digest(self.arithmetic.decode(self.a[:,support],self.profile.coefficient)),digest(self.decode(self.y)),tuple(support),
                 cache_signature(profile,self.policy.ls_normal_rtol,self.max_refinements))
            if key not in cache:
                stats['misses']+=1
                answer=super().least_squares(support)
                cache[key]=dict(raw_x=[int(x)//4 for x in answer],report=deepcopy(self.last_ls_report))
                self.last_ls_report['numerical_cache']=dict(hit=False)
                return answer
            saved=cache[key];report=deepcopy(saved['report']);self.last_ls_report=deepcopy(report)
            candidate=np.asarray([int(x)*4 for x in saved['raw_x']],dtype=object)
            if len(candidate)!=len(support) or any(not -(1<<23)<=int(x)<1<<23 for x in saved['raw_x']):
                raise ValueError('invalid cached X24 payload')
            self._guard();normal=self.mv(self.y,transpose=True,support=support);self._guard()
            rhs=self._dot(normal,normal);passed,_=self._certificate(candidate,support,rhs)
            if not passed:raise ArithmeticError('cached_qr_certificate_failed')
            validation=deepcopy(self.last_ls_report['certificate_history'][-1])
            extra={k:v-report['counts'].get(k,0) for k,v in self.last_ls_report['counts'].items()}
            self.last_ls_report=report
            self.last_ls_report['numerical_cache']=dict(hit=True,fresh_certificate=validation,revalidation_counts=extra)
            self.last_candidate=candidate.copy();self.ls_steps=report['steps']
            stats['hits']+=1;stats['fresh_certificates']+=1
            return candidate
    return CachedQR,stats


def hashes(paths):
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in paths}


def recovery_compatibility(archived,current):
    """Verify unchanged arithmetic/global definitions and complete outer loop."""
    def parts(path):
        module=ast.parse(path.read_text())
        run_node=next(n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='run')
        globals_ast=ast.Module(body=[n for n in module.body if n is not run_node],type_ignores=[])
        start=next(i for i,n in enumerate(run_node.body) if isinstance(n,ast.Assign) and
                   isinstance(n.targets[0],ast.Tuple) and [getattr(e,'id',None) for e in n.targets[0].elts]==['x','support','r'])
        outer_ast=ast.Module(body=run_node.body[start:],type_ignores=[])
        return [ast.dump(node,include_attributes=False) for node in (globals_ast,outer_ast)]
    old,new=parts(archived),parts(current)
    if old!=new:raise ValueError('recovery arithmetic/global definitions or outer recurrence changed')
    return dict(compatible=True,method='AST equality of every module definition except run, plus the entire run body from initial X/support/residual through return; only backend dispatcher prefix may differ',
                globals_ast_sha256=hashlib.sha256(old[0].encode()).hexdigest(),outer_ast_sha256=hashlib.sha256(old[1].encode()).hexdigest(),
                archived_source_sha256=hashlib.sha256(archived.read_bytes()).hexdigest(),current_source_sha256=hashlib.sha256(current.read_bytes()).hexdigest())


def quality(error, denominator, size):
    nmse = error / denominator if denominator else (0.0 if error == 0 else math.inf)
    return dict(mse=error / size, nmse=nmse,
                snr_db=-10 * math.log10(nmse) if nmse else math.inf)


def restore(meta):
    values = dict(a=make_matrix(meta['seed'], meta['M'], meta['N'],
                               1 / math.sqrt(meta['M']), 'lfsr32'),
                  y=np.asarray(meta['measurement']), truth=np.asarray(meta['truth']),
                  original=np.asarray(meta['original']))
    for name, field in [('a', 'operator_sha256'), ('y', 'measurement_sha256'),
                        ('truth', 'truth_sha256'), ('original', 'original_sha256')]:
        if digest(values[name]) != meta[field]:
            raise ValueError('persisted input digest mismatch: ' + name)
    transform = meta.get('transform')
    if transform:
        for field in ('orthogonality_max_abs_error', 'closure_max_abs_error'):
            if transform[field] > 1e-10:
                raise ValueError('recorded transform does not satisfy energy equivalence')
        if meta['original_reconstruction_max_abs_error'] > 1e-10:
            raise ValueError('recorded transform reconstruction exceeds tolerance')
    if not math.isfinite(meta['scale']) or meta['scale'] <= 0:
        raise ValueError('positive recorded scale required')
    return values


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--refinements', type=int, default=2)
    parser.add_argument('--limit', type=int, default=0)
    parser.add_argument('--support-study',type=Path,default=ROOT/'reports/v4/qr_support_study.json')
    parser.add_argument('--support-archive',type=Path,default=ROOT/'reports/v4/qr_support_audit_20260909')
    args = parser.parse_args(argv)
    reports = [ROOT / f'reports/v4/lfsr_tuned_{name}_fixed.json'
               for name in ('synthetic', 'wavelet')]
    paths = [Path(__file__).resolve(), ROOT / 'models/v4/qr.py',
             ROOT / 'models/v4/recovery.py', ROOT / 'models/v4/fixed.py',
             ROOT / 'scripts/v4/generated_numeric_study.py',
             ROOT / 'scripts/v4/numeric_screen.py', ROOT / 'models/v4/lfsr_operator.py',
             *reports,args.support_study.resolve(),args.support_archive.resolve()/'sources/models/v4/recovery.py']
    before = hashes(paths)
    study=json.loads(args.support_study.read_text())
    if not study['complete'] or not study['source_unchanged']:raise ValueError('complete source-bound QR study required')
    for source in ('models/v4/qr.py','models/v4/fixed.py'):
        if study['source_hashes'][source]!=before[source]:raise ValueError('QR cache arithmetic source mismatch')
    archived=args.support_archive/'sources/models/v4/recovery.py'
    if hashlib.sha256(archived.read_bytes()).hexdigest()!=study['source_hashes']['models/v4/recovery.py']:
        raise ValueError('archived recovery source does not match support study')
    compatibility=recovery_compatibility(archived,ROOT/'models/v4/recovery.py')
    cached,cache_stats=memoized_backend(study,reports,args.refinements)
    qr_module.IntegerQRKernels=cached
    result = dict(schema='qr_actual_greedy_calibration_v1', complete=False,
                  source_hashes=before, rows=[], max_refinements=args.refinements,
                  scope='Actual five greedy QR outer recurrences; fixed calibration policies; '
                        'no retuning or LSQR fallback; no RTL/full-eleven/held-out qualification',
                  quality_method='Squared coefficient error divided by recorded scale squared '
                        'equals signal error for the recorded orthonormal transforms. Full '
                        'signal denominator includes its mean; centered denominator is diagnostic. '
                        'Float reference metrics are frozen selection results, not rerun here.',
                  numerical_cache_method='Exact B/y/ordered support/profile/X24/rtol/refinement keyed QR rawX/report replay; '
                        'fresh original-operator RHS and stored-X certificate on every hit; real QR on misses. '
                        'Outer correlations/support choices execute normally. Runtime acceleration only, not RTL cycle reduction.',
                  cache_stats=cache_stats)
    result['recovery_dispatcher_compatibility']=compatibility
    started = time.time()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for path in reports:
        historical = json.loads(path.read_text())
        cases = {m['name']: m for m in historical['cases']}
        for old in historical['rows']:
            if old['algorithm'] not in ALGORITHMS:
                continue
            if args.limit and len(result['rows']) >= args.limit:
                break
            meta = cases[old['case']]
            values = restore(meta)
            gain = old['normalization']['gain']
            p = old['profile']
            profile = Profile(Format(**p['data']), Format(**p['coefficient']),
                              Format(**p['state']), p['accumulator_width'])
            answer = run(old['algorithm'], values['a'], values['y'] * gain,
                         Policy(**old['fixed_policy']), profile, ls_solver='qr',
                         solution_format=Format(24, 20), qr_max_refinements=args.refinements)
            coefficients = answer.x / gain
            error = float(np.sum((coefficients - values['truth']) ** 2)) / meta['scale'] ** 2
            original = values['original']
            full = quality(error, float(np.sum(original ** 2)), len(original))
            centered = quality(error, float(np.sum((original - meta['mean']) ** 2)), len(original))
            floating = old['float_quality_from_selection']
            float_centered = quality(floating['mse'] * len(original),
                                     float(np.sum((original - meta['mean']) ** 2)), len(original))
            thresholds = historical['thresholds']
            loss = floating['snr_db'] - full['snr_db']
            ratio = full['nmse'] / floating['nmse'] if floating['nmse'] else (1 if full['nmse'] == 0 else math.inf)
            no_fault = not any(answer.events.values()) and not any(t['phase'] == 'FAULT' for t in answer.trace)
            quality_pass = (loss <= thresholds['max_snr_loss_db'] and
                            ratio <= thresholds['max_nmse_ratio'] and
                            full['snr_db'] >= thresholds['absolute_snr_min_db'])
            prior = old['fixed_result']
            old_path = [t['support'] for t in prior['solver_trace']]
            new_path = [t['support'] for t in answer.solver_trace]
            row = dict(case=old['case'], domain=old['domain'], algorithm=old['algorithm'],
                       source_report=path.relative_to(ROOT).as_posix(), fixed_policy=old['fixed_policy'],
                       input_hashes={k: v for k, v in meta.items() if k.endswith('_sha256')},
                       transform=meta.get('transform'), normalization=old['normalization'],
                       full_quality=full, centered_quality=centered, float_quality=floating,
                       float_centered_quality=float_centered,
                       old_lsqr_quality=old['quality_full_original_units'],
                       snr_loss_db=loss, nmse_ratio=ratio, quality_pass=quality_pass,
                       no_fault=no_fault, combined_pass=quality_pass and no_fault,
                       status=answer.status, old_status=prior['status'],
                       status_changed=answer.status != prior['status'],
                       support=answer.support, old_support=prior['support'],
                       support_changed=answer.support != prior['support'],
                       solve_support_trajectory_changed=new_path != old_path,
                       raw_x=answer.raw_x, raw_x_format=answer.raw_x_format,
                       raw_x_changed=answer.raw_x != prior['raw_x'], events=answer.events,
                       outer_commits=sum(t['phase'] == 'COMMIT' for t in answer.trace),
                       old_outer_commits=sum(t['phase'] == 'COMMIT' for t in prior['trace']),
                       qr_solves=len(answer.solver_trace),
                       qr_refinements=sum(t.get('refinement_steps', 0) for t in answer.solver_trace),
                       old_lsqr_iteration_counts=prior.get('solver_trace_counts'),
                       trace=answer.trace, solver_trace=answer.solver_trace)
            result['rows'].append(row)
            args.output.write_text(json.dumps(result, indent=2) + '\n')
            print(f"QR application {len(result['rows'])}: {old['algorithm']} {old['case']} "
                  f"status={answer.status} quality={row['combined_pass']} SNR={full['snr_db']:.3f}", flush=True)
    result.update(complete=True, source_unchanged=before == hashes(paths), seconds=time.time() - started)
    result['summary'] = dict(rows=len(result['rows']), passed=sum(r['combined_pass'] for r in result['rows']),
                             status_changes=sum(r['status_changed'] for r in result['rows']),
                             support_changes=sum(r['support_changed'] for r in result['rows']),
                             trajectory_changes=sum(r['solve_support_trajectory_changed'] for r in result['rows']))
    groups = {}
    for row in result['rows']:
        key = row['algorithm'] + '/' + row['domain']
        group = groups.setdefault(key, dict(rows=0, passed=0, status_changes=0,
                                           support_changes=0, trajectory_changes=0,
                                           min_snr_db=math.inf, max_snr_loss_db=-math.inf,
                                           max_nmse_ratio=0))
        group['rows'] += 1
        group['passed'] += int(row['combined_pass'])
        group['status_changes'] += int(row['status_changed'])
        group['support_changes'] += int(row['support_changed'])
        group['trajectory_changes'] += int(row['solve_support_trajectory_changed'])
        group['min_snr_db'] = min(group['min_snr_db'], row['full_quality']['snr_db'])
        group['max_snr_loss_db'] = max(group['max_snr_loss_db'], row['snr_loss_db'])
        group['max_nmse_ratio'] = max(group['max_nmse_ratio'], row['nmse_ratio'])
    result['by_algorithm_domain'] = groups
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result['summary']), flush=True)
    if not result['source_unchanged']:
        raise SystemExit('source changed during application study')


if __name__ == '__main__':
    main()
