"""Validate and summarize completed profile calibration reports."""
from __future__ import annotations
from collections import Counter
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    paths = [ROOT/'reports/v4'/f'calibration_{name}.json'
             for name in ('compact','dsp_candidate','wide_control')]
    reports = [json.loads(p.read_text(encoding='utf-8')) for p in paths]
    reference = reports[0]
    combined = []
    for report in reports:
        if not report.get('complete'):
            raise ValueError('incomplete screen')
        for field in ('combined_source_sha256','source_sha256','cases','thresholds'):
            if report[field] != reference[field]:
                raise ValueError(f'incompatible reports: {field}')
        for path, expected in report['source_sha256'].items():
            if hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != expected:
                raise ValueError(f'stale source: {path}')
        expected = {(c['name'],a,p) for c in report['cases']
                    for a in report['configuration']['algorithms'] for p in report['profiles']}
        actual = [(r['case'],r['algorithm'],r['profile']) for r in report['rows']]
        if len(actual) != len(set(actual)) or set(actual) != expected:
            raise ValueError('missing/duplicate/unexpected measurement row')
        combined.extend(report['rows'])
    summary = []
    for report in reports:
        for name in report['profiles']:
            rows = [r for r in combined if r['profile']==name]
            summary.append({'profile':name,'profile_id':rows[0]['profile_id'],
                'passed':sum(r['screen_pass'] for r in rows),'total':len(rows),
                'max_snr_loss_db':max(r['quality']['snr_loss_db'] for r in rows if 'quality' in r),
                'max_nmse_ratio':max(r['quality']['nmse_ratio'] for r in rows if 'quality' in r),
                'failure_status_counts':dict(Counter(r.get('fixed_status','exception')
                    for r in rows if not r['screen_pass']))})
    result = {'scope':'calibration_only_not_release', 'complete':True,
        'combined_source_sha256':reference['combined_source_sha256'],
        'input_reports':[str(p.relative_to(ROOT)).replace('\\','/') for p in paths],
        'summary':summary,'rows':combined, 'selected_production_profile':None,
        'paper_claim_ready':False,'rtl_correctness_proven':False,'synthesis_allowed':False}
    output = ROOT/'reports/v4'
    (output/'calibration_summary.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    lines = ['# V4 initial calibration screen','',
        'All 99 rows use the same verified model source hashes. This is three tiny calibration cases',
        '(synthetic, one camera patch, one ECG segment), not a dataset benchmark or a precision freeze.','',
        '| Profile | Passed / total | Worst SNR loss (dB) | Worst NMSE ratio |',
        '|---|---:|---:|---:|']
    for item in summary:
        lines.append(f"| {item['profile_id']} | {item['passed']}/{item['total']} | {item['max_snr_loss_db']:.6f} | {item['max_nmse_ratio']:.6f} |")
    lines += ['', 'A failed solver returns the last committed state; its poor-quality metrics remain visible.',
        'The compact candidate has LS/certificate failures as well as a quality-only failure and a numeric fault.',
        'D, C and S change together here: this does not isolate a minimum DATA width.',
        'The 1e-4 inner certificate is provisional and must be related to quantization/error bounds before a full sweep.', '',
        '| Source case | Float SNR range (dB) | Centered float SNR range (dB) |',
        '|---|---:|---:|']
    for c in reference['cases']:
        rows = [r for r in combined if r['case']==c['name'] and r['profile']=='dsp_candidate']
        snr = [r['quality']['float']['snr_db'] for r in rows]
        centered = [r['centered_signal_quality']['float']['snr_db'] for r in rows]
        lines.append(f"| {c['name']} | {min(snr):.3f} .. {max(snr):.3f} | {min(centered):.3f} .. {max(centered):.3f} |")
    lines += ['', 'Mean restoration can make full-signal SNR look better; centered quality is reported explicitly.',
        'Absolute application floors, held-out qualification and large-scale/conditioned-matrix sweeps remain open.',
        'No profile is selected, and no v4 RTL/synthesis/implementation result is implied.','',
        'Reproduce: `py -3 scripts/v4/numeric_screen.py --suite applications --profiles <name> --output reports/v4/calibration_<name>.json`',
        'for `compact`, `dsp_candidate`, `wide_control`, then `py -3 scripts/v4/summarize_screen.py`.','',
        f"Model source bundle SHA-256: `{reference['combined_source_sha256']}`.",
        'The superseded exploratory screen is retained only under `work/v4/initial_numeric_screen.json`.']
    (output/'CALIBRATION_SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(summary,indent=2))


if __name__ == '__main__':
    main()
