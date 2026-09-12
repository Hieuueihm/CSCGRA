"""Focused autonomous LSQR integration gate using Vivado only."""
import datetime
import hashlib
import json
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from verification.v4 import test_lsqr_rtl
from scripts.v4.xsim import tools,tool_versions

def sources():
    paths=set(ROOT.glob('rtl/v4/**/*.sv'))|set(ROOT.glob('rtl/v4/include/*.vh'))|set(ROOT.glob('config/v4_*.json'))
    paths|={ROOT/name for name in ['compiler/v4/solver_program.py','models/v4/lsqr.py','models/v4/recovery.py',
        'models/v4/fixed.py','models/v4/lfsr_operator.py','verification/v4/test_lsqr_rtl.py',
        'verification/v4/solver/tb_lsqr_engine.sv','scripts/v4/run_lsqr_rtl.py','scripts/v4/xsim.py',
        'docs/v4/architecture/LSQR_RTL_CONTRACT.md','rtl/v4/files.f']}
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

def main():
    before=sources();started=datetime.datetime.now(datetime.timezone.utc).isoformat()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(test_lsqr_rtl))
    after=sources();passed=result.testsRun>0 and not result.skipped and bool(test_lsqr_rtl.RUNS) and result.wasSuccessful() and before==after
    evidence=dict(status='PASS' if passed else 'FAIL',started_utc=started,tests=result.testsRun,
        failures=len(result.failures),errors=len(result.errors),skips=len(result.skipped),
        sources_stable_during_run=before==after,source_sha256=before,replays=test_lsqr_rtl.RUNS,
        simulator='Vivado xsim',tools={k:str(v)for k,v in tools().items()},tool_versions=tool_versions(),
        scope='autonomous_resident_LSQR_candidate_not_outer_recovery_or_board_qualification')
    directory=ROOT/'reports/v4';directory.mkdir(parents=True,exist_ok=True)
    (directory/'lsqr_rtl_correctness.json').write_text(json.dumps(evidence,indent=2)+'\n')
    (directory/'LSQR_RTL_CORRECTNESS.md').write_text('\n'.join([
        '# Autonomous resident LSQR RTL correctness','',f'Status: **{evidence["status"]}**. UTC: {started}.','',
        f'{result.testsRun} tests; {len(test_lsqr_rtl.RUNS)} end-to-end cases; {len(result.failures)} failures; {len(result.errors)} errors.',
        f'Stable source hashes: {before==after}. Integer oracle: existing IntegerLSQRKernels, X24F20 stored certificate, relative tolerance1e-5.','',
        'Actual loaded service PC, real Phi/support builder/B/kernel32PE/scalar/candidate writer and atomic commit.',
        'No host numerical stepping after START; exact X, energies and iterations checked; faults/cancel preserve prior commit.',
        'Resident candidate LSQR only; no outer recovery, production numeric freeze, SNR20 application, synthesis or board claim.','',
        '[Commands, source hashes and exact oracle comparisons](lsqr_rtl_correctness.json)','']))
    return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
