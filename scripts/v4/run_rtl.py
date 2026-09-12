"""Run all implemented V4 RTL correctness gates once, with source-stable evidence."""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.v4.run_phi_rtl import sources
from scripts.v4.xsim import execute_process, tool_versions

BOUNDARY = (
    "Implemented primitives, resident GEMV reference, generic kernels/scalar RF and bounded LSQR "
    "with stored-X certification and transactional result publication. "
    "No full eleven-algorithm end-to-end recovery or board qualification. Numeric/context formats remain candidates. "
    "No synthesis, implementation, resource, timing or PPA claim. "
    "Individual image execution scope is retained in compiler_images; an image appearing there "
    "does not imply full program execution."
)


def run(command, env=None, timeout=120):
    """Keep failures and timeouts in evidence rather than losing the report."""
    try:
        if env is not None:
            raise ValueError('unified runner does not override subprocess environments')
        result = execute_process(command, cwd=ROOT, timeout=timeout)
        return dict(command=command, returncode=result.returncode,
                    stdout=result.stdout, stderr=result.stderr, timeout_seconds=timeout)
    except subprocess.TimeoutExpired as error:
        decode = lambda value: value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        return dict(command=command, returncode=124, stdout=decode(error.stdout),
                    stderr=decode(error.stderr), timeout_seconds=timeout, error='subprocess_timeout')
    except OSError as error:
        return dict(command=command, returncode=127, stdout='', stderr=str(error),
                    timeout_seconds=timeout, error=type(error).__name__)


def implemented_modules(root=ROOT):
    """Parse this file-list grammar explicitly; reject unknown directives."""
    paths, visited = [], set()
    def read_list(path):
        path = path.resolve()
        if path in visited:
            return
        visited.add(path)
        text = re.sub(r'/\*.*?\*/', '', path.read_text(encoding='utf-8'), flags=re.S)
        tokens = shlex.split(re.sub(r'//[^\n]*|#[^\n]*', '', text), posix=True)
        index = 0
        while index < len(tokens):
            token = tokens[index]
            if token == '-f':
                index += 1
                if index == len(tokens):
                    raise ValueError(f'missing nested file list after -f in {path}')
                read_list(root / tokens[index])
            elif token.startswith(('+incdir+', '+define+')):
                pass
            elif token.endswith(('.sv', '.v')) and not token.startswith(('-', '+')):
                source = (root / token).resolve()
                if not source.is_file():
                    raise ValueError(f'missing RTL source {source}')
                if source not in paths:
                    paths.append(source)
            else:
                raise ValueError(f'unsupported files.f token {token!r}; review discovery grammar')
            index += 1
    read_list(root / 'rtl/v4/files.f')
    modules = {}
    for path in paths:
        # Strip comments and strings so a diagnostic mentioning "module" is not a declaration.
        text = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"', '',
                      path.read_text(encoding='utf-8'), flags=re.S)
        for name in re.findall(r'\bmodule\s+(?:(?:automatic|static)\s+)?([A-Za-z_][A-Za-z0-9_$]*)\b', text):
            if name in modules:
                raise ValueError(f'duplicate module declaration {name}')
            modules[name] = path.relative_to(root).as_posix()
    if not modules:
        raise ValueError('no implemented modules discovered from rtl/v4/files.f')
    return modules


