"""Generated-operator / fixed LSQR calibration, with all failures retained.

This is a numerical study, not a profile freeze or FPGA performance report.
Applications use an explicit coefficient-domain encoder transform; no raw-signal
Phi*Psi hardware claim is made. Independent LS SVD/QR comparisons use the same
quantized B/y as the integer solver, separating solver and input errors.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
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
from models.v4.fixed import Arithmetic, Format, Profile
from models.v4 import recovery, proximal
from models.v4.generated_operator import generated_matrix
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.quality import compare, signed_dot_width
from scripts.v4.solver_study import ObservedCGLS, cases as stress_cases, normal_diagnostics, relative_norm
from scripts.v4.numeric_screen import digest, sanitized


def profile(d, df, c, cf, s, sf):
    return Profile(Format(d, df), Format(c, cf), Format(s, sf), signed_dot_width(s, s, 1024))


PROFILES = {
    'compact': profile(16,12,16,14,24,16),
    'baseline': profile(18,14,18,16,27,19),
    'data20': profile(20,16,18,16,27,19),
    'state30': profile(18,14,18,16,30,22),
    'state_frac22': profile(18,14,18,16,27,22),
    'coefficient16': profile(18,14,16,14,27,19),
    'wide_control': profile(24,20,18,16,32,24),
}
SEEDS = (23, 47, 101)
NORMAL_RTOL = 1e-4
COEFFICIENT_RTOL = 1e-3  # calibration diagnostic, not final rank-aware contract
QUALITY = {'max_snr_loss_db': 0.5, 'max_nmse_ratio': 1.1}


def noisy(clean, rng, snr):
    noise = rng.normal(size=len(clean))
    return clean + noise * np.linalg.norm(clean) * 10**(-snr/20) / np.linalg.norm(noise)


def make_matrix(seed, rows, columns, scale, generator):
    if generator=='threefry':
        return generated_matrix(seed,rows,columns,scale)
    from models.v4.lfsr_operator import lfsr32_matrix
    return lfsr32_matrix(seed,rows,columns,scale)


def ls_cases(seeds, generator):
    result = []
    for seed in seeds:
        a = make_matrix(seed, 128, 1024, 1/math.sqrt(128), generator)
        for s, snr, amplitude in [(8,30,1.), (32,30,1.), (96,30,1.), (32,50,1.), (8,30,.001)]:
            rng = np.random.default_rng(seed * 10000 + s * 10 + snr)
            support = rng.choice(1024, s, replace=False).tolist()
            truth = rng.uniform(-.45,.45,s) * amplitude
            y = noisy(a[:,support]@truth, rng, snr)
            result.append({'name':f'generated_m128_s{s}_noise{snr}_amp{amplitude:g}_seed{seed}',
                'a':a,'y':y,'support':support,'truth':truth,'seed':seed,
                'track':'generated_identity_LS', 'snr':snr, 'amplitude':amplitude})
    if seeds:
        seed = seeds[0]
        rng = np.random.default_rng(seed+789)
        a = make_matrix(seed,37,67,1/math.sqrt(37),generator)
        support = [66, 0, 31, 8, 32, 9, 65]
        truth = rng.uniform(-.4,.4,len(support))
        result.append({'name':'generated_tail_m37_n67_s7','a':a,'y':noisy(a[:,support]@truth,rng,30),
            'support':support,'truth':truth,'seed':seed,'track':'generated_identity_LS','snr':30})
        for c in stress_cases():
            result.append({**c,'track':'general_dense_solver_stress_not_generated_Phi','snr':30})
    return result


class ObservedLSQR(IntegerLSQRKernels):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.observed_candidates = []

    def certificate(self, coefficients, support, rhs_energy):
        accepted = super().certificate(coefficients,support,rhs_energy)
        self.observed_candidates.append(self.decode(coefficients).copy())
        return accepted


class CountedCGLS(ObservedCGLS):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.counts = {}
        self.last_ls_report = None

    def mv(self, *args, **kwargs):
        self.counts['GEMV'] = self.counts.get('GEMV',0)+1
        return super().mv(*args, **kwargs)

    def dot(self, *args, **kwargs):
        self.counts['DOT'] = self.counts.get('DOT',0)+1
        return super().dot(*args, **kwargs)

    def ratio(self, *args, **kwargs):
        self.counts['DIV'] = self.counts.get('DIV',0)+1
        return super().ratio(*args, **kwargs)

    def least_squares(self, support):
        self.counts = {}; status='certified'
        try:
            return super().least_squares(support)
        except ArithmeticError as exc:
            status=str(exc)
            raise
        finally:
            self.last_ls_report={'solver':'CGLS','status':status,'steps':self.ls_steps,
                'counts':dict(self.counts),'certificate_checks':len(self.candidates),
                'count_scope':'LS including initialization and every certificate; no outer/constructor costs'}


def isolate(case, p, solver):
    policy = recovery.Policy(sparsity=len(case['support']), ls_normal_rtol=NORMAL_RTOL, ls_max_iterations=128)
    cls = ObservedLSQR if solver == 'lsqr' else CountedCGLS
    k = cls(case['a'],case['y'],policy,p)
    b = k.arithmetic.decode(k.a[:,case['support']],p.coefficient)
    y = k.decode(k.y)
    oracle, _, rank, singular = np.linalg.lstsq(b,y,rcond=None)
    original = np.linalg.lstsq(case['a'][:,case['support']],case['y'],rcond=None)[0]
    accepted, status = None, 'certified'
    started = time.perf_counter()
    try:
        if any(k.events.values()):
            raise ArithmeticError('numeric_fault')
        accepted = k.decode(k.least_squares(case['support']))
        if any(k.events.values()):
            accepted = None
            raise ArithmeticError('numeric_fault')
    except ArithmeticError as e:
        status = str(e)
    elapsed = time.perf_counter()-started
    if solver == 'lsqr':
        candidates = k.observed_candidates
    else:
        candidates = [c['x'] for c in k.candidates]
    last = accepted if accepted is not None else (candidates[-1] if candidates else None)
    ar = Arithmetic(p)
    rounded_oracle = ar.decode(ar.quantize(oracle,p.data),p.data)
    row = {'case':case['name'],'track':case['track'],'solver':solver,'profile_id':p.name,
        'status':status,'accepted':accepted is not None,'events':dict(k.events),
        'iterations':k.ls_steps,'solver_elapsed_seconds':elapsed,
        'condition_quantized':float(singular[0]/singular[-1]) if singular[-1] else math.inf,
        'rank_quantized':int(rank),'support_size':len(case['support']),
        'oracle_method':'numpy.linalg.lstsq rcond=None SVD minimum norm',
        'oracle_normal':normal_diagnostics(b,y,oracle),
        'operator_input_only_coefficient_error':relative_norm(oracle-original,original),
        'D_rounded_oracle':{**normal_diagnostics(b,y,rounded_oracle),'events':dict(ar.events)},
        'last_candidate_diagnostic_only_if_failed':None,
        'solver_report':getattr(k,'last_ls_report',None),'screen_pass':False}
    if rank == len(case['support']) and b.shape[0] >= b.shape[1]:
        q,r = np.linalg.qr(b,mode='reduced')
        row['QR_SVD_relative_difference'] = relative_norm(np.linalg.solve(r,q.T@y)-oracle,oracle)
    if last is not None:
        d = {**normal_diagnostics(b,y,last),
            'coefficient_relative_error':relative_norm(last-oracle,oracle),
            'prediction_relative_error':relative_norm(b@(last-oracle),b@oracle),
            'quality':compare(case['truth'],original,last,**QUALITY),
            'accepted_output':accepted is not None}
        d['normal_float64_pass'] = d['normal_relative'] <= NORMAL_RTOL
        d['coefficient_agreement_pass'] = d['coefficient_relative_error'] <= COEFFICIENT_RTOL
        row['last_candidate_diagnostic_only_if_failed'] = d
        row['screen_pass'] = bool(accepted is not None and not any(k.events.values()) and
            d['normal_float64_pass'] and d['coefficient_agreement_pass'] and d['quality']['arithmetic_quality_pass'])
    return row


def outer_cases(seeds, applications, generator):
    result = []
    for seed in seeds:
        rng = np.random.default_rng(seed+420)
        n,m,s = 256,128,8
        truth = np.zeros(n)
        truth[rng.choice(n,s,replace=False)] = rng.uniform(.2,.5,s)*rng.choice([-1,1],s)
        a = make_matrix(seed,m,n,1/math.sqrt(m),generator)
        result.append({'name':f'synthetic_n{n}_m{m}_k{s}_seed{seed}','a':a,
            'y':noisy(a@truth,rng,30),'truth':truth,'seed':seed,'k':s,
            'track':'generated_identity_outer','restore':lambda x:x,'original':truth,
            'source':{'kind':'synthetic_exact_sparse','sparsified_real_signal':False}})
    # One full N1024 shape, fixed independently of numeric results.
    if seeds and not applications:
        seed=seeds[0]; rng=np.random.default_rng(seed+993)
        n,m,s=1024,128,8
        truth=np.zeros(n); truth[rng.choice(n,s,replace=False)]=rng.uniform(.2,.5,s)*rng.choice([-1,1],s)
        a=make_matrix(seed,m,n,1/math.sqrt(m),generator)
        result.append({'name':f'synthetic_n1024_m128_k8_seed{seed}','a':a,'y':noisy(a@truth,rng,30),
            'truth':truth,'original':truth,'seed':seed,'k':s,'track':'generated_identity_outer',
            'restore':lambda x:x,'source':{'kind':'synthetic_exact_sparse','sparsified_real_signal':False}})
    if applications:
        from scipy import datasets
        from scipy.fft import dct, idct
        from skimage import data
        ecg=datasets.electrocardiogram(); camera=data.camera().astype(float)/255
        for i,(name,raw,source) in enumerate([
            ('ecg_window_3600',ecg[3600:3856],{'loader':'scipy.datasets.electrocardiogram','record':'208 excerpt','samples':[3600,3856]}),
            ('ecg_window_7200',ecg[7200:7456],{'loader':'scipy.datasets.electrocardiogram','record':'208 excerpt','samples':[7200,7456]}),
            ('camera_patch_192_240',camera[192:208,240:256],{'loader':'skimage.data.camera','rows':[192,208],'columns':[240,256]}),
            ('camera_patch_64_64',camera[64:80,64:80],{'loader':'skimage.data.camera','rows':[64,80],'columns':[64,80]}),
        ]):
            shape=raw.shape; mean=float(raw.mean()); scale=.5/max(float(np.max(np.abs(raw-mean))),1e-12)
            centered=(raw-mean)*scale
            if len(shape)==2:
                coeff=dct(dct(centered,norm='ortho',axis=0),norm='ortho',axis=1).reshape(-1)
                def restore(x,shape=shape,scale=scale,mean=mean):
                    return (idct(idct(x.reshape(shape),norm='ortho',axis=0),norm='ortho',axis=1)/scale+mean).reshape(-1)
            else:
                coeff=dct(centered,norm='ortho')
                def restore(x,scale=scale,mean=mean): return idct(x,norm='ortho')/scale+mean
            seed=seeds[i%len(seeds)]; rng=np.random.default_rng(seed+12345+i)
            a=make_matrix(seed,128,256,1/math.sqrt(128),generator)
            result.append({'name':name,'a':a,'y':noisy(a@coeff,rng,30),'truth':coeff,'original':raw.reshape(-1),
                'seed':seed,'k':16,'track':'coefficient_domain_encoder_DCT_not_raw_signal_PhiPsi',
                'restore':restore,'mean':mean,'scale':scale,
                'source':{**source,'sparsified_real_signal':False,'source_window_sha256':digest(raw),
                          'split':'calibration_only_not_patient_or_scene_heldout'}})
    return [c for c in result if (c['track'].startswith('coefficient_domain') if applications else True)]


def outer_row(case, algorithm, p, solver):
    a,y=case['a'],case['y']
    if 'spectral_sq' not in case:
        case['spectral_sq']=float(np.linalg.norm(a,2)**2)
    spectral=case['spectral_sq']
    references=case.setdefault('float_references',{})
    if algorithm in recovery.ALGORITHMS:
        policy=recovery.Policy(case['k'],max_iterations=case['k'] if algorithm in ('OMP','GOMP') else 24,
            step_size=.9/spectral,residual_atol=1e-6)
        if algorithm not in references:
            references[algorithm]=recovery.run(algorithm,a,y,policy)
        floating=references[algorithm]
        fixed=recovery.run(algorithm,a,y,policy,p,ls_solver=solver)
    else:
        policy=proximal.Policy(regularization=.01,max_iterations=24,step_size=.9/spectral,pd_sigma=.9)
        if algorithm not in references:
            references[algorithm]=proximal.run(algorithm,a,y,policy)
        floating=references[algorithm]
        fixed=proximal.run(algorithm,a,y,policy,p)
    fq,xq=case['restore'](floating.x),case['restore'](fixed.x)
    quality=compare(case['original'],fq,xq,**QUALITY)
    fault=any(fixed.events.values()) or any(t['phase']=='FAULT' for t in fixed.trace)
    float_fault=any(t['phase']=='FAULT' for t in floating.trace)
    return {'case':case['name'],'track':case['track'],'algorithm':algorithm,
        'solver':solver if algorithm in ('OMP','GOMP','CoSaMP','SP','HTP') else (
            'shifted_CG' if algorithm=='ADMM' else 'no_LS'),
        'profile_id':p.name,'policy':asdict(policy),'float_status':floating.status,
        'fixed_status':fixed.status,'events':fixed.events,'quality':quality,
        'centered_quality':compare(case['original']-case.get('mean',0),fq-case.get('mean',0),xq-case.get('mean',0),**QUALITY),
        'same_support_diagnostic':floating.support==fixed.support,
        'solver_trace':fixed.solver_trace,'screen_pass':bool(quality['arithmetic_quality_pass'] and not fault and not float_fault),
        'termination_at_fixed_budget_is_not_a_convergence_proof':True,
        'both_residual_tolerance':floating.status=='residual_tolerance' and fixed.status=='residual_tolerance',
        'absolute_application_quality_established':False,'production_gate_pass':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite',choices=['ls','outer','applications'],default='ls')
    parser.add_argument('--generator',choices=['threefry','lfsr32'],default='threefry')
    parser.add_argument('--profiles',nargs='+',choices=PROFILES,default=list(PROFILES))
    parser.add_argument('--seeds',nargs='+',type=int,default=list(SEEDS))
    parser.add_argument('--solvers',nargs='+',choices=['cgls','lsqr'],default=['cgls','lsqr'])
    parser.add_argument('--algorithms',nargs='+',choices=recovery.ALGORITHMS+proximal.ALGORITHMS,
                        default=list(recovery.ALGORITHMS+proximal.ALGORITHMS))
    parser.add_argument('--case-contains',default='')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    dataset=ls_cases(args.seeds,args.generator) if args.suite=='ls' else outer_cases(args.seeds,args.suite=='applications',args.generator)
    dataset=[c for c in dataset if args.case_contains in c['name']]
    if not dataset: raise ValueError('empty study selection')
    if args.suite!='ls':
        for c in dataset:
            original_l=float(np.linalg.norm(c['a'],2)**2)
            magnitude=float(abs(c['a'][0,0]))
            ratios=[]
            for label in args.profiles:
                fmt=PROFILES[label].coefficient
                quantized=math.floor(magnitude*fmt.scale+.5)/fmt.scale
                ratios.append(quantized/magnitude)
            c['spectral_sq']=max([original_l]+[original_l*r*r for r in ratios])
            c['spectral_sq_original']=original_l
    files=[Path(__file__),*sorted((ROOT/'models/v4').glob('*.py')),
           ROOT/'scripts/v4/solver_study.py',ROOT/'scripts/v4/numeric_screen.py']
    hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
    report={'schema':'v4-generated-numeric-study-v1','complete':False,'scope':'calibration_only',
        'configuration':{**vars(args),'output':args.output.as_posix()},'python':platform.python_version(),'numpy':np.__version__,
        'packages':{n:importlib.metadata.version(n) for n in ['numpy','scipy','scikit-image']},
        'profiles':{n:asdict(PROFILES[n]) for n in args.profiles},'source_sha256':hashes,
        'selected_production_profile':None,'synthesis_allowed':False,'paper_claim_ready':False,
        'absolute_application_floors_frozen':False,
        'thresholds':{**QUALITY,'normal_rtol':NORMAL_RTOL,'coefficient_rtol_diagnostic':COEFFICIENT_RTOL},
        'generator_contract':('Threefry2x32-20 v3 coordinate mapping' if args.generator=='threefry' else
            'LFSR32 Galois taps0x80200003 indexed column-major col*M+row; zero seed maps to DEADBEEF')+
            '; revision1; common scale=1/sqrt(M); no column normalization',
        'screen_pass_definition':{'ls':'accepted_no_fault_plus_float64_normal_and_coefficient_agreement_and_relative_quality',
            'outer':'relative_quality_and_no_fault_at_same_budget_only_not_convergence_or_application_adequacy'},
        'cost_claim':'Python runtime and arithmetic counts only; no RTL cycles or throughput',
        'cases':[{'name':c['name'],'track':c['track'],'seed':c['seed'],'M':c['a'].shape[0],'N':c['a'].shape[1],
            'operator_sha256':digest(c['a']),'measurement_sha256':digest(c['y']),'truth_sha256':digest(c['truth']),
            'support':c.get('support'),'source':c.get('source',{'kind':c['track'],'generator':args.generator if c['track'].startswith('generated') else None}),
            'measurement_snr_db':c.get('snr',30),
            'common_spectral_sq_bound':c.get('spectral_sq'),'original_spectral_sq':c.get('spectral_sq_original'),
            'normalization_mean':c.get('mean',0),'normalization_scale':c.get('scale',1)} for c in dataset],
        'rows':[]}
    report['profile_cost_proxies']={name:{
        'vector_three_planes_bits':3*4096*p.state.width,
        'B_payload_bits_at_m128_s96':128*96*p.coefficient.width,
        'C_times_S_27x18_partial_products':min(math.ceil(p.coefficient.width/18)*math.ceil(p.state.width/27),
                                              math.ceil(p.coefficient.width/27)*math.ceil(p.state.width/18)),
        'S_times_S_27x18_partial_products':math.ceil(p.state.width/18)*math.ceil(p.state.width/27),
        'accumulator_bits':p.accumulator_width,
        'not_measured_DSP_count_or_cycles':True} for name,p in PROFILES.items() if name in args.profiles}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    def save():
        args.output.write_text(json.dumps(sanitized(report),indent=2,allow_nan=False)+'\n',encoding='utf-8')
    save()
    for c in dataset:
        for label in args.profiles:
            p=PROFILES[label]
            targets=[(s,None) for s in args.solvers] if args.suite=='ls' else [
                (s,a) for a in args.algorithms for s in (args.solvers if a in ('OMP','GOMP','CoSaMP','SP','HTP') else [args.solvers[-1]])]
            for solver,algorithm in targets:
                start=time.perf_counter()
                try:
                    row=isolate(c,p,solver) if args.suite=='ls' else outer_row(c,algorithm,p,solver)
                except (ArithmeticError,ValueError,np.linalg.LinAlgError) as exc:
                    row={'case':c['name'],'track':c['track'],'solver':solver,'algorithm':algorithm,
                         'profile_id':p.name,'screen_pass':False,'exception':str(exc),'status':'exception'}
                row['profile']=label; row['model_elapsed_seconds']=time.perf_counter()-start
                report['rows'].append(row); save()
                print(f"{c['name']} {algorithm or 'LS'} {solver} {label}: {'PASS' if row['screen_pass'] else 'FAIL'} {row.get('status',row.get('fixed_status'))}",flush=True)
    report['source_unchanged_during_run']=all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
    report['complete']=True
    report['summary']={p:{s:{'passed':sum(r['screen_pass'] for r in report['rows'] if r['profile']==p and r['solver']==s),
                              'total':sum(r['profile']==p and r['solver']==s for r in report['rows'])}
                         for s in sorted({r['solver'] for r in report['rows']})} for p in args.profiles}
    save(); print(json.dumps(report['summary']),flush=True)
    if not report['source_unchanged_during_run']: raise RuntimeError('source changed during study; rerun required')
    return 0


if __name__=='__main__':
    raise SystemExit(main())
