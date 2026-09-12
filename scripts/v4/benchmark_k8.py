"""Source-frozen native K=8 timing/quality fixtures; Vivado xsim only.

Create a tree with --freeze --rows 64 --columns 256 --scale 8192.
Run the returned tree with its cwd/PYTHONPATH and --run. Production code is
copied unchanged; model dispatch below only selects the existing quality oracle.
"""
import os
for _thread_key in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ[_thread_key] = '1'
import argparse
from contextlib import nullcontext
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v4 import greedy_qr_emit, qr_program
from models.v4 import qr, lsqr
from verification.v4 import test_recovery_algorithms_rtl as helper
from verification.v4.exact_model_context import model_acceleration

CONFIG = ROOT / 'benchmark_config.json'
RUNS = []
OBSERVED = {}
ORIGINAL_GREEDY = helper.run
ORIGINAL_PROXIMAL = helper.proximal_run
ORIGINAL_POLICY = helper.Policy
ACCELERATED_ORACLE = False
ALL_ALGORITHMS = ('MP', 'GP', 'IHT', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP', 'FISTA', 'PDHG', 'ADMM')
ACTIVE_ALGORITHMS = tuple(algorithm for algorithm in ALL_ALGORITHMS if algorithm != 'ADMM')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_default(value):
    if hasattr(value, 'item'):
        return value.item()
    if hasattr(value, 'tolist'):
        return value.tolist()
    raise TypeError(type(value).__name__)


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, default=json_default))


def quality_comparison(quality):
    """Both absolute NMSE limits plus relative limits, including exact-zero error."""
    fixed, floating = quality['fixed']['nmse'], quality['floating']['nmse']
    valid = all(math.isfinite(value) and value >= 0 for value in (fixed, floating))
    ratio = (fixed / floating if floating > 0 else 1.0 if fixed == 0 else None) if valid else None
    loss = 10 * math.log10(ratio) if ratio is not None and ratio > 0 else None
    passed = (valid and fixed <= 0.01 and floating <= 0.01 and ratio is not None
              and math.isfinite(ratio) and ratio <= 1.1 and (ratio == 0 or loss <= 0.5))
    return dict(nmse_ratio=ratio, snr_loss_db=loss, threshold_pass=passed,
                threshold_definition='Both fixed/float NMSE<=0.01, fixed/float NMSE ratio<=1.1, SNR loss<=0.5dB; both zero errors pass, positive fixed error against zero float error fails')


def oracle_mode(enabled):
    return dict(
        enabled=bool(enabled),
        vm_gemv='optional_bounded_c18_s27_acc64' if enabled else 'default_arithmetic_matvec',
        fixed_model='scoped_integer_reductions' if enabled else 'default_model_methods',
        floating_model='default_model_methods',
        scope='VM GEMV and fixed-profile model calls only; floating model, RTL, policy and arithmetic contracts are unchanged')


def model_call(call, profile):
    """Keep the optional process-global model patch inside one fixed call."""
    with (model_acceleration() if ACCELERATED_ORACLE and profile is not None else nullcontext()):
        return call()


def greedy_dispatch(algorithm, matrix, measurement, policy, profile=None, **kwargs):
    # The shared case() calls its `run` name for planted floating quality even
    # for proximal algorithms. Choose their existing model, not a new oracle.
    if algorithm in ('FISTA', 'ADMM', 'PDHG'):
        result = model_call(lambda: ORIGINAL_PROXIMAL(algorithm, matrix, measurement, policy, profile), profile)
    else:
        result = model_call(lambda: ORIGINAL_GREEDY(algorithm, matrix, measurement, policy, profile, **kwargs), profile)
    OBSERVED['fixed' if profile is not None else 'floating'] = result
    return result


def proximal_dispatch(algorithm, matrix, measurement, policy, profile=None):
    result = model_call(lambda: ORIGINAL_PROXIMAL(algorithm, matrix, measurement, policy, profile), profile)
    OBSERVED['fixed' if profile is not None else 'floating'] = result
    return result