def collect_test_metadata(modules=None):
    """Merge import aliases by physical file; never sum the same replay list twice."""
    grouped = {}
    for module in tuple(sys.modules.values()) if modules is None else modules:
        filename = getattr(module, '__file__', None)
        if not filename:
            continue
        path = Path(filename).resolve()
        if path.is_relative_to(ROOT / 'verification/v4') and re.fullmatch(r'test_.*_rtl\.py', path.name):
            grouped.setdefault(path.relative_to(ROOT).as_posix(), []).append(module)
    replays, images, commands, compile_output = {}, {}, {}, {}
    seen_lists = set()
    for filename, aliases in sorted(grouped.items()):
        for attr in ('RUNS', 'FABRIC_RUNS', 'PRIMITIVE_RUNS', 'IMAGES', 'COMMANDS'):
            rows, seen_rows = [], set()
            for module in aliases:
                value = getattr(module, attr, None)
                if not value or id(value) in seen_lists:
                    continue
                if not isinstance(value, list) and not (attr == 'IMAGES' and isinstance(value, dict)):
                    raise TypeError(f'{filename}:{attr} must be a replay list or image metadata')
                seen_lists.add(id(value))
                for row in ([value] if isinstance(value, dict) else value):
                    key = json.dumps(row, sort_keys=True)
                    if key not in seen_rows:
                        seen_rows.add(key)
                        rows.append(row)
            if rows:
                destination = images if attr == 'IMAGES' else commands if attr == 'COMMANDS' else replays
                destination[filename + ':' + attr] = rows
        logs = []
        for module in aliases:
            for value in vars(module).values():
                if isinstance(value, type) and hasattr(value, 'compile_output'):
                    log = getattr(value, 'compile_output')
                    if log not in logs:
                        logs.append(log)
        if logs:
            compile_output[filename] = logs
    return dict(replays=replays, compiler_images=images, rtl_commands=commands,
                rtl_compile_output=compile_output)


