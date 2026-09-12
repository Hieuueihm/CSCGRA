"""LFSR calibration of job normalization, persistent X precision and LS stop.

All solvers see only B/y and an explicit numerical policy. SVD, conditioning,
quality and storage-floor diagnostics are outside the solver. A completed
study does not freeze a production bit profile or establish application fit.
"""
from __future__ import annotations
import argparse
from collections import Counter
from dataclasses import asdict
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import sys
import time
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from models.v4.fixed import Arithmetic,Format
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.normalization import Normalization
from models.v4.recovery import Policy
from models.v4.quality import compare
from models.v4.lfsr_operator import operator_identity
from scripts.v4.generated_numeric_study import ls_cases,PROFILES,QUALITY
from scripts.v4.numeric_screen import digest,sanitized
from scripts.v4.solver_study import relative_norm,normal_diagnostics

CONFIGS={
    'raw_D18_X18_t4': ('baseline',Format(18,14),False,1e-4),
    'norm_D18_X18_t4': ('baseline',Format(18,14),True,1e-4),
    'norm_D18_X22_t4': ('baseline',Format(22,18),True,1e-4),
    'norm_D18_X22_t5': ('baseline',Format(22,18),True,1e-5),
    'norm_D18_X23_t5': ('baseline',Format(23,19),True,1e-5),
    'norm_D20_X23_t5': ('data20',Format(23,19),True,1e-5),
    'norm_D18_S30_X24_t5': ('state30',Format(24,20),True,1e-5),
    'norm_D18_S27F22_X24_t5': ('state_frac22',Format(24,20),True,1e-5),
}
SPLITS={'calibration':[23,47,101],'matrix_validation':[211,509,997]}


def source_hashes():
    paths=list((ROOT/'models/v4').glob('*.py'))+[Path(__file__),
        ROOT/'scripts/v4/generated_numeric_study.py',ROOT/'scripts/v4/solver_study.py',
        ROOT/'scripts/v4/numeric_screen.py']
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def configuration(name):
    p,x,n,t=CONFIGS[name]
    return {'profile':asdict(PROFILES[p]),'solution_format':asdict(x),
            'normalization':n,'target_peak':.5,'ls_normal_rtol':t,'ls_max_iterations':128}


