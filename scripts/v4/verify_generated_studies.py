"""Verify archived evidence, run the v4 suite, and replay LSQR edge-only fixes."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
OUT=ROOT/'reports/v4'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_bundle(report):
    sources=report.get('source_sha256',report.get('source_sha256_at_start'))
    bundle=hashlib.sha256(json.dumps(sources,sort_keys=True).encode()).hexdigest()
    directory=OUT/'source_snapshots'/bundle
    for relative,expected in sources.items():
        assert sha(directory/relative)==expected, relative
    return directory


def main():
    evidence=[]
    names=['generated_ls_sweep','generated_outer_sweep','generated_application_screen',
           'generator_comparison','lsqr_stop_study','input_scale_study','application_float_study']
    for name in names:
        path=OUT/(name+'.json')
        report=json.loads(path.read_text(encoding='utf-8'))
        assert report['complete'], name
        assert report.get('source_unchanged_during_run',True), name
        bundle=source_bundle(report)
        evidence.append({'report':path.relative_to(ROOT).as_posix(),'report_sha256':sha(path),
                         'source_bundle':bundle.relative_to(ROOT).as_posix(),'archive_verified':True})

    run=subprocess.run([sys.executable,'-m','unittest','discover','-s','verification/v4','-v'],
                       cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace')
    log=run.stdout+run.stderr
    (OUT/'generated_verification.log').write_text(log,encoding='utf-8')
    match=re.search(r'Ran (\d+) tests?',log)
    assert run.returncode==0, log[-5000:]
    assert match, 'missing unittest completion count'

    ls_report=json.loads((OUT/'generated_ls_sweep.json').read_text(encoding='utf-8'))
    old_path=source_bundle(ls_report)/'models/v4/lsqr.py'
    spec=importlib.util.spec_from_file_location('archived_v4_lsqr',old_path)
    old=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    from models.v4.lsqr import IntegerLSQRKernels
    from models.v4.recovery import Policy
    from scripts.v4.generated_numeric_study import ls_cases,PROFILES
    replay=[]
    selected={'generated_m128_s8_noise30_amp1_seed23',
              'generated_m128_s32_noise30_amp1_seed23',
              'generated_m128_s8_noise30_amp0.001_seed23'}
    for case in ls_cases([23],'threefry'):
        if case['name'] not in selected: continue
        results=[]
        for cls in [old.IntegerLSQRKernels,IntegerLSQRKernels]:
            solver=cls(case['a'],case['y'],Policy(len(case['support']),ls_max_iterations=128),PROFILES['baseline'])
            try:
                values=[int(v) for v in solver.least_squares(case['support'])]
                status='accepted'
            except ArithmeticError as exc:
                values=None; status=str(exc)
            results.append({'status':status,'accepted_raw':values,'report':solver.last_ls_report,
                            'events':dict(solver.events)})
        assert results[0]==results[1], case['name']
        replay.append({'case':case['name'],'profile':'baseline','status':results[1]['status'],
                       'accepted_output_candidate_history_counts_events_equal':True})
    assert len(replay)==3
    result={'complete':True,'scope':'software tests and edge-fix regression; no RTL qualification',
            'unittest':{'count':int(match.group(1)),'exit_code':run.returncode,
                        'log':'reports/v4/generated_verification.log'},
            'archived_studies':evidence,'lsqr_edge_fix_replay':replay,
            'archived_lsqr_sha256':sha(old_path),
            'current_source_sha256':{p.relative_to(ROOT).as_posix():sha(p)
                for p in sorted((ROOT/'models/v4').glob('*.py'))},
            'verification_script_sha256':sha(Path(__file__)),
            'large_studies_rerun_after_edge_fix':False}
    (OUT/'generated_verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(f"{result['unittest']['count']} tests passed; 7 archived studies verified; 3 exact before/after LSQR replays passed")


if __name__=='__main__': main()