def sources():
    result = {ROOT / name for name in helper.SOURCES}
    pending = list(result)
    while pending:
        source = pending.pop()
        for name in re.findall(r'`include\s+"([^"]+)"', source.read_text()):
            target = ROOT / 'rtl/v4/include' / name
            if target not in result:
                result.add(target)
                pending.append(target)
    for module in tuple(sys.modules.values()):
        location = getattr(module, '__file__', None)
        if location:
            path = Path(location).resolve()
            if path.suffix == '.py' and path.is_relative_to(ROOT):
                result.add(path)
    result.update(ROOT / name for name in (
        'config/v4_program_interface.json', 'config/v4_kernel_interface.json',
        'config/v4_stream_interface.json', 'config/v4_recovery_interface.json',
        'config/v4_design.json', 'rtl/v4/files.f',
        # __main__ is not named scripts.* in sys.modules.  Pin the runner and
        # its optional oracle helpers explicitly so a frozen child is runnable
        # and audited even before either backend has been called.
        'scripts/v4/benchmark_k8.py', 'scripts/v4/k8_exact_integer_acceleration.py',
        'verification/v4/exact_model_context.py', 'verification/v4/exact_vm_gemv.py'))
    calibration = json.loads((ROOT / 'config/v4_gemv_mapping_calibration.json').read_text())
    result.add(ROOT / 'config/v4_gemv_mapping_calibration.json')
    result.update(ROOT / name for name in calibration['source_sha256'])
    if CONFIG.exists():
        result.add(CONFIG)
    return result


def freeze(args):
    work_root = ROOT / 'work'
    work_root.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix=f'k8_m{args.rows}_n{args.columns}_', dir=work_root))
    (destination / 'work').mkdir()
    hashes = {}
    for source in sorted(sources()):
        name = source.relative_to(ROOT).as_posix()
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        target.write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    assert all(digest(ROOT / name) == value for name, value in hashes.items()), 'source changed during copy'
    cfg = dict(rows=args.rows, columns=args.columns, scale=args.scale, sparsity=8,
               outer=8, gomp_extra=args.gomp_extra, inner_limit=24, qr_refinements=2,
               report_name=args.report_name or f'k8_m{args.rows}_n{args.columns}_rtl_20260909',
               expected_phi_sha256=args.expected_phi, expected_y_sha256=args.expected_y)
    cfg['qr_profile'] = args.qr_profile
    cfg['qr_panel_min_columns'] = args.qr_panel_min_columns
    cfg['operand_chains'] = bool(args.operand_chains)
    cfg['outer_fusion'] = bool(args.outer_fusion)
    cfg['factor_range_template'] = bool(args.factor_range_template)
    cfg['factor_energy_tap'] = bool(args.factor_energy_tap)
    cfg['instruction_limit_override'] = args.instruction_limit
    cfg['fixed_iteration_benchmark'] = args.fixed_iterations
    cfg['accelerated_oracle'] = bool(args.accelerated_oracle)
    cfg['fast_elaboration'] = bool(args.fast_elaboration)
    selected = tuple(part.strip() for part in args.algorithms.split(',') if part.strip())
    unknown = sorted(set(selected) - set(ALL_ALGORITHMS))
    if unknown:
        raise ValueError(f'unknown algorithms: {", ".join(unknown)}')
    if not selected:
        raise ValueError('--algorithms must name at least one algorithm')
    if len(set(selected)) != len(selected):
        raise ValueError('--algorithms may not repeat an algorithm')
    cfg['algorithms'] = list(selected)
    dump(destination / CONFIG.name, cfg)
    hashes[CONFIG.name] = digest(destination / CONFIG.name)
    dump(destination / 'snapshot_manifest.json', dict(origin=str(ROOT), execution_root=str(destination), sources=hashes))
    print(destination)


def requested_cases(cfg):
    algorithms = tuple(cfg.get('algorithms', ALL_ALGORITHMS))
    if not algorithms or set(algorithms) - set(ALL_ALGORITHMS):
        raise ValueError('frozen config has invalid algorithms')
    cases = [(a, cfg['outer']) for a in algorithms]
    return cases + ([('GOMP', cfg['gomp_extra'])] if cfg['gomp_extra'] and 'GOMP' in algorithms else [])