def run_case(case,name):
    pname,xf,normalize,rtol=CONFIGS[name]; p=PROFILES[pname]
    a=np.asarray(case['a']); support=case['support']; b0=a[:,support]
    y0=np.asarray(case['y'])
    normalization=Normalization.derive(y0) if normalize else None
    y=normalization.encode(y0) if normalization else y0.copy()
    gain=normalization.gain if normalization else 1.
    policy=Policy(len(support),ls_max_iterations=128,ls_normal_rtol=rtol)
    # LS on ordered B is independent of unselected dictionary columns. This
    # avoids repeated full-N constructor work without changing the recurrence.
    backend=IntegerLSQRKernels(b0,y,policy,p,solution_format=xf)
    b=backend.arithmetic.decode(backend.a,p.coefficient); yq=backend.decode(backend.y)
    oracle,_,rank,singular=np.linalg.lstsq(b,yq,rcond=None)
    original=np.linalg.lstsq(b0,y0,rcond=None)[0]
    ar=Arithmetic(p); oracle_X=ar.decode(ar.quantize(oracle,xf),xf)
    denominator=np.linalg.norm(b.T@yq)
    rounding_bound=(singular[0]**2)*np.sqrt(len(support))/(2*xf.scale)
    rounding_bound_valid=not any(ar.events.values()) and denominator>0
    rounding_bound_relative=rounding_bound/denominator if rounding_bound_valid else None
    start=time.perf_counter(); accepted=None; error=None
    try:
        accepted=backend.least_squares(list(range(len(support))))
    except ArithmeticError as exc:
        error=str(exc)
    elapsed=time.perf_counter()-start
    raw=backend.last_candidate
    candidate=None if raw is None else backend.decode(raw)
    row={'case':case['name'],'track':case['track'],'configuration':name,
         'normalization':normalization.descriptor if normalization else {'exponent':0,'gain':1.,'mode':'raw'},
         'accepted':accepted is not None,'status':'accepted' if accepted is not None else error,
         'events':dict(backend.events),'steps':backend.ls_steps,'solver_seconds':elapsed,
         'rank':int(rank),'condition':float(singular[0]/singular[-1]) if singular[-1] else None,
         'quantized_B_sha256':digest(b),'quantized_y_sha256':digest(yq),
         'oracle':'numpy SVD on same quantized B/y; never used by solver',
         'input_operator_coefficient_error':relative_norm(oracle/gain-original,original),
         'input_operator_error_scope':'combined measurement D and coefficient C quantization; no recurrence/storage error',
         'X_rounded_oracle':{**normal_diagnostics(b,yq,oracle_X),'events':dict(ar.events),
                              'normal_rounding_upper_bound_relative':rounding_bound_relative,
                              'normal_rounding_bound_applicable':rounding_bound_valid,
                              'bound_is_not_proof_that_every_grid_solution_fails':True},
         'candidate':None,'diagnostic_pass':False,
         'application_qualification':False,'production_profile_frozen':False}
    if candidate is not None:
        normal=normal_diagnostics(b,yq,candidate)
        err=relative_norm(candidate-oracle,oracle)
        quality=compare(case['truth'],original,candidate/gain,**QUALITY)
        before=backend.decode(backend.last_pre_storage)
        pre_normal=normal_diagnostics(b,yq,before)
        xraw=[int(backend.arithmetic.rescale(int(v),p.state.frac,xf)) for v in raw]
        row['candidate']={**normal,'coefficient_relative_error':err,
            'prediction_relative_error':relative_norm(b@(candidate-oracle),b@oracle),
            'pre_storage_normal':pre_normal,'storage_roundoff_norm':float(np.linalg.norm(candidate-before)),
            'quality_original_units':quality,'raw_X':xraw,'raw_X_format':asdict(xf),
            'output_scale_exponent':-(normalization.exponent if normalization else 0),
            'normal_float64_pass':bool(normal['normal_relative']<=rtol),
            'coefficient_diagnostic_pass':bool(err<=1e-3),'accepted_output':accepted is not None}
        row['diagnostic_pass']=bool(accepted is not None and not any(backend.events.values())
            and normal['normal_relative']<=rtol and err<=1e-3 and quality['arithmetic_quality_pass'])
    report=backend.last_ls_report.copy()
    report['certificate_history']=[{k:v for k,v in item.items() if k!='stored'}
                                   for item in report['certificate_history']]
    row['solver_report']=report
    return row


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--split',choices=SPLITS,default='calibration')
    parser.add_argument('--configs',nargs='+',choices=CONFIGS,default=list(CONFIGS))
    parser.add_argument('--case-contains',default='')
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    cases=ls_cases(SPLITS[args.split],'lfsr32')
    if args.split=='matrix_validation':
        cases=[c for c in cases if c['track']=='generated_identity_LS']
    cases=[c for c in cases if args.case_contains in c['name']]
    if not cases: raise ValueError('empty case selection')
    sources=source_hashes()
    report={'schema':'v4-lfsr-numeric-contract-v1','complete':False,'split':args.split,
        'generator':'LFSR32 selected by user; no superiority claim',
        'seeds':SPLITS[args.split],'source_sha256':sources,
        'python':platform.python_version(),'packages':{n:importlib.metadata.version(n) for n in ['numpy','scipy']},
        'configuration':{n:configuration(n) for n in args.configs},
        'diagnostic_gate':{'normal_float64_rtol':'same as runtime policy','coefficient_relative_rtol':1e-3,
             **QUALITY,'finite_arithmetic_and_runtime_acceptance_required':True},
        'matrix_validation_is_not_patient_scene_heldout':True,
        'cases':[],'rows':[],'selected_production_profile':None}
    for c in cases:
        meta={k:v for k,v in c.items() if k not in ['a','y','truth']}
        meta.update({'A_sha256':digest(c['a']),'y_sha256':digest(c['y']),'truth_sha256':digest(c['truth'])})
        if c['track']=='generated_identity_LS':
            meta['operator']=operator_identity(c['seed'],*c['a'].shape,abs(float(c['a'][0,0])))
        report['cases'].append(meta)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    def save(): args.output.write_text(json.dumps(sanitized(report),indent=2,allow_nan=False)+'\n',encoding='utf-8')
    save()
    for c in cases:
        for name in args.configs:
            row=run_case(c,name); report['rows'].append(row); save()
            print(c['name'],name,'PASS' if row['diagnostic_pass'] else 'FAIL',row['status'],row['steps'],flush=True)
    report['source_unchanged_during_run']=sources==source_hashes()
    report['complete']=report['source_unchanged_during_run']
    report['summary']={n:{'rows':sum(r['configuration']==n for r in report['rows']),
        'accepted':sum(r['configuration']==n and r['accepted'] for r in report['rows']),
        'diagnostic_pass':sum(r['configuration']==n and r['diagnostic_pass'] for r in report['rows']),
        'statuses':dict(Counter(r['status'] for r in report['rows'] if r['configuration']==n))} for n in args.configs}
    save()
    if not report['complete']: raise RuntimeError('numerical source changed during study')
    print(json.dumps(report['summary']),flush=True)


if __name__=='__main__': main()