def test_cases(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from test_cases(item)
        else:
            yield item


def discover_test_ids():
    """The unchanged original discovery is the authority for test coverage."""
    loader = unittest.TestLoader()
    suite = loader.discover(str(ROOT / 'verification/v4'), pattern='test_*.py')
    if loader.errors:
        raise ValueError('authoritative unittest discovery failed: ' + '\n'.join(loader.errors))
    modules = {}
    for case in test_cases(suite):
        modules.setdefault(case.__class__.__module__, []).append(case.id())
    identifiers = [name for names in modules.values() for name in names]
    if not identifiers or len(set(identifiers)) != len(identifiers):
        raise ValueError('authoritative discovery is empty or contains duplicate test IDs')
    return modules


def partition_modules(modules, workers):
    """Keep module fixtures together, with the three expensive families separated."""
    if not 1 <= workers <= 3:
        raise ValueError('test worker count must be 1..3')
    if not modules:
        raise ValueError('cannot partition empty discovery')
    groups = [[] for _ in range(min(workers, len(modules)))]
    loads = [0] * len(groups)
    anchors = ('test_context_rtl', 'test_tile_rtl', 'test_pe_rtl')
    extra = {'test_control_rtl': 180, 'test_resident_rtl': 140,
             'test_resident_operands_rtl': 140, 'test_fabric_rtl': 100,
             'test_ram_reader_rtl': 70, 'test_memory_rtl': 60}
    def weight(module):
        leaf = module.rsplit('.', 1)[-1]
        return (1000 if leaf in anchors else extra.get(leaf, 0)) + len(modules[module])
    for module in sorted(modules, key=lambda name: (-weight(name), name)):
        group = min(range(len(groups)), key=lambda index: loads[index])
        groups[group].append(module)
        loads[group] += weight(module)
    order = {name: index for index, name in enumerate(modules)}
    return [dict(worker=index, modules=sorted(names, key=order.get),
                 test_ids=[test for name in sorted(names, key=order.get) for test in modules[name]])
            for index, names in enumerate(groups)]


class CoverageResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.actual_test_ids = []

    def startTest(self, test):
        self.actual_test_ids.append(test.id())
        super().startTest(test)


def test_worker(plan_path, output_path):
    plan = json.loads(Path(plan_path).read_text(encoding='utf-8'))
    # Match discover(start_dir) module names exactly, without rerunning discovery.
    sys.path.insert(0, str(ROOT / 'verification/v4'))
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromNames(plan['modules'])
    selected = [case.id() for case in test_cases(suite)]
    stream = io.StringIO()
    if loader.errors or Counter(selected) != Counter(plan['test_ids']) or len(set(selected)) != len(selected):
        evidence = dict(tests=0, failures=0, errors=1, skips=0, successful=False,
                        actual_test_ids=[], test_output='worker module loading differs from assigned coverage',
                        loader_errors=loader.errors, loaded_test_ids=selected)
    else:
        result = unittest.TextTestRunner(stream=stream, verbosity=2, resultclass=CoverageResult).run(suite)
        evidence = dict(tests=result.testsRun, failures=len(result.failures), errors=len(result.errors),
                        skips=len(result.skipped), successful=result.wasSuccessful(),
                        actual_test_ids=result.actual_test_ids, test_output=stream.getvalue())
    evidence.update(worker=plan['worker'], assigned_test_ids=plan['test_ids'], **collect_test_metadata())
    Path(output_path).write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print(evidence['test_output'], flush=True)
    exact = Counter(evidence['actual_test_ids']) == Counter(plan['test_ids'])
    return 0 if evidence['successful'] and exact and not evidence['skips'] and evidence['tests'] else 1


def aggregate_workers(authoritative_ids, plans, outcomes):
    """Reject missing, added, repeated or unexecuted tests, independently of exit code."""
    result = dict(tests=0, failures=0, errors=0, skips=0, successful=False,
                  replays={}, compiler_images={}, rtl_commands={}, rtl_compile_output={},
                  test_output='', actual_test_ids=[], worker_results=outcomes, coverage_errors=[])
    errors = result['coverage_errors']
    if len(set(authoritative_ids)) != len(authoritative_ids) or not authoritative_ids:
        errors.append('authoritative test IDs are empty or duplicated')
    assigned = [name for plan in plans for name in plan['test_ids']]
    if Counter(assigned) != Counter(authoritative_ids):
        errors.append('worker assignments differ from authoritative test-ID multiset')
    if Counter(row.get('worker') for row in outcomes) != Counter(plan['worker'] for plan in plans):
        errors.append('missing, additional or duplicate worker outcomes')
    by_worker = {plan['worker']: plan for plan in plans}
    for outcome in outcomes:
        worker = outcome.get('worker')
        data = outcome.get('result')
        if outcome.get('command', {}).get('returncode') != 0:
            errors.append(f'worker {worker} command failed or timed out')
        required = {'tests', 'failures', 'errors', 'skips', 'successful', 'actual_test_ids',
                    'assigned_test_ids', 'worker', 'test_output', 'replays', 'compiler_images',
                    'rtl_commands', 'rtl_compile_output'}
        if not isinstance(data, dict) or not required <= data.keys():
            errors.append(f'worker {worker} metadata missing or incomplete')
            continue
        actual = data['actual_test_ids']
        plan = by_worker.get(worker, {})
        if (data['worker'] != worker or Counter(data['assigned_test_ids']) != Counter(plan.get('test_ids', []))
                or Counter(actual) != Counter(plan.get('test_ids', []))
                or len(actual) != data['tests'] or len(actual) != len(set(actual))):
            errors.append(f'worker {worker} actual/assigned coverage mismatch or duplicate test IDs')
        if not data['successful'] or data['failures'] or data['errors'] or data['skips']:
            errors.append(f'worker {worker} has unsuccessful, failed, erroneous or skipped tests')
        for key in ('tests', 'failures', 'errors', 'skips'):
            result[key] += data[key]
        result['actual_test_ids'].extend(actual)
        result['test_output'] += f'Worker {worker}:\n' + data['test_output'] + '\n'
        for field in ('replays', 'compiler_images', 'rtl_commands', 'rtl_compile_output'):
            for name, rows in data[field].items():
                result[field].setdefault(name, []).extend(rows)
    if Counter(result['actual_test_ids']) != Counter(authoritative_ids):
        errors.append('executed test-ID multiset differs from authoritative discovery')
    result['authoritative_test_ids'] = authoritative_ids
    result['coverage_exact'] = not errors
    result['successful'] = not errors
    return result


def coordinate_workers(plan_path, output_path, timeout):
    """This process owns every worker/tool descendant for parent timeout cleanup."""
    plan = json.loads(Path(plan_path).read_text(encoding='utf-8'))
    folder = Path(output_path).parent
    progress_path = folder / 'progress.jsonl'
    outcomes = []
    def execute(worker):
        worker_path = folder / f"worker_{worker['worker']}.json"
        result_path = folder / f"worker_{worker['worker']}_result.json"
        worker_path.write_text(json.dumps(worker), encoding='utf-8')
        command = run([sys.executable, 'scripts/v4/run_rtl.py', '--internal-worker-plan',
                       str(worker_path), '--internal-test-output', str(result_path)], timeout=timeout)
        try:
            data = json.loads(result_path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            data = None
        return dict(worker=worker['worker'], command=command, result=data)
    with ThreadPoolExecutor(max_workers=len(plan['groups'])) as executor:
        pending = [executor.submit(execute, worker) for worker in plan['groups']]
        for future in as_completed(pending):
            outcome = future.result()
            outcomes.append(outcome)
            data = outcome['result'] or {}
            progress = dict(worker=outcome['worker'], returncode=outcome['command']['returncode'],
                            tests=data.get('tests'), finished_utc=datetime.now(timezone.utc).isoformat())
            with progress_path.open('a', encoding='utf-8') as log:
                log.write(json.dumps(progress) + '\n')
                log.flush()
            print('Worker completion: ' + json.dumps(progress), flush=True)
    combined = aggregate_workers(plan['test_ids'], plan['groups'], sorted(outcomes, key=lambda row: row['worker']))
    Path(output_path).write_text(json.dumps(combined, indent=2) + '\n', encoding='utf-8')
    return 0 if combined['successful'] else 1


def baseline_audit(current):
    path = ROOT / 'reports/v4/rtl_baseline_audit_20260909/evidence.json'
    if not path.exists():
        return dict(available=False, path=path.relative_to(ROOT).as_posix(), unchanged=None)
    baseline = json.loads(path.read_text(encoding='utf-8'))
    old = baseline['source_sha256']
    selected = {name: digest for name, digest in old.items()
                if (name.startswith('rtl/v4/') and Path(name).suffix in ('.sv', '.vh'))
                or (name.startswith('verification/v4/') and Path(name).suffix == '.sv')}
    if not selected:
        raise ValueError('baseline archive has no RTL/TB source hashes')
    missing = sorted(set(selected) - set(current))
    changed = {name: dict(baseline=selected[name], current=current[name])
               for name in selected if name in current and selected[name] != current[name]}
    namespace_only = []
    for name in changed:
        archived = path.parent / 'sources' / name
        live = ROOT / name
        if archived.is_file() and live.is_file():
            original = archived.read_bytes()
            if (hashlib.sha256(original).hexdigest() == selected[name]
                    and original.replace(b'V4_', b'CSR_') == live.read_bytes()):
                namespace_only.append(name)
    return dict(available=True, path=path.relative_to(ROOT).as_posix(),
                evidence_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                baseline_status=baseline.get('status'), baseline_tests=baseline.get('tests'),
                baseline_checks=len(baseline.get('checks', [])), compared_files=len(selected),
                changed=changed, missing=missing, unchanged=not changed and not missing,
                namespace_only=sorted(namespace_only),
                other_changes=sorted(set(changed)-set(namespace_only)),
                scope='Existing RTL .sv/.vh and TB .sv only; config/files.f/new files excluded')


def totals(rows):
    return dict(replays=len(rows), cycles=sum(row.get('cycles', 0) for row in rows),
                comparisons=sum(row.get('comparisons', row.get('checks', row.get('signal_checks', 0))) for row in rows))


def vivado_stages(metadata):
    """Count unique successful executions, excluding cache reuse and provenance trees."""
    stages, seen = {}, set()
    def visit(value):
        if isinstance(value, dict):
            argv = value.get('argv')
            if isinstance(argv, list) and argv:
                invocation = value.get('invocation_id')
                name = Path(argv[0]).stem
                if (invocation and invocation not in seen and value.get('execution') == 'executed'
                        and name in ('xvlog', 'xelab', 'xsim') and value.get('returncode') == 0):
                    seen.add(invocation)
                    stages[name] = stages.get(name, 0) + 1
                # A command is a leaf: its source identity is provenance, not execution.
                return
            for key, child in value.items():
                if key not in ('source_identity', 'compile_identity', 'identity', 'hashes'):
                    visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(metadata)
    return stages


def write_report(evidence):
    folder = ROOT / 'reports/v4'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'rtl_correctness.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    lines = ['# Unified V4 RTL correctness', '',
             f"Status: **{evidence['status']}**. UTC: {evidence['started_utc']}.", '',
             f"Full regression: {evidence['tests']} tests, {evidence['failures']} failures, {evidence['errors']} errors, {evidence['skips']} skips.",
             f"Checks: {len(evidence['checks'])}; implemented modules: {len(evidence['implemented_modules'])}; simulator: Vivado xvlog/xelab/xsim.",
             f"Source hashes: {len(evidence['source_sha256'])}; stable during run: {evidence['sources_stable_during_run']}.",
             f"Test workers: {evidence['test_workers']}; exact discovered/executed test-ID coverage: {evidence.get('coverage_exact', False)}.", '',
             '| Replay file/list | Replays | Cycles | Checks/comparisons | Kind |', '|---|---:|---:|---:|---|']
    for name, rows in evidence['replays'].items():
        count = totals(rows)
        kinds = ', '.join(sorted({str(row['comparison_kind']) for row in rows if row.get('comparison_kind')}))
        lines.append(f"| {name} | {count['replays']} | {count['cycles']} | {count['comparisons']} | {kinds} |")
    audit = evidence.get('baseline_audit', {})
    lines += ['', 'Baseline preservation: ' + (
        f"{audit.get('compared_files')} old RTL/TB sources compared; unchanged={audit.get('unchanged')}; "
        f"changed={len(audit.get('changed', {}))}, missing={len(audit.get('missing', []))}; "
        f"exact V4_ to CSR_ namespace-only changes={len(audit.get('namespace_only', []))}."
        if audit.get('available') else 'no baseline archive available; no preservation claim.'), '', BOUNDARY, '',
        'Generate/check commands, tool versions, Vivado compile/elaboration/simulation commands, image scopes and all hashes are retained in the JSON.',
        'Compile records retain exact source/header hashes, including generated testbenches. Stage counts deduplicate invocation IDs and exclude reused elaborations.',
        'A PASS requires nonempty successful tests, zero skips, all checks/tools successful, stable sources and actual Vivado compile/elaboration/simulation evidence. Baseline compatibility edits are reported with hashes.', '',
        'Reproduce: `py -3 scripts/v4/run_rtl.py` (three bounded workers). `--test-workers 1` is the serial fallback. `--no-project-check` explicitly omits the generated-document/link check and is recorded in evidence.',
        '[Machine-readable unified evidence](rtl_correctness.json).', '']
    if evidence.get('runner_errors'):
        lines += ['Runner errors:', *['- ' + error for error in evidence['runner_errors']], '']
    (folder / 'RTL_CORRECTNESS.md').write_text('\n'.join(lines), encoding='utf-8')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-project-check', action='store_true')
    parser.add_argument('--test-timeout', type=int, default=1800, help='deadline per worker in seconds')
    parser.add_argument('--test-workers', type=int, choices=(1, 2, 3), default=3, help='bounded complete-module workers; 1 preserves serial execution')
    parser.add_argument('--internal-worker-plan', help=argparse.SUPPRESS)
    parser.add_argument('--internal-coordinate-plan', help=argparse.SUPPRESS)
    parser.add_argument('--internal-test-output', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.internal_worker_plan and args.internal_test_output:
        return test_worker(args.internal_worker_plan, args.internal_test_output)
    if args.internal_coordinate_plan and args.internal_test_output:
        return coordinate_workers(args.internal_coordinate_plan, args.internal_test_output, args.test_timeout)
    if not 1 <= args.test_timeout <= 7200:
        parser.error('--test-timeout must be between 1 and 7200 seconds')
    started = datetime.now(timezone.utc).isoformat()
    before = sources(True)
    errors, checks, versions = [], [], []
    modules, audit = {}, {}
    test_result = dict(tests=0, failures=0, errors=0, skips=0, successful=False,
                       replays={}, compiler_images={}, rtl_commands={}, rtl_compile_output={}, test_output='')
    try:
        versions = tool_versions()
    except Exception as error:
        errors.append(f'Vivado tools required: {error}')
    versions.append(run([sys.executable, '--version']))
    try:
        modules = implemented_modules()
        generators = sorted(set((ROOT / 'scripts/v4').glob('generate_*_interface.py')) |
                            set((ROOT / 'scripts/v4').glob('generate_*_defs.py')))
        if not generators:
            raise ValueError('no interface/definition generators discovered')
        for path in generators:
            checks.append(run([sys.executable, path.relative_to(ROOT).as_posix(), '--check']))
        if not args.no_project_check:
            checks.append(run([sys.executable, 'scripts/v4/project.py', 'check']))
        work = ROOT / 'work'
        work.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='v4_unified_', dir=work) as temporary:
            discovered = discover_test_ids()
            groups = partition_modules(discovered, args.test_workers)
            plan = dict(test_ids=[name for names in discovered.values() for name in names], groups=groups)
            plan_path = Path(temporary) / 'plan.json'
            plan_path.write_text(json.dumps(plan, indent=2), encoding='utf-8')
            result_path = Path(temporary) / 'tests.json'
            print(f"Starting {len(groups)} workers; live completions: {Path(temporary) / 'progress.jsonl'}", flush=True)
            test_command = run([sys.executable, 'scripts/v4/run_rtl.py', '--internal-coordinate-plan',
                                str(plan_path), '--internal-test-output', str(result_path),
                                '--test-timeout', str(args.test_timeout)], timeout=args.test_timeout + 60)
            checks.append(test_command)
            if result_path.exists():
                test_result = json.loads(result_path.read_text(encoding='utf-8'))
            else:
                errors.append('unittest child did not produce complete metadata')
            print(test_command['stdout'])
            if test_command['stderr']:
                print(test_command['stderr'], file=sys.stderr)
        audit = baseline_audit(before)
    except Exception as error:
        errors.append(f'{type(error).__name__}: {error}')
    try:
        after = sources(True)
        stable = before == after
    except Exception as error:
        after, stable = {}, False
        errors.append(f'final source audit failed: {error}')
    stages = vivado_stages(test_result)
    if set(stages) != {'xvlog', 'xelab', 'xsim'}:
        errors.append('full test evidence is missing actual Vivado compile/elaboration/simulation commands')
    passed = (not errors and bool(test_result['tests']) and test_result['successful']
              and not test_result['skips'] and test_result.get('coverage_exact', False) and stable
              and all(row['returncode'] == 0 for row in checks + versions))
    evidence = dict(schema_version=1, status='PASS' if passed else 'FAIL', started_utc=started,
                    finished_utc=datetime.now(timezone.utc).isoformat(), invocation=[sys.executable, *sys.argv],
                    python=sys.version, full_v4_regression=True, test_workers=args.test_workers, project_check=not args.no_project_check,
                    implemented_modules=modules, simulator="Vivado xvlog/xelab/xsim", vivado_stages=stages, checks=checks, versions=versions,
                    source_sha256=before, source_sha256_after=after, sources_stable_during_run=stable,
                    baseline_audit=audit, runner_errors=errors, scope=BOUNDARY,
                    synthesis_run=False, implementation_run=False, **test_result)
    write_report(evidence)
    print(ROOT / 'reports/v4/rtl_correctness.json')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