def case_args(cfg, algorithm, outer):
    return dict(rows=cfg['rows'], n=cfg['columns'], sparsity=8,
                iterations=outer, scale_override=cfg['scale'], planted=True,
                sparse_forward=algorithm in ('MP', 'GP', 'IHT'),
                refinements=cfg['qr_refinements'], inner_limit=cfg['inner_limit'],
                qr_profile=cfg['qr_profile'],
                qr_panel_min_columns=cfg.get('qr_panel_min_columns', 8),
                operand_chains=bool(cfg.get('operand_chains', False)),
                outer_fusion=bool(cfg.get('outer_fusion', False)),
                factor_range_template=bool(cfg.get('factor_range_template', False)),
                factor_energy_tap=bool(cfg.get('factor_energy_tap', False)))


def numerical_preflight(cfg, report):
    """Run unchanged helper oracle checks before xsim; determine watchdog need."""
    class Complete(Exception):
        pass
    class Preflight(unittest.TestCase):
        attempt_index = 0
        run_records = []
    instance = Preflight()
    instance.path = Path(tempfile.mkdtemp(prefix='k8_preflight_', dir=ROOT / 'work'))
    instance.binary = instance.path / 'not_compiled'
    old_execute, old_simulate = helper.execute, helper.run_rtl
    current = {}
    def execute(*args, **kwargs):
        result = old_execute(*args, **kwargs)
        current['retired_instructions'] = len(result['trace'])
        current['status'] = result['status']
        current['actual_outer'] = result['outer']
        return result
    def simulate(*args, **kwargs):
        raise Complete()
    helper.execute, helper.run_rtl = execute, simulate
    rows = []
    try:
        for algorithm, outer in requested_cases(cfg):
            current.clear()
            try:
                helper.RecoveryAlgorithmsRtlTests.case(instance, algorithm, **case_args(cfg, algorithm, outer))
            except Complete:
                if cfg.get('fixed_iteration_benchmark'):
                    assert current['actual_outer'] == outer, (algorithm, current)
                rows.append(dict(algorithm=algorithm, outer=outer, **current))
                print(f'PREFLIGHT {algorithm} outer={outer} {current}', flush=True)
    finally:
        helper.execute, helper.run_rtl = old_execute, old_simulate
    assert len(rows) == len(requested_cases(cfg))
    instruction_limit=max(10000,max(row['retired_instructions'] for row in rows)+1)
    dump(report / 'numerical_preflight.json', dict(cases=rows, instruction_limit=instruction_limit,
         plusarg_used=instruction_limit>10000, testbench_watchdog_patch=None))
    return instruction_limit


