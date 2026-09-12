"""Source-bound QR-only study on previously observed ordered LS supports.

Support replay qualifies a numerical subproblem, not complete QR recovery
programs, outer support trajectories, application quality or RTL performance.
"""
import os
for name in ('OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','OMP_NUM_THREADS'):os.environ[name]='1'
import argparse
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import time
import numpy as np
from models.v4.fixed import Format,Profile
from models.v4.qr import IntegerQRKernels
from models.v4.recovery import Policy
from scripts.v4.generated_numeric_study import make_matrix
from scripts.v4.numeric_screen import digest

ROOT=Path(__file__).resolve().parents[2]

def hashes(paths):
    return {str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports',nargs='+',type=Path,default=[ROOT/'reports/v4/lfsr_tuned_synthetic_fixed.json',ROOT/'reports/v4/lfsr_tuned_wavelet_fixed.json'])
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--limit',type=int,default=0)
    parser.add_argument('--refinements',type=int,default=2)
    args=parser.parse_args(argv)
    sources=[Path(__file__).resolve(),ROOT/'models/v4/qr.py',ROOT/'models/v4/fixed.py',ROOT/'models/v4/recovery.py',
             ROOT/'scripts/v4/lfsr_application_fixed_validation.py',ROOT/'scripts/v4/generated_numeric_study.py',
             ROOT/'scripts/v4/lfsr_basis_feasibility.py',ROOT/'models/v4/lfsr_operator.py',*[p.resolve() for p in args.reports]]
    before=hashes(sources);started=time.time()
    result=dict(schema='householder_qr_support_study_v1',complete=False,source_hashes=before,rows=[],
                max_refinements=args.refinements,limit=args.limit,
                scope='QR numerical support replay; not full outer/application/RTL qualification; no LSQR fallback',
                references=['https://www.netlib.org/lapack/explore-html/d8/d0d/group__larfg_gadc154fac2a92ae4c7405169a9d1f5ae9.html',
                            'https://www.netlib.org/lapack/explore-html/d0/da1/group__geqrf_gade26961283814bb4e62183d9133d8bf5.html'])
    cache={};restored={};total=0
    args.output.parent.mkdir(parents=True,exist_ok=True)
    for report_path in args.reports:
        report=json.loads(report_path.read_text());metas={m['name']:m for m in report['cases']}
        total+=sum(len(r.get('LS_observations',[])) for r in report['rows'])
        for row in report['rows']:
            if not row.get('LS_observations'):continue
            identity=(str(report_path),row['case'])
            if identity not in restored:
                meta=metas[row['case']]
                case={'a':make_matrix(meta['seed'],meta['M'],meta['N'],1/math.sqrt(meta['M']),'lfsr32'),
                      'y':np.asarray(meta['measurement'],dtype=float),'truth':np.asarray(meta['truth'],dtype=float),
                      'original':np.asarray(meta['original'],dtype=float)}
                for field,key in [('a','operator_sha256'),('y','measurement_sha256'),('truth','truth_sha256'),('original','original_sha256')]:
                    if digest(case[field])!=meta[key]:raise ValueError('persisted application input hash mismatch: '+field)
                restored[identity]=case
            case=restored[identity];profile=Profile(Format(**row['profile']['data']),Format(**row['profile']['coefficient']),Format(**row['profile']['state']),row['profile']['accumulator_width'])
            policy=Policy(**row['fixed_policy']);gain=row['normalization']['gain']
            for index,audit in enumerate(row['LS_observations']):
                if args.limit and len(result['rows'])>=args.limit:break
                support=audit['ordered_support'];key=(identity,tuple(support),gain,policy.ls_normal_rtol)
                reused=key in cache
                if not reused:
                    backend=IntegerQRKernels(case['a'],np.asarray(case['y'])*gain,policy,profile,max_refinements=args.refinements)
                    b=backend.arithmetic.decode(backend.a[:,support],profile.coefficient);y=backend.decode(backend.y)
                    if digest(b)!=audit['quantized_B_sha256'] or digest(y)!=audit['quantized_y_sha256']:
                        raise ValueError('reconstructed case differs from historical support input hash')
                    answer=None
                    try:answer=backend.least_squares(support)
                    except ArithmeticError:pass
                    diagnostic=backend.diagnostics(support)
                    cache[key]=dict(report=backend.last_ls_report,diagnostics=diagnostic,
                                    quantized_B_sha256=digest(b),quantized_y_sha256=digest(y),
                                    raw_x=None if answer is None else [int(v)//4 for v in answer])
                entry=dict(case=row['case'],algorithm=row['algorithm'],support_index=index,ordered_support=support,reused=reused,**cache[key])
                result['rows'].append(entry)
                if len(result['rows'])%10==0:
                    print(f"QR supports={len(result['rows'])} unique={len(cache)} success={sum(x['report']['status']=='success' for x in result['rows'])}",flush=True)
                    args.output.write_text(json.dumps(result,indent=2)+'\n')
    result.update(complete=True,total_historical_supports=total,unique_solves=len(cache),source_unchanged=before==hashes(sources),seconds=time.time()-started)
    statuses={}
    for row in result['rows']:statuses[row['report']['status']]=statuses.get(row['report']['status'],0)+1
    result['summary']=dict(statuses=statuses,first_certificate_pass=sum(bool(r['report']['certificate_history'] and r['report']['certificate_history'][0]['passed']) for r in result['rows']),
                           diagnostic_coefficient_pass=sum(r['diagnostics'].get('coefficient_relative_error',1e99)<=1e-3 for r in result['rows']))
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result['summary']),flush=True)
    if not result['source_unchanged']:raise SystemExit('source changed during numerical study')

if __name__=='__main__':main()
