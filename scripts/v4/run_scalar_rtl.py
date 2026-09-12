"""Run the standalone scalar RTL correctness gate; never synthesize/implement."""
from datetime import datetime,timezone
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from scripts.v4.xsim import tool_versions

def sources():
    paths=[ROOT/p for p in (
        'config/v4_scalar_interface.json','config/v4_pe_interface.json','config/v4_phi_interface.json',
        'rtl/v4/include/scalar_interface.vh','rtl/v4/services/scalar_service.sv',
        'scripts/v4/generate_scalar_interface.py','scripts/v4/run_scalar_rtl.py','scripts/v4/xsim.py',
        'verification/v4/test_scalar_rtl.py','verification/v4/scalar/tb_scalar_service.sv',
        'verification/v4/scalar/README.md','docs/v4/architecture/SCALAR_RTL_CONTRACT.md',
        'docs/v4/architecture/NUMERIC_CONTRACT.md')]
    paths.extend((ROOT/'models/v4').glob('*.py'))
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

def run(command,env=None):
    p=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,timeout=120)
    return dict(command=command,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)

def main():
    from verification.v4 import test_scalar_rtl
    test_scalar_rtl.RUNS.clear()
    started=datetime.now(timezone.utc).isoformat(); before=sources()
    versions=tool_versions()+[run([sys.executable,'--version'])]
    checks=[run([sys.executable,'scripts/v4/generate_scalar_interface.py','--check'])]
    output=io.StringIO()
    result=unittest.TextTestRunner(stream=output,verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromModule(test_scalar_rtl))
    stable=before==sources()
    passed=result.wasSuccessful() and not result.skipped and stable and all(x['returncode']==0 for x in checks+versions)
    evidence=dict(status='PASS' if passed else 'FAIL',scope='standalone_scalar_arithmetic_leaf',simulator='Vivado xvlog/xelab/xsim',
                  started_utc=started,tests=result.testsRun,failures=len(result.failures),
                  errors=len(result.errors),skips=len(result.skipped),sources_stable_during_run=stable,
                  source_sha256=before,versions=versions,checks=checks,
                  replays=test_scalar_rtl.RUNS,unittest_output=output.getvalue(),
                  not_qualified=['scalar_RF','control_context_integration','LSQR_RTL','synthesis','implementation','PPA'])
    folder=ROOT/'reports/v4';folder.mkdir(parents=True,exist_ok=True)
    (folder/'scalar_rtl_correctness.json').write_text(json.dumps(evidence,indent=2)+'\n')
    replays=evidence['replays']
    lines=['# Standalone scalar RTL correctness','',f"Status: **{evidence['status']}**. UTC: {started}.",'',
           f"{result.testsRun} tests, {len(result.failures)} failures, {len(result.errors)} errors, {len(result.skipped)} skips.",
           f"{len(checks)} generated-definition checks; Vivado xvlog/xelab/xsim replay; source stability: {stable}.",
           f"{sum(r['cycles'] for r in replays)} replay cycles; {sum(r['comparisons'] for r in replays)} before/after-edge signal comparisons.",'',
           '| Replay | Cycles | Accepted | Retired | Flushed |','|---|---:|---:|---:|---:|']
    for row in replays:
        lines.append(f"| {row['test'].rsplit('.',1)[-1]} | {row['cycles']} | {row['accepted']} | {row['retired']} | {row['flushed']} |")
    lines.extend(['','DIV compares signed64 ratios with independent arbitrary-integer nearest rounding. SQRT compares ACC64 energies with integer isqrt and midpoint rounding. Both return S27F22 or an inert fault.',
                  'Tests include signed minima, half ties, representable limits and overflow, unsupported metadata, all iterative reset/cancel positions, output stalls, and actual scalar calls captured from two successful numerical LSQR solves.',
                  '','This evidence qualifies the standalone arithmetic leaf only. Scalar RF, control/context integration and LSQR RTL remain absent. No synthesis, implementation, resource or timing claim. Numeric format remains a candidate.',
                  '','Reproduce: `py -3 scripts/v4/run_scalar_rtl.py`.',
                  '[Commands, versions, vectors/trace hashes, captured LSQR calls and source hashes](scalar_rtl_correctness.json).',''])
    (folder/'SCALAR_RTL_CORRECTNESS.md').write_text('\n'.join(lines))
    print(output.getvalue());print(folder/'scalar_rtl_correctness.json')
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