class K8Programs(unittest.TestCase):
    run_records = RUNS
    setUpClass = classmethod(helper.RecoveryAlgorithmsRtlTests.setUpClass.__func__)

    @classmethod
    def tearDownClass(cls):
        dump(cls.path / 'evidence.json', RUNS)

    def test_algorithms(self):
        cfg = json.loads(CONFIG.read_text())
        for algorithm, outer in requested_cases(cfg):
            with self.subTest(algorithm=algorithm, outer=outer):
                OBSERVED.clear()
                attempt = self.attempt_index
                helper.RecoveryAlgorithmsRtlTests.case(
                    self, algorithm, **case_args(cfg, algorithm, outer),
                    instruction_limit=getattr(type(self), 'instruction_limit', None),
                    vm_limit=getattr(type(self), 'vm_limit', 100000))
                record = RUNS[-1]
                for key, expected in (('raw_phi_sha256', cfg['expected_phi_sha256']),
                                      ('raw_y_sha256', cfg['expected_y_sha256'])):
                    if expected:
                        self.assertEqual(record[key], expected, 'original matched fixture changed')
                fixed = OBSERVED['fixed']
                floating = OBSERVED['floating']
                record['fixed_model_trace'] = fixed.trace
                record['fixed_solver_trace'] = fixed.solver_trace
                record['fixed_numeric_events'] = fixed.events
                record['floating_model_trace'] = floating.trace
                record['solver_invocations'] = len(fixed.solver_trace)
                record['solver_solve_count'] = sum(r.get('steps', 0) for r in fixed.solver_trace)
                record['solver_refinement_count'] = sum(r.get('refinement_steps', 0) for r in fixed.solver_trace)
                record['maximum_ls_support'] = max((len(r.get('support', [])) for r in fixed.solver_trace), default=0)
                record['total_committed_inner_iterations'] = sum(r.get('inner_iterations', 0) for r in fixed.trace if r.get('phase') == 'COMMIT')
                record['accepted_support_size'] = len(record['accepted_support'])
                record['qr_refinement_limit'] = cfg['qr_refinements']
                record['snr_at_least_20_db'] = (record['quality']['fixed']['nmse'] <= 0.01)
                quality = record['quality']
                quality.update(quality_comparison(quality))
                package = json.loads((self.path / f'package{attempt}/package.json').read_text())
                record['program_length'] = len(package['program'])
                record['template_count'] = len(package['templates'])
                record['load_record_count'] = len(helper.asm.load_records(package))
                record['mapping_metadata'] = {k: v for k, v in package.items() if 'mapping' in k or 'r4' in k}
                record['qr_execution_profile'] = package.get('qr_execution_profile')
                record['qr_reuse_enabled'] = bool(package.get('qr_reuse_enabled', False))
                record['qr_factor_init_transport'] = package.get('qr_factor_init_transport')
                record['qr_factor_extend_transport'] = package.get('qr_factor_extend_transport')
                record['qr_resident_project_enabled'] = bool(package.get('qr_resident_project_enabled', False))
                record['qr_scalar_insert_enabled'] = bool(package.get('qr_scalar_insert_enabled', False))
                record['qr_stream_scalar_insert_enabled'] = bool(package.get('qr_stream_scalar_insert_enabled', False))
                record['qr_panel_requested_min_columns'] = package.get('qr_panel_requested_min_columns')
                record['qr_panel_min_columns'] = package.get('qr_panel_min_columns')
                record['qr_factor_project_update_transport'] = package.get('qr_factor_project_update_transport')
                record['operand_chains'] = bool(package.get('operand_chains', False))
                record['factor_range_template'] = bool(package.get('qr_factor_range_template_enabled', False))
                record['factor_energy_tap'] = bool(package.get('qr_factor_energy_tap_enabled', False))
                record['required_kernel_revision'] = package.get('required_kernel_revision', 1)
                trace = (self.path / f'trace{attempt}.txt').read_text()
                metadata = [line.split() for line in trace.splitlines() if line.startswith('M 1 ')][-1]
                record['published_support_enabled'] = bool(int(metadata[6]))
                record['published_support_size'] = int(metadata[7])
                record['actual_nonzero_coefficients'] = sum(int(line.split()[3], 16) != 0
                    for line in trace.splitlines() if line.startswith('X 1 '))
                record['accepted_support_scope'] = 'Fixed model support/nonzero-index list; proximal publication disables active support. See published_support_size and actual_nonzero_coefficients.'
                done_cycles = [int(line.split()[-1]) for line in trace.splitlines() if line.startswith('D ')]
                record['fixture_non_job_cycles'] = record['cycles'] - sum(done_cycles)
                record['raw_setup_markers'] = [line for line in record['stdout'].splitlines()
                    if line.startswith(('Phi ready cycles=', 'Program loaded job=', 'Started job='))]
                record['timing_scope'] = dict(
                    start_done='Accepted START through held DONE; includes BUILD and candidate drain/publication',
                    result_drain=record['cycle_profile']['result_drain_clocks'],
                    fixture_non_job='Aggregate setup, program/Phi/vector loading, inspection and inter-job clocks for both test jobs; not isolated preload latency',
                    cold_preload_separate=None, clock_frequency='Not synthesized or implemented')
                record['fixed_iteration_benchmark'] = cfg.get('fixed_iteration_benchmark', False)
                if record['fixed_iteration_benchmark']:
                    self.assertEqual(record['outer_iterations'], outer)
                dump(self.path / 'evidence.json', RUNS)
                print(f"K8 {algorithm} requested={outer} actual={record['outer_iterations']} "
                      f"support={record['accepted_support_size']} cycles={record['job_cycles']} "
                      f"status={record['status']} snr={record['quality']['fixed']['snr_db']}", flush=True)


