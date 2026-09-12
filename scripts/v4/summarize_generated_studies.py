"""Produce a concise evidence summary of completed generated-v4 studies."""
from __future__ import annotations
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'reports/v4'


def load(name):
    d=json.loads((OUT/name).read_text(encoding='utf-8'))
    if not d.get('complete',False): raise ValueError('incomplete report: '+name)
    return d


def main():
    ls=load('generated_ls_sweep.json'); outer=load('generated_outer_sweep.json')
    app=load('generated_application_screen.json'); gen=load('generator_comparison.json')
    stop=load('lsqr_stop_study.json'); scale=load('input_scale_study.json')
    float_app=load('application_float_study.json')
    verification=load('generated_verification.json')
    lines=['# Generated v4: numerical calibration evidence','',
        '**No production bit profile, generator winner, application qualification, or RTL sign-off is established.**','',
        'All failures are retained. The main experiments use generated sign A (Psi=I); three additional LS cases explicitly exercise general dense rank/conditioning stress.',
        'The real-window screen measures DCT coefficients at the encoder; it does not implement raw-signal Phi/Psi on the FPGA.','',
        '## Fixed LS, including difficult cases','',
        f"{len(ls['cases'])} cases × {len(ls['profiles'])} profiles × two solvers; normal tolerance 1e-4, budget 128.",
        'The stricter diagnostic also requires float64 normal checking, coefficient agreement within 1e-3 versus quantized SVD, and relative SNR/NMSE quality.',
        'The coefficient threshold is a calibration diagnostic, not a frozen rank-aware release policy.','',
        '| Profile | CGLS certified / diagnostic pass | LSQR certified / diagnostic pass | Cases per solver |',
        '|---|---:|---:|---:|']
    for p in ls['profiles']:
        cells=[]
        for solver in ['cgls','lsqr']:
            rows=[r for r in ls['rows'] if r['profile']==p and r['solver']==solver]
            cells.append(f"{sum(r.get('accepted',False) for r in rows)} / {sum(r['screen_pass'] for r in rows)}")
        lines.append(f"| {p} | {cells[0]} | {cells[1]} | {len(rows)} |")
    lines += ['','[Complete per-case LS report](generated_ls_sweep.json). A certified result can still fail coefficient/quality diagnostics.',
        'Low-amplitude cases, rank/conditioning stress, and storage roundoff must be treated explicitly; a wider profile is not automatically better under the same early-stop rule.','',
        'If storage faults before the observation hook, the top-level failed-candidate diagnostic may describe the preceding observed candidate; the solver report retains the latest raw candidate. Neither is accepted on failure.','',
        '| Profile | D / C / S / ACC |', '|---|---|']
    for name,p in ls['profiles'].items():
        formats=' / '.join(f"{k[0].upper()}{p[k]['width']}F{p[k]['frac']}" for k in ['data','coefficient','state'])
        lines.append(f"| {name} | {formats} / A{p['accumulator_width']} |")
    lines += ['', '### What the LS failures mean','',
        '- At M128/S32, seed47, baseline LSQR exhausts 128 steps after D storage; changing only D18F14 to D20F16 accepts in 11 steps. This identifies one storage-sensitive case, not a universal D20 guarantee.',
        '- At M128/S96, seed23, wide-control LSQR stops with coefficient relative error 0.001547 at normal tolerance 1e-4. Tightening to 3e-5 gives 0.0004783 and to 1e-5 gives 0.00008478. Tighter policies also cause failures in narrower profiles, so no universal default is selected.',
        '- The generic near-collinear case passes the normal certificate while coefficient relative error remains about 0.997. Normal residual alone cannot qualify coefficients used by support pruning.',
        '- Three low-amplitude baseline cases all fail without input scaling and all accept after explicit power-of-two normalization before quantization. The exponent must accompany the job and be undone at output. This does not recover samples already lost to ADC quantization.',
        '', '### Scalar cost is material','',
        'For the baseline M128/S8 seed23 case, both solvers take six steps and 26 GEMVs including certificates. CGLS uses 19 DOTs and 11 DIVs; LSQR uses 21 DOTs, 38 DIVs and 20 SQRTs.',
        'These are numerical kernel counts, not clock cycles. A single scalar service can become the bottleneck; LSQR has not demonstrated a total-job throughput advantage.',
        '',
        '## Outer algorithms at fixed budgets','',
        f"{sum(r['screen_pass'] for r in outer['rows'])}/{len(outer['rows'])} rows pass the relative-quality/no-fault screen.",
        'This is not a convergence or absolute-reconstruction-quality claim; iteration-budget terminations remain in the report.',
        '[Full outer report](generated_outer_sweep.json).','',
        '## Real-window coefficient-domain screen','',
        f"{sum(r['screen_pass'] for r in app['rows'])}/{len(app['rows'])} relative-quality/no-fault passes on two ECG windows and two camera patches.",
        'The original windows are not sparsified before measurement. They are calibration windows, not patient/scene-held-out data.',
        'Float reconstruction quality remains a separate issue from fixed-versus-float agreement.','',
        '| Window | Float SNR range across algorithms (dB) | Largest SNR loss (dB) | Largest NMSE ratio |',
        '|---|---:|---:|---:|']
    for case in app['cases']:
        rows=[r for r in app['rows'] if r['case']==case['name'] and 'quality' in r]
        snr=[r['quality']['float']['snr_db'] for r in rows]
        lines.append(f"| {case['name']} | {min(snr):.2f}–{max(snr):.2f} | {max(r['quality']['snr_loss_db'] for r in rows):.5f} | {max(r['quality']['nmse_ratio'] for r in rows):.6f} |")
    lines += ['','[Per-case application screen](generated_application_screen.json).',
        'Any mean/DC restoration is also accompanied by centered-signal metrics in the JSON. No application floor is frozen by this screen.','',
        '## Threefry versus LFSR','',
        'The comparison uses matched supports/truth/noise directions and recomputes measurements with each matrix.',
        'The 20 dB threshold below is an explicit synthetic diagnostic. Counts combine eight algorithms at fixed budgets, not independent statistical trials.','',
        '| Generator | Coherence over three seeds | K8 rows at least 20 dB | K32 rows at least 20 dB |',
        '|---|---:|---:|---:|']
    for family in ['threefry','lfsr32']:
        mu=[r['mutual_coherence'] for r in gen['matrix_quality'] if r['generator']==family]
        summary=gen['summary'][family]
        lines.append(f"| {family} | {min(mu):.6f}–{max(mu):.6f} | {summary['8']['snr20_pass']}/{summary['8']['rows']} | {summary['32']['snr20_pass']}/{summary['32']['rows']} |")
    lines += ['','[Generator comparison](generator_comparison.json). These data do not establish a hardware-cost winner or a RIP bound.',
        'At M128/N1024, the K32 cases already expose a float recovery-quality limitation; changing bit width alone cannot fix it.','',
        '## Follow-up diagnostics','',
        '- [LSQR stop-policy study](lsqr_stop_study.json): separate stronger convergence requirements from storage precision.',
        '- [Input-scale study](input_scale_study.json): explicit power-of-two normalization before quantization; requires exponent metadata.',
        '- [Float application-policy calibration](application_float_study.json): separate inadequate float policies from quantization loss.','',
        f"Follow-up report sizes: {len(stop['rows'])} paired stop configurations, {len(scale['rows'])} scale rows, and {len(float_app['rows'])} float application-policy rows.",
        'Policy candidates are selected on these calibration windows only. Full-signal and centered metrics are both recorded; a high camera SNR with a large restored DC component does not guarantee recovery of image variation.','',
        '## Provenance and final verification','',
        'Every executed numerical source bundle is archived under [source_snapshots](source_snapshots). Report source hashes identify the version actually executed; they are not silently replaced by current working-tree hashes.',
        'The final LSQR edge fix rejects constructor faults even for empty support and detaches completed operation reports. The large studies use the preceding archived version; a separate nonempty replay compares exact candidates, certificate histories and counts before/after that fix.',
        f"Final verification: **{verification['unittest']['count']} tests pass**, archived sources for seven reports are checked, and three exact nonempty LSQR before/after replays pass (including budget failure). See [verification result](generated_verification.json).",'',
        'Next freeze requires justified application floors and held-out profiles, final scalar/normalization/storage contracts, operator/adjoint/context execution verification, and then RTL correctness.',
        'Synthesis and implementation remain gated. Python elapsed time and operation counts are not FPGA throughput.','']
    (OUT/'GENERATED_NUMERICAL_SUMMARY.md').write_text('\n'.join(lines),encoding='utf-8')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    fig,axes=plt.subplots(1,2,figsize=(12.8,4.8),layout='constrained')
    names=list(ls['profiles']); locations=np.arange(len(names))
    for solver,offset,color in [('cgls',-.19,'#78909C'),('lsqr',.19,'#1565C0')]:
        counts=[sum(r['screen_pass'] for r in ls['rows'] if r['solver']==solver and r['profile']==p) for p in names]
        axes[0].bar(locations+offset,counts,width=.36,label=solver.upper(),color=color)
    axes[0].set_xticks(locations,names,rotation=35,ha='right')
    axes[0].set_ylim(0,len(ls['cases'])+1)
    axes[0].set_ylabel(f"Diagnostic passes / {len(ls['cases'])} cases")
    axes[0].set_title('LS: includes low-amplitude and rank stress')
    axes[0].legend(frameon=False)
    for i,family in enumerate(['threefry','lfsr32']):
        mu=[r['mutual_coherence'] for r in gen['matrix_quality'] if r['generator']==family]
        axes[1].scatter(np.full(len(mu),i)+np.linspace(-.06,.06,len(mu)),mu,s=65,
                        color=['#1565C0','#E67E22'][i],zorder=3)
        for x,v,seed in zip(np.full(len(mu),i)+np.linspace(-.06,.06,len(mu)),mu,gen['seeds']):
            axes[1].annotate(str(seed),(x,v),xytext=(4,5),textcoords='offset points',fontsize=8)
    axes[1].set_xticks([0,1],['Threefry2x32-20','LFSR32'])
    axes[1].set_ylabel('Mutual coherence')
    axes[1].set_title('M128 / N1024: three matrix seeds, no RIP claim')
    axes[1].set_xlim(-.4,1.4)
    axes[1].grid(axis='y',alpha=.2)
    fig.suptitle('Generated v4 calibration — no bit-width or FPGA sign-off',fontsize=13)
    fig.savefig(OUT/'generated_calibration.png',dpi=160)
    plt.close(fig)
    print('Wrote reports/v4/GENERATED_NUMERICAL_SUMMARY.md')


if __name__=='__main__': main()
