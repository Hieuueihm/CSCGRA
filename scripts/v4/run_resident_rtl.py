"""Focused Vivado xsim resident integration evidence with stable source hashes."""
import datetime
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from verification.v4 import test_resident_rtl
from scripts.v4.xsim import compile_rtl, filelist_sources, tools, tool_versions

def sources():
    files=set(ROOT.glob('rtl/v4/**/*.sv'))|set(ROOT.glob('rtl/v4/include/*.vh'))
    files |= {ROOT/name for name in ('config/v4_operator_exec.json','compiler/v4/resident_program.py',
        'compiler/v4/context_image.py','scripts/v4/export_control_stream.py','scripts/v4/generate_operator_defs.py',
        'verification/v4/test_resident_rtl.py','verification/v4/control/tb_resident_engine.sv',
        'docs/v4/architecture/RESIDENT_RTL_CONTRACT.md','scripts/v4/run_resident_rtl.py','scripts/v4/xsim.py','rtl/v4/files.f')}
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}

def main():
    before=sources(); started=datetime.datetime.now(datetime.timezone.utc).isoformat()
    checks=[]
    with tempfile.TemporaryDirectory(prefix='resident_elab_',dir=ROOT/'work') as temporary:
        for top in ('phi_reader','frame_fabric','operator_controller','resident_operands','resident_engine'):
            run=compile_rtl(Path(temporary)/(top+'.xsim.json'),top,filelist_sources(ROOT),root=ROOT,timeout=300)
            checks.append(dict(top=top,commands=run.commands,returncode=run.returncode,stdout=run.stdout,stderr=run.stderr))
    suite=unittest.defaultTestLoader.loadTestsFromModule(test_resident_rtl)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    after=sources()
    passed=result.wasSuccessful() and before==after and all(row['returncode']==0 for row in checks)
    evidence=dict(status='PASS' if passed else 'FAIL',started_utc=started,tests=result.testsRun,
        failures=len(result.failures),errors=len(result.errors),skips=len(result.skipped),checks=checks,
        sources_stable_during_run=before==after,source_sha256=before,replays=test_resident_rtl.RUNS,
        scope='candidate_result_stream_not_job_commit_scalar_service_or_LSQR',
        simulator='Vivado xsim',tools={name:str(path) for name,path in tools().items()},tool_versions=tool_versions())
    directory=ROOT/'reports/v4'; directory.mkdir(parents=True,exist_ok=True)
    (directory/'resident_rtl_correctness.json').write_text(json.dumps(evidence,indent=2)+'\n')
    (directory/'RESIDENT_RTL_CORRECTNESS.md').write_text('\n'.join([
        '# Resident execution RTL correctness','',f'Status: **{evidence["status"]}**. UTC: {started}.','',
        f'{result.testsRun} tests; {len(result.failures)} failures; {len(result.errors)} errors; {len(test_resident_rtl.RUNS)} live integration cases.',
        f'{len(checks)} Vivado compile/elaboration tops; stable source hashes: {before==after}.','',
        'Actual verified image load, live Phi/B/vector, ADDRESS/PC-controlled GEMV, 32 PEs and candidate retirement.',
        'Two starts per case preserve preloaded memories. R4 full-width PE routes reduce before final rounding.',
        'Candidate output stream only; no vector writeback/commit, support builder, scalar service or LSQR.',
        'No synthesis, implementation, BRAM/timing claim or tile/control ABI freeze.','',
        '[Commands, source hashes, images and accepted-result evidence](resident_rtl_correctness.json)','']))
    return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