def run():
    global ACCELERATED_ORACLE
    cfg = json.loads(CONFIG.read_text())
    manifest = json.loads((ROOT / 'snapshot_manifest.json').read_text())
    for name, value in manifest['sources'].items():
        assert digest(ROOT / name) == value, name
    if cfg.get('fixed_iteration_benchmark'):
        def fixed_policy(*args, **kwargs):
            kwargs.update(residual_atol=0, sp_stop_on_non_decrease=False)
            return ORIGINAL_POLICY(*args, **kwargs)
        helper.Policy = fixed_policy
    ACCELERATED_ORACLE = bool(cfg.get('accelerated_oracle', False))
    if ACCELERATED_ORACLE:
        original_execute = helper.execute
        def execute_accelerated(*args, **kwargs):
            if 'accelerate_gemv' in kwargs:
                raise TypeError('benchmark owns accelerate_gemv mode')
            return original_execute(*args, **kwargs, accelerate_gemv=True)
        helper.execute = execute_accelerated
    if cfg.get('fast_elaboration', False):
        original_compile = helper.compile_rtl
        def compile_fast(*args, **kwargs):
            if 'debug' in kwargs or 'optimization' in kwargs:
                raise TypeError('benchmark owns elaboration mode')
            return original_compile(*args, **kwargs, debug='off', optimization=3)
        helper.compile_rtl = compile_fast
    helper.run = greedy_dispatch
    helper.proximal_run = proximal_dispatch
    report = ROOT / 'reports/v4' / cfg['report_name']
    report.mkdir(parents=True, exist_ok=True)
    preflight_instruction_limit = numerical_preflight(cfg, report)
    override = cfg.get('instruction_limit_override')
    if override is not None and (isinstance(override, bool) or not isinstance(override, int) or not 1 <= override < 2**32):
        raise ValueError('--instruction-limit must be a positive 32-bit integer')
    instruction_limit = override if override is not None else preflight_instruction_limit
    # Preserve the RTL testbench's documented 10000 default.  Only a
    # preflight-derived extension becomes a plusarg.
    K8Programs.instruction_limit = instruction_limit if (override is not None or instruction_limit > 10000) else None
    K8Programs.vm_limit = max(100000, instruction_limit)
    tracked = sources()
    hashes = {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(tracked)}
    for source in tracked:
        target = report / 'source_snapshot' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(K8Programs))
    changed = [name for name, value in hashes.items() if digest(ROOT / name) != value]
    imports = []
    for name, module in tuple(sys.modules.items()):
        location = getattr(module, '__file__', None)
        if location and name.split('.')[0] in ('compiler', 'models', 'verification', 'scripts'):
            path = Path(location).resolve()
            if not path.is_relative_to(ROOT) or path.relative_to(ROOT).as_posix() not in hashes:
                imports.append(str(path))
    expected = len(requested_cases(cfg))
    passed = (result.wasSuccessful() and result.testsRun == 1 and not result.skipped
              and len(RUNS) == expected and not changed and not imports)
    summary = dict(status='PASS' if passed else 'FAIL', config=cfg, replays=len(RUNS), expected_replays=expected,
                   failures=len(result.failures), errors=len(result.errors), elapsed_seconds=time.monotonic() - started,
                   source_sha256=hashes, changed_sources=changed, untracked_imports=imports,
                   execution_root=str(ROOT), scope='Current-source frozen K8 timing fixtures, unchanged arithmetic/policies. '
                   'Real loaded programs, QR for restricted LS, same32PEs. Bit-exact fixed X/R/support/status and own VM PC trace. '
                   'Numerical quality is reported, never tuned; no V2/V3 input-equivalence or Fmax claim.')
    summary['instruction_limit'] = instruction_limit
    summary['preflight_instruction_limit'] = preflight_instruction_limit
    summary['plusarg_used'] = K8Programs.instruction_limit is not None
    summary['testbench_watchdog_patch'] = None
    summary['oracle_mode'] = oracle_mode(ACCELERATED_ORACLE)
    summary['elaboration_mode'] = dict(debug='off', optimization=3) if cfg.get('fast_elaboration', False) else dict(debug='typical', optimization=None)
    summary['cases'] = RUNS
    dump(report / 'focused_summary.json', summary)
    dump(report / 'summary.json', summary)
    dump(report / 'evidence.json', RUNS)
    dump(report / 'executed_manifest.json', dict(execution_root=str(ROOT), sources=hashes))
    if hasattr(K8Programs, 'path'):
        shutil.copytree(K8Programs.path, report / K8Programs.path.name, dirs_exist_ok=True)
    print(json.dumps(summary, indent=2), flush=True)
    return 0 if passed else 1


