"""Summarize completed LFSR numerical contracts without freezing production."""
from __future__ import annotations
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/v4'
TARGET='norm_D18_S27F22_X24_t5'


def load(name):
    d=json.loads((OUT/(name+'.json')).read_text(encoding='utf-8'))
    if not d['complete']: raise ValueError('incomplete '+name)
    return d


def main():
    names=['lfsr_contract_pilot','lfsr_contract_calibration','lfsr_contract_matrix_validation',
           'lfsr_contract_bound_check','lfsr_outer_contract']
    reports={n:load(n) for n in names}
    archives=[]
    for name,d in reports.items():
        sources=d['source_sha256']
        bundle=hashlib.sha256(json.dumps(sources,sort_keys=True).encode()).hexdigest()
        directory=OUT/'source_snapshots'/bundle
        for path,digest in sources.items():
            assert hashlib.sha256((directory/path).read_bytes()).hexdigest()==digest,path
        archives.append({'report':name+'.json','report_sha256':hashlib.sha256((OUT/(name+'.json')).read_bytes()).hexdigest(),
                         'source_bundle':directory.relative_to(ROOT).as_posix(),
                         'bound_review':d.get('derived_bound_review')})
    cal=reports['lfsr_contract_calibration']; val=reports['lfsr_contract_matrix_validation']; outer=reports['lfsr_outer_contract']
    rows=[r for d in [cal,val] for r in d['rows'] if r['configuration']==TARGET and r['track']=='generated_identity_LS']
    q=[r['candidate']['quality_original_units'] for r in rows]
    def outer_pass(r):
        quality=r['quality_full_original_units']
        return bool(quality and quality['arithmetic_quality_pass'] and not r['float_exception']
                    and not r['fixed_exception'] and r['fixed_result']['returned_without_numeric_fault']
                    and r['float_result']['returned_without_numeric_fault'])
    log=(OUT/'lfsr_contract_tests.log').read_text(encoding='utf-8-sig')
    match=re.search(r'Ran (\d+) tests',log)
    assert match and re.search(r'\nOK\s*$',log)
    model_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted((ROOT/'models/v4').glob('*.py'))}
    for path,digest in model_hashes.items(): assert cal['source_sha256'][path]==digest,path
    verification={'complete':True,'unittest_count':int(match.group(1)),
        'test_log_sha256':hashlib.sha256((OUT/'lfsr_contract_tests.log').read_bytes()).hexdigest(),
        'test_source_sha256':{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sorted((ROOT/'verification/v4').glob('test_*.py'))},
        'current_model_sha256':model_hashes,'archived_studies':archives,
        'models_match_tested_source_bundle':True,'RTL_qualification':False}
    (OUT/'lfsr_contract_verification.json').write_text(json.dumps(verification,indent=2)+'\n',encoding='utf-8')
    lines=['# LFSR: normalization, LS stop and solution precision','',
        '**LFSR32 is selected by the user. The numerical shortlist is not a production bit freeze.**','',
        'Current application policy also requires float and fixed reconstruction SNR >=20 dB per case.',
        '[SNR20 reassessment of the existing outer results](LFSR_SNR20_REASSESSMENT.md) is separate from the original relative-quality evidence below.','',
        'Working candidate: D18F14 / C18F16 / S27F22 / X24F20 / ACC64; LSQR normal tolerance 1e-5, budget128.',
        'Normalize the input once by 2^e before D quantization, with peak in (0.25,0.5]; keep the whole job normalized, store X, and undo e only at host output.',
        'S remains 27 bits. Compared with S27F19, F22 exchanges integer headroom for fractional precision; overflow remains a failed job.','',
        '## Completed LS evidence','',
        '| Configuration | Calibration diagnostic pass / 19 | Separate matrix-seed diagnostic pass / 16 |',
        '|---|---:|---:|']
    for cfg,counts in cal['summary'].items():
        v=val['summary'].get(cfg)
        lines.append(f"| {cfg} | {counts['diagnostic_pass']}/19 | {v['diagnostic_pass'] if v else 'not run'}{'/16' if v else ''} |")
    lines += ['',f"The shortlist passes **{sum(r['diagnostic_pass'] for r in rows)}/{len(rows)} generated LFSR LS cases**: 16 calibration and 16 separate matrix-seed cases.",
        f"Worst coefficient relative error against SVD on the same quantized B/y: {max(r['candidate']['coefficient_relative_error'] for r in rows):.9g}.",
        f"Worst SNR loss: {max(x['snr_loss_db'] for x in q):.6f} dB; worst NMSE ratio: {max(x['nmse_ratio'] for x in q):.8f}; maximum LS steps: {max(r['steps'] for r in rows)}.",
        'Cases cover M128/N1024 with support8/32/96, noise30/50dB, low amplitude0.001, plus an M37/N67 tail.',
        'Calibration seeds23/47/101 and validation seeds211/509/997 are separate. This is matrix validation, not patient/scene-held-out evidence.',
        '', '**One generic near-collinear case still fails coefficient agreement despite passing the runtime normal certificate.**',
        'It is retained in all19-case calibration groups. Rank-deficient and general dense stress cases are identified separately; no universal LS coefficient guarantee is claimed.',
        '', '## What changed and why','',
        '- Normalization alone fixes low-amplitude input loss but can expose the D18 solution-storage floor at large support.',
        '- Separate X storage preserves extra coefficient bits through every outer commit; X is not narrowed back to D on return.',
        '- S27F19 with X22/X23 cannot meet tolerance1e-5 in the pilot S96 case. S27F22/X24 reaches the tighter stop without increasing PE operand width.',
        '- S27F22 and S30F22 produce identical raw X outputs and kernel counts on all16 generated calibration cases. The larger S30 control does not improve those numerical results; this does not establish FPGA timing or a global width optimum.',
        '- Loose tolerance1e-4 can pass the normal residual but exceed coefficient error1e-3. Separate matrix seeds211 and997 expose this for the X22/F19 comparison.',
        '- The rounding-only oracle bound is unavailable if rounding clips. Four calibration annotations were corrected with explicit provenance; solver outputs and PASS/FAIL outcomes were not changed.',
        '', '## Outer programs and real windows','',
        f"{sum(outer_pass(r) for r in outer['rows'])}/{len(outer['rows'])} rows pass relative SNR/NMSE and no-fault checks against original-unit float runs.",
        'All11 programs run on three N256 synthetic cases and four real calibration windows; the five LS-using programs also run on N1024.',
        'OMP/GOMP use K iterations, other recovery programs24; proximal programs24 with original lambda0.01. This fixed-budget comparison is not a convergence or absolute-quality guarantee.',
        'FISTA/ADMM/PDHG retain D storage in their current reference. Their lambda is scaled by2^e; they do not claim the new persistent X interface.',
        'Real windows retain the entire original signal through an explicit coefficient-domain encoder DCT; no K-sparsification, raw-signal Phi/Psi hardware, or new application floor is claimed.','',
        '| Case | Relative/no-fault passes | Float full SNR range (dB) | Float centered SNR range (dB) |',
        '|---|---:|---:|---:|']
    for case in outer['cases']:
        cr=[r for r in outer['rows'] if r['case']==case['name']]
        full=[r['quality_full_original_units']['float']['snr_db'] for r in cr if r['quality_full_original_units']]
        centered=[r['quality_centered_original_units']['float']['snr_db'] for r in cr if r['quality_centered_original_units']]
        lines.append(f"| {case['name']} | {sum(outer_pass(r) for r in cr)}/{len(cr)} | {min(full):.2f}–{max(full):.2f} | {min(centered):.2f}–{max(centered):.2f} |")
    failures=[r for r in outer['rows'] if not outer_pass(r)]
    if failures:
        lines += ['', 'Failed outer rows are retained:']
        lines += [f"- {r['case']} / {r['algorithm']}: {r['fixed_status']}" for r in failures]
    lines += ['', '## Verification and artifacts','',
        f"**{verification['unittest_count']} model tests passed**. Tests cover normalization boundaries, finite outputs, scale covariance, explicit X raw representation, overflow rollback and post-storage certification.",
        '[Verification/source hashes](lfsr_contract_verification.json); [calibration](lfsr_contract_calibration.json); [matrix validation](lfsr_contract_matrix_validation.json); [outer evidence](lfsr_outer_contract.json); [pilot failures](lfsr_contract_pilot.json).',
        'Executed sources are archived and verified. The later bound applicability correction is recorded separately without rewriting executed-source identities.',
        '', '[Numeric contract](../../docs/v4/architecture/NUMERIC_CONTRACT.md) and [numeric diagram](../../docs/v4/diagrams/numeric_contract.mmd) define the proposed hardware boundaries.',
        'Remaining gates: meeting the selected SNR20 floor and application-specific secondary metrics on source-level held-out datasets, rank/conditioning policy, staged transforms/adjoints, LFSR cache/feeder/context execution, then RTL correctness before synth/impl.','']
    (OUT/'LFSR_NUMERICAL_CONTRACT.md').write_text('\n'.join(lines),encoding='utf-8')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,ax=plt.subplots(figsize=(10,4.7),layout='constrained')
    combined=cal['rows']+val['rows']
    for cfg,label,color in [('norm_D18_X22_t4','S27F19 / X22F18 / tol 1e-4','#CF7B26'),
                            (TARGET,'S27F22 / X24F20 / tol 1e-5','#1765A3')]:
        selected=[r for r in combined if r['configuration']==cfg and '_s96_' in r['case']]
        errors=[r['candidate']['coefficient_relative_error'] for r in selected]
        ax.semilogy(range(6),errors,'o-',label=label,color=color)
    ax.axhline(1e-3,color='#A33',linestyle='--',label='Coefficient diagnostic 1e-3')
    ax.axvline(2.5,color='#777',linestyle=':',alpha=.7)
    ax.set_xticks(range(6),['23','47','101','211','509','997'])
    ax.set_xlabel('LFSR seed: calibration (left), separate matrix validation (right)')
    ax.set_ylabel('Relative coefficient error vs quantized SVD')
    ax.set_title('LFSR M128 / support96 — numerical calibration, no bit freeze')
    ax.grid(axis='y',alpha=.2); ax.legend(frameon=False,fontsize=9)
    fig.savefig(OUT/'lfsr_ls_precision.png',dpi=170); plt.close(fig)
    print('LFSR summary and source verification written')


if __name__=='__main__': main()
