"""Run only the four revision-one streaming test modules, serially in-process."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib
import io
import json
from pathlib import Path
import sys
import traceback
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.v4.xsim import tool_versions

MODULES = tuple('verification.v4.test_stream_' + name + '_rtl'
                for name in ('memory', 'compute', 'program', 'engine'))


def sources():
    paths = {
        'config/v4_stream_interface.json', 'config/v4_pe_interface.json',
        'config/v4_kernel_interface.json', 'config/v4_program_interface.json', 'scripts/v4/generate_kernel_interface.py', 'scripts/v4/generate_program_interface.py',
        'config/v4_modules.json', 'config/v4_design.json', 'rtl/v4/files.f',
        'rtl/v4/include/stream_interface.vh', 'rtl/v4/include/pe_interface.vh', 'rtl/v4/include/kernel_interface.vh', 'rtl/v4/include/program_interface.vh',
        'scripts/v4/generate_stream_interface.py', 'scripts/v4/xsim.py',
        'scripts/v4/run_stream_rtl.py', 'compiler/v4/stream_program.py',
        'docs/v4/architecture/STREAM_RTL_CONTRACT.md',
        'docs/v4/architecture/STREAM_SYSTEM_CONTRACT.md',
        'docs/v4/architecture/FACTOR_SERVICE.md', 'docs/v4/architecture/FACTOR_PANEL.md',
        'docs/v4/architecture/NUMERIC_CONTRACT.md',
        'rtl/v4/memory/stream_vector_store.sv',
        'rtl/v4/control/stream_program_control.sv', 'rtl/v4/control/stream_engine.sv',
        'rtl/v4/compute/stream_kernel.sv', 'rtl/v4/dataflow/operator_frame_feeder.sv',
        'rtl/v4/dataflow/support_service.sv','rtl/v4/dataflow/factor_service.sv','rtl/v4/dataflow/factor_panel_service.sv','rtl/v4/memory/factor_store.sv',
        'verification/v4/memory/tb_stream_vector_store.sv',
    }
    paths.update('rtl/v4/compute/stream_' + name + '.sv' for name in ('pe', 'array', 'fabric'))
    # The wrapper imports Arithmetic only; QR/recovery models are not executed here.
    paths.add('models/v4/fixed.py')
    for package in ('models/__init__.py', 'models/v4/__init__.py', 'compiler/__init__.py', 'compiler/v4/__init__.py'):
        if (ROOT / package).is_file():
            paths.add(package)
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'rtl/v4/include').glob('*.vh'))
    paths.update('reports/v4/stream_program_example/' + name
                 for name in ('input.json', 'package.json', 'program.hex', 'templates.hex'))
    paths.update(name.replace('.', '/') + '.py' for name in MODULES)
    paths.update('verification/v4/stream/' + name for name in (
        'arithmetic_oracle.py', 'tb_stream.sv', 'tb_stream_program_control.sv',
        'tb_stream_engine.sv'))
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            for name in sorted(paths)}


def cases(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from cases(test)
        else:
            yield test.id()


def commands(value):
    """Return actual command leaves once; provenance and reuse are not executions."""
    found = {}
    def visit(item):
        if isinstance(item, dict):
            if isinstance(item.get('argv'), list):
                if item.get('execution') == 'executed' and item.get('invocation_id'):
                    found.setdefault(item['invocation_id'], item)
                return
            for key, child in item.items():
                if key not in ('source_identity', 'compile_identity', 'identity', 'hashes'):
                    visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)
    visit(value)
    return list(found.values())


class RecordedResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.executed = []

    def startTest(self, test):
        self.executed.append(test.id())
        super().startTest(test)


class TestLog(io.StringIO):
    def writeln(self, text=''):
        self.write(text + '\n')


def write_report(folder, evidence):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'stream_rtl_correctness.json').write_text(
        json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    lines = ['# Streaming RTL correctness', '', f"Status: **{evidence['status']}**.", '',
             'Scope: revision-one loaded CALL/HALT programs, explicit vector RAM, and exactly 32 streaming PEs.',
             f"Tests executed: {evidence['tests']}; failures: {evidence['failures']}; errors: {evidence['errors']}; skips: {evidence['skips']}.",
             f"Exact discovered/executed coverage: {evidence.get('coverage_exact', False)}; source stability: {evidence.get('sources_stable_during_run', False)}.",
             '', '| Family | Replays | Cycles | Checks/comparisons |', '|---|---:|---:|---:|']
    for name, rows in evidence.get('replays', {}).items():
        lines.append(f"| {name} | {len(rows)} | {sum(r.get('cycles', 0) for r in rows)} | "
                     f"{sum(r.get('comparisons', r.get('checks', 0)) for r in rows)} |")
    lines += ['', 'Counts combine different numerical and protocol checks; they are not all signal comparisons.',
              'This separate gate does not qualify full algorithms, Phi/B integration, synthesis, implementation, timing or resources.',
              'Interrupted or incomplete runs cannot pass. Executed command records, source identities, test IDs and tool versions are in the JSON.',
              '', '[Machine-readable evidence](stream_rtl_correctness.json).', '']
    (folder / 'STREAM_RTL_CORRECTNESS.md').write_text('\n'.join(lines), encoding='utf-8')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'reports/v4')
    args = parser.parse_args(argv)
    evidence = dict(status='RUNNING', started_utc=datetime.now(timezone.utc).isoformat(),
                    simulator='Vivado xvlog/xelab/xsim', modules=list(MODULES), tests=0,
                    failures=0, errors=0, skips=0, replays={}, runner_errors=[])
    write_report(args.output_dir, evidence)
    loaded = []
    output = TestLog()
    result = RecordedResult(output, True, 2)
    interrupted = False
    try:
        evidence['source_sha256'] = sources()
        evidence['versions'] = tool_versions()
        evidence['python'] = dict(executable=sys.executable, version=sys.version)
        suite = unittest.TestSuite()
        for name in MODULES:
            module = importlib.import_module(name)
            module.RUNS.clear()
            loaded.append(module)
            suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
        evidence['scheduled_test_ids'] = list(cases(suite))
        # Run the combined suite once; no subprocess discovery, filtering or retry.
        suite.run(result)
    except KeyboardInterrupt:
        interrupted = True
        evidence['runner_errors'].append('KeyboardInterrupt: incomplete execution')
    except BaseException:
        evidence['runner_errors'].append(traceback.format_exc())
    finally:
        evidence.update(tests=result.testsRun, failures=len(result.failures), errors=len(result.errors),
                        skips=len(result.skipped), executed_test_ids=result.executed,
                        expected_failures=len(result.expectedFailures),
                        unexpected_successes=len(result.unexpectedSuccesses),
                        unittest_output=output.getvalue(),
                        failure_details=result.failures, error_details=result.errors,
                        skipped_tests=[(t.id(), why) for t, why in result.skipped])
        # unittest stores TestCase objects alongside tracebacks; serialize IDs.
        for key in ('failure_details', 'error_details'):
            evidence[key] = [(t.id(), detail) for t, detail in evidence[key]]
        evidence['replays'] = {module.__name__: module.RUNS for module in loaded}
        try:
            evidence['source_sha256_after'] = sources()
            evidence['sources_stable_during_run'] = evidence.get('source_sha256') == evidence['source_sha256_after']
        except BaseException:
            evidence['sources_stable_during_run'] = False
            evidence['runner_errors'].append(traceback.format_exc())
        planned = evidence.get('scheduled_test_ids', [])
        evidence['coverage_exact'] = bool(planned) and Counter(planned) == Counter(result.executed) and len(set(planned)) == len(planned)
        actual = commands(evidence['replays'])
        evidence['actual_commands'] = actual
        evidence['stages_by_module'] = {
            name: dict(Counter(Path(c['argv'][0]).stem.lower() for c in commands(rows)))
            for name, rows in evidence['replays'].items()}
        stages_ok = all(all(evidence['stages_by_module'].get(name, {}).get(stage, 0) > 0
                            for stage in ('xvlog', 'xelab', 'xsim')) for name in MODULES)
        tools_ok = bool(actual) and all(c.get('returncode') == 0 and Path(c['argv'][0]).stem.lower() in ('xvlog', 'xelab', 'xsim') for c in actual) and bool(evidence.get('versions')) and all(c.get('returncode') == 0 for c in evidence.get('versions', []))
        evidence['tool_failures'] = sum(c.get('returncode') != 0 for c in actual + evidence.get('versions', []))
        replay_ok = all(rows and all(row.get('status') == 'PASS' for row in rows)
                        for rows in evidence['replays'].values())
        passed = result.wasSuccessful() and not result.skipped and not result.expectedFailures and not evidence['runner_errors'] and evidence['coverage_exact'] and evidence['sources_stable_during_run'] and stages_ok and tools_ok and replay_ok
        evidence['status'] = 'INTERRUPTED' if interrupted else 'PASS' if passed else 'FAIL'
        evidence['finished_utc'] = datetime.now(timezone.utc).isoformat()
        write_report(args.output_dir, evidence)
    print(output.getvalue())
    print(args.output_dir / 'stream_rtl_correctness.json')
    return 0 if evidence['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