def argument_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument('--freeze', action='store_true')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--rows', type=int, default=64)
    parser.add_argument('--columns', type=int, default=256)
    parser.add_argument('--scale', type=int, default=8192)
    parser.add_argument('--gomp-extra', type=int, default=4)
    parser.add_argument('--report-name')
    parser.add_argument('--expected-phi')
    parser.add_argument('--expected-y')
    parser.add_argument('--instruction-limit', type=int, help='Test-only explicit watchdog plusarg; omit to use the preflight-derived limit and preserve the 10000 testbench default when sufficient')
    parser.add_argument('--fixed-iterations', action='store_true', help='Benchmark only: greedy residual_atol=0 and SP nondecrease stop disabled; require actual outer count equals budget')
    parser.add_argument('--accelerated-oracle', action='store_true', help='Use only the proven optional VM GEMV and scoped fixed-model integer backends')
    parser.add_argument('--fast-elaboration', action='store_true', help='Vivado debug off/O3; simulation runtime only')
    parser.add_argument('--algorithms', default=','.join(ACTIVE_ALGORITHMS), help='Comma-separated active algorithms; ADMM remains an explicit reference-only selection')
    parser.add_argument('--qr-profile', choices=('reference', 'balanced', 'panel', 'reuse', 'resident', 'compact', 'streamed', 'view'), default='reference',
                        help='Explicit QR schedule; streamed requires kernel revision6; view requires kernel revision7 and adds command-scoped RANGE_TEMPLATE QR reads')
    parser.add_argument('--qr-panel-min-columns', type=int, default=8,
                        help='Panel/reuse/resident/compact/streamed profiles: explicit generic factor-panel threshold for statically reachable wider trailing rectangles')
    parser.add_argument('--operand-chains', action=argparse.BooleanOptionalAction, default=False,
                        help='Explicit feature8 non-QR ROUNDED_AFFINE ablation; default preserves separate SCALE then ADD/SUB programs')
    parser.add_argument('--outer-fusion', action=argparse.BooleanOptionalAction, default=False,
                        help='Opt-in rounded HTP outer update; all other algorithms retain their image')
    parser.add_argument('--factor-range-template', action=argparse.BooleanOptionalAction, default=False,
                        help='Explicit feature9 QR view factor-range raw-DOT/tap lowering; default preserves the view image')
    parser.add_argument('--factor-energy-tap', action=argparse.BooleanOptionalAction, default=False,
                        help='Explicit feature10 QR view factor-square raw-energy/tap lowering; default preserves the view image')
    return parser


if __name__ == '__main__':
    parser = argument_parser()
    args = parser.parse_args()
    if args.freeze:
        freeze(args)
    elif args.run:
        raise SystemExit(run())
    else:
        parser.error('choose --freeze or --run')

