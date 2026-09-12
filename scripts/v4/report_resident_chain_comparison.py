"""Fail-closed A/B/C resident-chain comparison from source-bound fixed8 archives."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ACTIVE = ('MP', 'GP', 'IHT', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP', 'FISTA', 'PDHG')
QR = frozenset({'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'})
CONFIG_ALLOWED_DIFFERENCES = frozenset({'qr_profile', 'report_name'})
# A threshold-only comparison may opt in to this one scheduling knob.  The
# default remains the historic fully strict configuration comparison.
THRESHOLD_CONFIG_DIFFERENCES = frozenset({'qr_panel_min_columns'})
# Operand-chain experiments must name their one benchmark knob explicitly.
# Keeping this separate from the threshold allowance prevents an ordinary
# A/B/C comparison from silently accepting a new compiler scheduling profile.
OPERAND_CHAIN_CONFIG_DIFFERENCES = frozenset({'operand_chains'})
OPERAND_CHAIN_ALGORITHMS = frozenset({'GP', 'IHT', 'FISTA', 'PDHG'})
# Feature-9 is a QR-only factor/public operand-chain lowering.  Its helper is
# deliberately separate from the historic A/B/C and feature-8 helpers.
FACTOR_RANGE_TEMPLATE_CONFIG_DIFFERENCES = frozenset({'factor_range_template'})
FACTOR_RANGE_TEMPLATE_ALGORITHMS = QR
# Feature-10 is a QR-only factor reflector energy/tap lowering.  It gets its
# own comparator because an energy tap may change executable QR images while
# physical QR work must remain exactly unchanged.
FACTOR_ENERGY_TAP_CONFIG_DIFFERENCES = frozenset({'factor_energy_tap'})
FACTOR_ENERGY_TAP_ALGORITHMS = QR
PRODUCTION_SOURCE_EXCLUSIONS = frozenset({'benchmark_config.json'})
IDENTITY = (
    'rows', 'columns', 'requested_sparsity', 'requested_outer_iterations',
    'outer_iterations', 'raw_phi_sha256', 'raw_y_sha256',
    'output_raw_x_sha256', 'output_raw_r_sha256', 'accepted_support',
    'accepted_support_scope', 'inner_iterations', 'status',
    'fixed_numeric_events', 'fixed_model_trace', 'fixed_solver_trace',
    'solver_invocations', 'solver_solve_count', 'solver_refinement_count',
    'maximum_ls_support', 'total_committed_inner_iterations',
)


class ValidationError(ValueError):
    """Raised when an input cannot support a fair fixed8 comparison."""


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_summary(path):
    path = Path(path)
    path = path / 'summary.json' if path.is_dir() else path
    if not path.is_file():
        raise ValidationError(f'missing summary: {path}')
    try:
        return path.resolve(), json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValidationError(f'invalid JSON {path}: {error}') from error


def require_digest(value, label):
    if not isinstance(value, str) or len(value) != 64:
        raise ValidationError(f'{label}: missing SHA-256 digest')


def source_manifest(summary, path, label):
    """Rehash the archived source snapshot rather than trusting its manifest."""
    sources = summary.get('source_sha256')
    if not isinstance(sources, dict) or not sources:
        raise ValidationError(f'{label}: missing source hash manifest')
    snapshot = path.parent / 'source_snapshot'
    if not snapshot.is_dir():
        raise ValidationError(f'{label}: missing source_snapshot')
    actual = {str(file.relative_to(snapshot)).replace('\\', '/'): digest(file)
              for file in snapshot.rglob('*') if file.is_file()}
    if set(actual) != set(sources):
        raise ValidationError(f'{label}: source_snapshot file set differs from manifest')
    for name, value in sources.items():
        require_digest(value, f'{label}: source {name}')
        if actual[name] != value:
            raise ValidationError(f'{label}: source_snapshot digest mismatch for {name}')
    return sources


def require_clean(summary, path, label):
    if summary.get('status') != 'PASS':
        raise ValidationError(f'{label}: status must be PASS')
    if summary.get('changed_sources') != []:
        raise ValidationError(f'{label}: changed_sources must be an explicit empty list')
    if summary.get('untracked_imports') != []:
        raise ValidationError(f'{label}: untracked_imports must be an explicit empty list')
    return source_manifest(summary, path, label)


def require_frozen_benchmark_config(summary, path, label):
    """Bind the summary configuration to the archived benchmark input.

    The archived source manifest already rehashes benchmark_config.json.  This
    additional comparison prevents a summary from selecting a different
    algorithm set, profile, or policy while retaining a clean source snapshot.
    JSON object order is retained by the decoder, so compare it as recorded as
    well as by value.
    """
    frozen_path = path.parent / 'source_snapshot' / 'benchmark_config.json'
    if not frozen_path.is_file():
        raise ValidationError(f'{label}: missing archived benchmark_config.json')
    try:
        frozen = json.loads(frozen_path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValidationError(f'{label}: invalid archived benchmark_config.json') from error
    config = summary.get('config')
    if not isinstance(config, dict) or not isinstance(frozen, dict):
        raise ValidationError(f'{label}: summary or archived benchmark config is invalid')
    if list(config.items()) != list(frozen.items()):
        raise ValidationError(f'{label}: summary config differs from archived benchmark_config.json')
    return config


def unique_artifact(root, value, pattern, label):
    require_digest(value, label)
    matches = [path for path in Path(root).rglob(pattern) if digest(path) == value]
    if len(matches) != 1:
        raise ValidationError(f'{label}: artifact match count {len(matches)}')
    return matches[0]


def load_digest(case, root, label):
    package_path = unique_artifact(root, case.get('package_sha256'), 'package.json', f'{label}: package')
    package = json.loads(package_path.read_text(encoding='utf-8'))
    if package.get('algorithm') != case.get('algorithm'):
        raise ValidationError(f'{label}: package algorithm mismatch')
    load_path = package_path.with_name('load.txt')
    if not load_path.is_file():
        raise ValidationError(f'{label}: package lacks executable load.txt')
    loaded = hashlib.sha256(load_path.read_text(encoding='utf-8').replace('\r\n', '\n').encode('utf-8')).hexdigest()
    if package.get('load_sha256') != loaded:
        raise ValidationError(f'{label}: package load digest disagrees with load.txt')
    claimed = case.get('load_image_sha256', case.get('load_sha256'))
    if claimed is not None and claimed != loaded:
        raise ValidationError(f'{label}: summary load digest disagrees with load.txt')
    match = re.fullmatch(r'package(\d+)', package_path.parent.name)
    if match is None:
        raise ValidationError(f'{label}: package directory must carry replay index')
    return loaded, package_path.parent, match.group(1)


def artifact_digests(case, root, config, label):
    load, replay_root, index = load_digest(case, root, label)
    trace = replay_root.parent / f'trace{index}.txt'
    fixture = replay_root.parent / f'case{index}.txt'
    if not trace.is_file() or not fixture.is_file():
        raise ValidationError(f'{label}: replay fixture or trace is missing')
    if digest(trace) != case.get('trace_sha256') or digest(fixture) != case.get('fixture_sha256'):
        raise ValidationError(f'{label}: replay fixture or trace digest mismatch')
    stdout = case.get('stdout')
    # The archive relocates byte-identical replay files, while stdout retains
    # the original execution-root path.  Bind the command to the indexed
    # artifact name and its independently rehashed archived bytes.
    fixture_arg = re.escape(fixture.name)
    trace_arg = re.escape(trace.name)
    if (not isinstance(stdout, str) or re.search(r'fixture=\S*' + fixture_arg + r'(?=\s)', stdout) is None or
            re.search(r'trace=\S*' + trace_arg + r'(?=\s)', stdout) is None or 'PASS cycles=' not in stdout or
            f'-testplusarg scale={config["scale"]}' not in stdout or
            f'-testplusarg instruction_limit={case["instruction_limit"]}' not in stdout):
        raise ValidationError(f'{label}: replay command context is incomplete')
    return {'load': load, 'trace_sha256': digest(trace), 'fixture_sha256': digest(fixture),
            'replay_index': int(index)}


def service_totals(case, label):
    totals = case.get('cycle_profile', {}).get('service_totals')
    if not isinstance(totals, dict):
        raise ValidationError(f'{label}: missing cycle-profile service totals')
    out = {}
    for name, value in totals.items():
        if not isinstance(value, dict):
            raise ValidationError(f'{label}: invalid service {name}')
        calls, clocks, frames = value.get('calls'), value.get('clocks'), value.get('accepted_frames')
        if not all(isinstance(item, int) and item >= 0 for item in (calls, clocks, frames)):
            raise ValidationError(f'{label}: incomplete service interval {name}')
        out[name] = {'calls': calls, 'clocks': clocks, 'accepted_frames': frames}
    return out


def load_cases(summary, path, rows, label, expected_algorithms=ACTIVE):
    sources = require_clean(summary, path, label)
    config = require_frozen_benchmark_config(summary, path, label)
    columns = 64 if rows == 32 else 256
    required_config = ('rows', 'columns', 'scale', 'sparsity', 'outer', 'gomp_extra',
                       'inner_limit', 'qr_refinements', 'qr_panel_min_columns',
                       'expected_phi_sha256', 'expected_y_sha256',
                       'fixed_iteration_benchmark', 'accelerated_oracle',
                       'fast_elaboration', 'instruction_limit_override',
                       'algorithms', 'qr_profile', 'report_name')
    missing_config = [name for name in required_config if name not in config]
    if missing_config:
        raise ValidationError(f'{label}: missing config fields {missing_config}')
    if (config.get('rows') != rows or config.get('columns') != columns or
            config.get('sparsity') != 8 or config.get('outer') != 8 or
            config.get('fixed_iteration_benchmark') is not True):
        raise ValidationError(f'{label}: expected M{rows}/N{columns}/K8/fixed outer8')
    require_digest(config['expected_phi_sha256'], f'{label}: expected Phi')
    require_digest(config['expected_y_sha256'], f'{label}: expected Y')
    expected_algorithms = tuple(expected_algorithms)
    if not expected_algorithms or len(set(expected_algorithms)) != len(expected_algorithms) or set(expected_algorithms) - set(ACTIVE):
        raise ValidationError(f'{label}: invalid expected algorithm subset')
    if not isinstance(config['algorithms'], list) or len(config['algorithms']) != len(expected_algorithms) or set(config['algorithms']) != set(expected_algorithms):
        raise ValidationError(f'{label}: active algorithm config mismatch')
    found = {}
    for case in summary.get('cases', []):
        algorithm = case.get('algorithm')
        if algorithm not in expected_algorithms or algorithm in found:
            raise ValidationError(f'{label}: invalid active algorithm {algorithm!r}')
        missing = [name for name in IDENTITY if name not in case]
        if missing:
            raise ValidationError(f'{label}/{algorithm}: missing fairness fields {missing}')
        if (case['rows'] != rows or case['columns'] != columns or
                case['requested_sparsity'] not in (8, None) or
                len(case.get('planted_support', [])) != 8 or
                case['requested_outer_iterations'] != 8 or case['outer_iterations'] != 8 or
                case.get('returncode') != 0 or not isinstance(case['status'], str)):
            raise ValidationError(f'{label}/{algorithm}: geometry, K, outer, or return-code mismatch')
        if not isinstance(case.get('policy'), dict) or not case['policy']:
            raise ValidationError(f'{label}/{algorithm}: missing non-empty policy')
        if case['raw_phi_sha256'] != config['expected_phi_sha256'] or case['raw_y_sha256'] != config['expected_y_sha256']:
            raise ValidationError(f'{label}/{algorithm}: raw input differs from benchmark config')
        quality = case.get('quality')
        if not isinstance(quality, dict) or not isinstance(quality.get('fixed', {}).get('snr_db'), (int, float)):
            raise ValidationError(f'{label}/{algorithm}: missing fixed quality evidence')
        if not isinstance(case.get('job_cycles'), int) or case['job_cycles'] <= 0:
            raise ValidationError(f'{label}/{algorithm}: invalid job cycles')
        case = dict(case)
        case['_artifacts'] = artifact_digests(case, path.parent, config, f'{label}/{algorithm}')
        case['_services'] = service_totals(case, f'{label}/{algorithm}')
        found[algorithm] = case
    missing = sorted(set(expected_algorithms) - set(found))
    if missing:
        raise ValidationError(f'{label}: missing active algorithms {missing}')
    return found, config, sources


def parse_allowed(value, label):
    allowed = frozenset(item for item in value.split(',') if item)
    bad = sorted(allowed - QR)
    if bad:
        raise ValidationError(f'{label}: changed set contains non-QR algorithm(s) {bad}')
    return allowed


def parse_allowed_config(value, label):
    """Parse an explicit, threshold-only config allowance for one phase."""
    allowed = frozenset(item for item in value.split(',') if item)
    bad = sorted(allowed - THRESHOLD_CONFIG_DIFFERENCES)
    if bad:
        raise ValidationError(f'{label}: config allowance is not threshold-only {bad}')
    return allowed


def compare_case(before, after, rows, algorithm, allowed, allow_nonqr_images=False):
    changed = [name for name in IDENTITY if before[name] != after[name]]
    if changed:
        raise ValidationError(f'M{rows}/{algorithm}: changed mathematical evidence {changed}')
    if before.get('policy') != after.get('policy'):
        raise ValidationError(f'M{rows}/{algorithm}: changed policy')
    if before.get('quality') != after.get('quality'):
        raise ValidationError(f'M{rows}/{algorithm}: changed raw quality')
    # The fixture and trace artifacts include the loaded program/PC trace, so
    # a permitted QR image change can legitimately change their byte hashes.
    # Each artifact is nevertheless resolved and rehashed above.  Raw Phi/Y
    # and all observable X/R/support/quality fields remain strict identities.
    load_changed = before['_artifacts']['load'] != after['_artifacts']['load']
    if load_changed and algorithm not in allowed:
        raise ValidationError(f'M{rows}/{algorithm}: executable image changed outside explicit QR set')
    if algorithm not in QR and load_changed and not allow_nonqr_images:
        raise ValidationError(f'M{rows}/{algorithm}: non-QR executable image changed')
    return {
        'algorithm': algorithm,
        'cycles_before': before['job_cycles'],
        'cycles_after': after['job_cycles'],
        'reduction_percent': (before['job_cycles'] - after['job_cycles']) * 100 / before['job_cycles'],
        'actual_outer_iterations': 8,
        'image_changed': load_changed,
        'artifacts': {'before': before['_artifacts'], 'after': after['_artifacts']},
        'quality': after['quality'],
        'logical_ls': {key: after[key] for key in ('solver_invocations', 'solver_solve_count', 'solver_refinement_count', 'maximum_ls_support', 'total_committed_inner_iterations')},
        'numeric_events': after['fixed_numeric_events'],
        'retired': {'before': before.get('retired_instructions'), 'after': after.get('retired_instructions')},
        'services': {'before': before['_services'], 'after': after['_services']},
    }


def compare_config(before, after, label, allowed_config_differences=frozenset(),
                   permitted_config_differences=THRESHOLD_CONFIG_DIFFERENCES):
    # load_cases has already required each side to carry exactly the unique
    # ACTIVE set.  Scheduling order in that configuration list does not alter
    # a reset/load job, so compare its canonical set while retaining strict
    # equality for every policy, input, iteration, and execution field.
    def value(config, name):
        if name == 'algorithms':
            return tuple(sorted(config.get(name, ())))
        return config.get(name)
    allowed_config_differences = frozenset(allowed_config_differences)
    permitted_config_differences = frozenset(permitted_config_differences)
    bad = sorted(allowed_config_differences - permitted_config_differences)
    if bad:
        raise ValidationError(f'{label}: config allowance is not permitted for this comparison {bad}')
    allowed = CONFIG_ALLOWED_DIFFERENCES | allowed_config_differences
    changed = [name for name in sorted(set(before) | set(after))
               if name not in allowed and value(before, name) != value(after, name)]
    if changed:
        raise ValidationError(f'{label}: config differs outside explicit allowance: {changed}')


def production_sources(manifest):
    return {name: value for name, value in manifest.items()
            if name not in PRODUCTION_SOURCE_EXCLUSIONS}


def _pair(before_arg, after_arg, rows, label, allowed, require_same_production,
          allowed_config_differences, permitted_config_differences, allowance_kind,
          allow_nonqr_images=False):
    before_path, before_summary = read_summary(before_arg)
    after_path, after_summary = read_summary(after_arg)
    before, before_config, before_sources = load_cases(before_summary, before_path, rows, f'{label} before M{rows}')
    after, after_config, after_sources = load_cases(after_summary, after_path, rows, f'{label} after M{rows}')
    compare_config(before_config, after_config, f'{label}/M{rows}', allowed_config_differences,
                   permitted_config_differences)
    if require_same_production and production_sources(before_sources) != production_sources(after_sources):
        raise ValidationError(f'{label}/M{rows}: resident/compact production source manifests differ')
    result = [compare_case(before[algorithm], after[algorithm], rows, algorithm, allowed,
                           allow_nonqr_images) for algorithm in ACTIVE]
    actual = frozenset(row['algorithm'] for row in result if row['image_changed'])
    if actual - allowed:
        raise ValidationError(f'{label}/M{rows}: changed image set exceeds explicit allowance {sorted(actual - allowed)}')
    return {'rows': rows, 'columns': 64 if rows == 32 else 256,
            'before_summary_sha256': digest(before_path), 'after_summary_sha256': digest(after_path),
            'source_manifests': {'before': before_sources, 'after': after_sources},
            'allowance_kind': allowance_kind,
            # Keep the historic serialized field for A/B/C consumers.  The
            # operand-chain helper records its non-QR set separately.
            'allowed_changed_qr': sorted(allowed) if allowance_kind == 'legacy-qr-threshold' else [],
            'allowed_changed_algorithms': sorted(allowed),
            'allowed_config_differences': sorted(allowed_config_differences),
            'actual_changed_images': sorted(actual), 'rows_output': result}


def pair(before_arg, after_arg, rows, label, allowed, require_same_production=False,
         allowed_config_differences=frozenset()):
    """Historic A/B/C comparison: QR images and threshold knob only."""
    return _pair(before_arg, after_arg, rows, label, allowed, require_same_production,
                 allowed_config_differences, THRESHOLD_CONFIG_DIFFERENCES, 'legacy-qr-threshold')


def prove_pre_operand_chain_baseline(summary, path, rows, label):
    """Prove a missing operand_chains key belongs to the pre-feature8 ABI.

    The exception never inserts a synthetic false configuration value.  It
    rehashes the frozen closure, binds the archived benchmark configuration,
    resolves every package/load/fixture/trace through the normal loader, and
    then inspects the resolved decoded program words for newer opcodes.
    """
    sources = require_clean(summary, path, label)
    config = require_frozen_benchmark_config(summary, path, label)
    if 'operand_chains' in config:
        raise ValidationError(f'{label}: legacy baseline must omit operand_chains')
    interface_path = path.parent / 'source_snapshot' / 'config' / 'v4_kernel_interface.json'
    interface_name = 'config/v4_kernel_interface.json'
    if interface_name not in sources or not interface_path.is_file():
        raise ValidationError(f'{label}: legacy baseline lacks frozen kernel interface')
    try:
        interface = json.loads(interface_path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValidationError(f'{label}: invalid frozen kernel interface') from error
    revision = interface.get('revision') if isinstance(interface, dict) else None
    if type(revision) is not int or revision > 7:
        raise ValidationError(f'{label}: omitted operand_chains requires frozen kernel revision <= 7')

    cases, _, _ = load_cases(summary, path, rows, label)
    for algorithm, case in cases.items():
        _, package_dir, _ = load_digest(case, path.parent, f'{label}/{algorithm}')
        package_path = package_dir / 'package.json'
        try:
            decoded = json.loads(package_path.read_text(encoding='utf-8')).get('decoded')
        except json.JSONDecodeError as error:
            raise ValidationError(f'{label}/{algorithm}: invalid rehashed package JSON') from error
        if not isinstance(decoded, list):
            raise ValidationError(f'{label}/{algorithm}: legacy package lacks decoded program')
        for word_index, word in enumerate(decoded):
            if not isinstance(word, dict):
                raise ValidationError(f'{label}/{algorithm}: invalid decoded word {word_index}')
            if word.get('kind') == 1:
                opcode = word.get('kernel')
                if type(opcode) is not int or opcode < 0:
                    raise ValidationError(f'{label}/{algorithm}: invalid decoded kernel opcode {word_index}')
                if opcode >= 23:
                    raise ValidationError(f'{label}/{algorithm}: legacy package uses kernel opcode {opcode}')
    return {'kernel_revision': revision, 'packages_checked': len(cases)}


def pair_operand_chain(before_arg, after_arg, rows, label, allowed_changed_algorithms=frozenset(),
                       require_same_production=False, allow_legacy_baseline=False):
    """Explicit step-2 comparison for compiler operand-chain scheduling.

    Only the `operand_chains` benchmark configuration key may vary, and only
    the four non-QR programs that can emit this feature may change images.
    All mathematical evidence, policy, quality, LS counters, source closure,
    frozen benchmark binding, and actual-eight checks still use `_pair`.
    """
    allowed_changed_algorithms = frozenset(allowed_changed_algorithms)
    bad = sorted(allowed_changed_algorithms - OPERAND_CHAIN_ALGORITHMS)
    if bad:
        raise ValidationError(f'{label}: operand-chain image allowance contains unsupported algorithms {bad}')
    before_path, before_summary = read_summary(before_arg)
    after_path, after_summary = read_summary(after_arg)
    before_config = require_frozen_benchmark_config(before_summary, before_path, f'{label} before M{rows}')
    after_config = require_frozen_benchmark_config(after_summary, after_path, f'{label} after M{rows}')
    legacy_proof = None
    if before_config.get('operand_chains') is False:
        pass
    elif allow_legacy_baseline and 'operand_chains' not in before_config:
        legacy_proof = prove_pre_operand_chain_baseline(
            before_summary, before_path, rows, f'{label} before M{rows}')
    else:
        raise ValidationError(f'{label}: operand_chains comparison must be explicit false→true')
    if after_config.get('operand_chains') is not True:
        raise ValidationError(f'{label}: operand_chains comparison must be explicit false→true')
    result = _pair(before_arg, after_arg, rows, label, allowed_changed_algorithms,
                   require_same_production, OPERAND_CHAIN_CONFIG_DIFFERENCES,
                   OPERAND_CHAIN_CONFIG_DIFFERENCES, 'operand-chain', True)
    if legacy_proof is not None:
        result['legacy_pre_operand_chain_baseline'] = legacy_proof
    return result


def _physical_factor_counts(case, label):
    """Bind reported QR physical work to the independently recorded services."""
    required = ('factor_init_calls', 'factor_extend_calls', 'builds', 'qr_reuse_enabled')
    missing = [name for name in required if name not in case]
    if missing:
        raise ValidationError(f'{label}: missing physical QR fields {missing}')
    if (not isinstance(case['factor_init_calls'], int) or case['factor_init_calls'] < 0 or
            not isinstance(case['factor_extend_calls'], int) or case['factor_extend_calls'] < 0 or
            not isinstance(case['builds'], int) or case['builds'] < 0 or
            not isinstance(case['qr_reuse_enabled'], bool)):
        raise ValidationError(f'{label}: invalid physical QR fields')
    services = service_totals(case, label)
    init = services.get('KERNEL:13', {}).get('calls', 0)
    extend = services.get('KERNEL:19', {}).get('calls', 0)
    builds = sum(value['calls'] for name, value in services.items() if name.startswith('BUILD:'))
    observed = {'factor_init_calls': init, 'factor_extend_calls': extend, 'builds': builds,
                'qr_reuse_enabled': case['qr_reuse_enabled']}
    for name in ('factor_init_calls', 'factor_extend_calls', 'builds'):
        if case[name] != observed[name]:
            raise ValidationError(f'{label}: {name} disagrees with service totals')
    return observed


def prove_pre_factor_range_template_baseline(summary, path, rows, label):
    """Prove an omitted feature-9 flag is an archived pre-op24 closure."""
    sources = require_clean(summary, path, label)
    config = require_frozen_benchmark_config(summary, path, label)
    if 'factor_range_template' in config:
        raise ValidationError(f'{label}: legacy baseline must omit factor_range_template')
    interface_path = path.parent / 'source_snapshot' / 'config' / 'v4_kernel_interface.json'
    if 'config/v4_kernel_interface.json' not in sources or not interface_path.is_file():
        raise ValidationError(f'{label}: legacy baseline lacks frozen kernel interface')
    try:
        revision = json.loads(interface_path.read_text(encoding='utf-8')).get('revision')
    except json.JSONDecodeError as error:
        raise ValidationError(f'{label}: invalid frozen kernel interface') from error
    if type(revision) is not int or revision > 8:
        raise ValidationError(f'{label}: omitted factor_range_template requires frozen kernel revision <= 8')
    cases, _, _ = load_cases(summary, path, rows, label)
    for algorithm, case in cases.items():
        _, package_dir, _ = load_digest(case, path.parent, f'{label}/{algorithm}')
        try:
            decoded = json.loads((package_dir / 'package.json').read_text(encoding='utf-8')).get('decoded')
        except json.JSONDecodeError as error:
            raise ValidationError(f'{label}/{algorithm}: invalid rehashed package JSON') from error
        if not isinstance(decoded, list):
            raise ValidationError(f'{label}/{algorithm}: legacy package lacks decoded program')
        for word_index, word in enumerate(decoded):
            if not isinstance(word, dict) or (word.get('kind') == 1 and
                                              (type(word.get('kernel')) is not int or word['kernel'] >= 24)):
                raise ValidationError(f'{label}/{algorithm}: legacy package uses invalid/new kernel opcode {word_index}')
    return {'kernel_revision': revision, 'packages_checked': len(cases)}


def pair_factor_range_template(before_arg, after_arg, rows, label,
                               allowed_changed_algorithms=frozenset(),
                               require_same_production=False,
                               allow_legacy_baseline=False):
    """Fail-closed feature-9 comparison; only QR images may change."""
    allowed_changed_algorithms = frozenset(allowed_changed_algorithms)
    bad = sorted(allowed_changed_algorithms - FACTOR_RANGE_TEMPLATE_ALGORITHMS)
    if bad:
        raise ValidationError(f'{label}: factor-range image allowance contains non-QR algorithms {bad}')
    before_path, before_summary = read_summary(before_arg)
    after_path, after_summary = read_summary(after_arg)
    before_config = require_frozen_benchmark_config(before_summary, before_path, f'{label} before M{rows}')
    after_config = require_frozen_benchmark_config(after_summary, after_path, f'{label} after M{rows}')
    if before_config.get('qr_profile') != after_config.get('qr_profile'):
        raise ValidationError(f'{label}: factor-range comparison requires identical qr_profile')
    legacy_proof = None
    if before_config.get('factor_range_template') is False:
        pass
    elif allow_legacy_baseline and 'factor_range_template' not in before_config:
        legacy_proof = prove_pre_factor_range_template_baseline(before_summary, before_path, rows,
                                                                 f'{label} before M{rows}')
    else:
        raise ValidationError(f'{label}: factor_range_template comparison must be explicit false→true')
    if after_config.get('factor_range_template') is not True:
        raise ValidationError(f'{label}: factor_range_template comparison must be explicit false→true')
    result = _pair(before_arg, after_arg, rows, label, allowed_changed_algorithms,
                   require_same_production, FACTOR_RANGE_TEMPLATE_CONFIG_DIFFERENCES,
                   FACTOR_RANGE_TEMPLATE_CONFIG_DIFFERENCES, 'factor-range-template')
    before_cases, _, _ = load_cases(before_summary, before_path, rows, f'{label} before M{rows}')
    after_cases, _, _ = load_cases(after_summary, after_path, rows, f'{label} after M{rows}')
    result['physical_qr_counts'] = {
        'before': {algorithm: _physical_factor_counts(case, f'{label} before M{rows}/{algorithm}')
                   for algorithm, case in before_cases.items()},
        'after': {algorithm: _physical_factor_counts(case, f'{label} after M{rows}/{algorithm}')
                  for algorithm, case in after_cases.items()},
    }
    if legacy_proof is not None:
        result['legacy_pre_factor_range_template_baseline'] = legacy_proof
    return result


def prove_pre_factor_energy_tap_baseline(summary, path, rows, label):
    """Prove an omitted feature-10 flag belongs to a frozen pre-op25 run."""
    sources = require_clean(summary, path, label)
    config = require_frozen_benchmark_config(summary, path, label)
    if 'factor_energy_tap' in config:
        raise ValidationError(f'{label}: legacy baseline must omit factor_energy_tap')
    interface_path = path.parent / 'source_snapshot' / 'config' / 'v4_kernel_interface.json'
    interface_name = 'config/v4_kernel_interface.json'
    if interface_name not in sources or not interface_path.is_file():
        raise ValidationError(f'{label}: legacy baseline lacks frozen kernel interface')
    try:
        revision = json.loads(interface_path.read_text(encoding='utf-8')).get('revision')
    except json.JSONDecodeError as error:
        raise ValidationError(f'{label}: invalid frozen kernel interface') from error
    if type(revision) is not int or revision > 9:
        raise ValidationError(f'{label}: omitted factor_energy_tap requires frozen kernel revision <= 9')
    cases, _, _ = load_cases(summary, path, rows, label)
    for algorithm, case in cases.items():
        _, package_dir, _ = load_digest(case, path.parent, f'{label}/{algorithm}')
        try:
            decoded = json.loads((package_dir / 'package.json').read_text(encoding='utf-8')).get('decoded')
        except json.JSONDecodeError as error:
            raise ValidationError(f'{label}/{algorithm}: invalid rehashed package JSON') from error
        if not isinstance(decoded, list):
            raise ValidationError(f'{label}/{algorithm}: legacy package lacks decoded program')
        for word_index, word in enumerate(decoded):
            if not isinstance(word, dict) or (word.get('kind') == 1 and
                                              (type(word.get('kernel')) is not int or word['kernel'] >= 25)):
                raise ValidationError(f'{label}/{algorithm}: legacy package uses invalid/new kernel opcode {word_index}')
    return {'kernel_revision': revision, 'packages_checked': len(cases)}


def pair_factor_energy_tap(before_arg, after_arg, rows, label,
                           allowed_changed_algorithms=frozenset(),
                           require_same_production=False,
                           allow_legacy_baseline=False):
    """Fail-closed feature-10 comparison for a QR reflector energy tap.

    The only allowed configuration difference is explicit ``factor_energy_tap``
    false-to-true.  QR images may change only for the caller-declared subset of
    the five QR algorithms.  Every case still rehashes its immutable closure and
    replay artifacts; X/R/support/policy/quality/logical-LS/actual-eight remain
    identity fields.  INIT/EXTEND/BUILD/reuse counts are independently derived
    from the service totals and must remain equal across the pair.
    """
    allowed_changed_algorithms = frozenset(allowed_changed_algorithms)
    bad = sorted(allowed_changed_algorithms - FACTOR_ENERGY_TAP_ALGORITHMS)
    if bad:
        raise ValidationError(f'{label}: factor-energy image allowance contains non-QR algorithms {bad}')
    before_path, before_summary = read_summary(before_arg)
    after_path, after_summary = read_summary(after_arg)
    before_config = require_frozen_benchmark_config(before_summary, before_path, f'{label} before M{rows}')
    after_config = require_frozen_benchmark_config(after_summary, after_path, f'{label} after M{rows}')
    if before_config.get('qr_profile') != after_config.get('qr_profile'):
        raise ValidationError(f'{label}: factor-energy comparison requires identical qr_profile')
    legacy_proof = None
    if before_config.get('factor_energy_tap') is False:
        pass
    elif allow_legacy_baseline and 'factor_energy_tap' not in before_config:
        legacy_proof = prove_pre_factor_energy_tap_baseline(before_summary, before_path, rows,
                                                            f'{label} before M{rows}')
    else:
        raise ValidationError(f'{label}: factor_energy_tap comparison must be explicit false→true')
    if after_config.get('factor_energy_tap') is not True:
        raise ValidationError(f'{label}: factor_energy_tap comparison must be explicit false→true')
    result = _pair(before_arg, after_arg, rows, label, allowed_changed_algorithms,
                   require_same_production, FACTOR_ENERGY_TAP_CONFIG_DIFFERENCES,
                   FACTOR_ENERGY_TAP_CONFIG_DIFFERENCES, 'factor-energy-tap')
    before_cases, _, _ = load_cases(before_summary, before_path, rows, f'{label} before M{rows}')
    after_cases, _, _ = load_cases(after_summary, after_path, rows, f'{label} after M{rows}')
    physical_before = {
        algorithm: _physical_factor_counts(case, f'{label} before M{rows}/{algorithm}')
        for algorithm, case in before_cases.items()
    }
    physical_after = {
        algorithm: _physical_factor_counts(case, f'{label} after M{rows}/{algorithm}')
        for algorithm, case in after_cases.items()
    }
    if physical_before != physical_after:
        raise ValidationError(f'{label}/M{rows}: factor-energy comparison changed physical QR work')
    result['physical_qr_counts'] = {'before': physical_before, 'after': physical_after}
    if legacy_proof is not None:
        result['legacy_pre_factor_energy_tap_baseline'] = legacy_proof
    return result


def pair_bitmap_sort(before_arg, after_arg, rows, label,
                     require_same_production=False):
    """Fail-closed comparison for the runtime-only bitmap SORT phase.

    This phase has no benchmark knob and permits no program-image change.  It
    still passes through the normal frozen-config, artifact rehash, policy,
    output, support, quality, actual-eight, and source-closure validation in
    ``_pair``.  In addition, QR physical work is bound to service totals and
    must be byte-for-byte equivalent as structured counts on both sides.
    """
    before_path, before_summary = read_summary(before_arg)
    after_path, after_summary = read_summary(after_arg)
    before_config = require_frozen_benchmark_config(before_summary, before_path,
                                                    f'{label} before M{rows}')
    after_config = require_frozen_benchmark_config(after_summary, after_path,
                                                  f'{label} after M{rows}')
    if before_config.get('qr_profile') != after_config.get('qr_profile'):
        raise ValidationError(f'{label}: bitmap-sort comparison requires identical qr_profile')
    result = _pair(before_arg, after_arg, rows, label, frozenset(),
                   require_same_production, frozenset(), frozenset(), 'bitmap-sort')
    before_cases, _, _ = load_cases(before_summary, before_path, rows,
                                    f'{label} before M{rows}')
    after_cases, _, _ = load_cases(after_summary, after_path, rows,
                                   f'{label} after M{rows}')
    physical_before = {
        algorithm: _physical_factor_counts(case, f'{label} before M{rows}/{algorithm}')
        for algorithm, case in before_cases.items()
    }
    physical_after = {
        algorithm: _physical_factor_counts(case, f'{label} after M{rows}/{algorithm}')
        for algorithm, case in after_cases.items()
    }
    if physical_before != physical_after:
        raise ValidationError(f'{label}/M{rows}: bitmap-sort comparison changed physical QR work')
    result['physical_qr_counts'] = {'before': physical_before, 'after': physical_after}
    return result


def pair_panel_schedule(before_arg, after_arg, rows, label,
                        require_same_production=False):
    """Fail-closed comparison for a runtime-only factor-panel schedule change.

    This intentionally mirrors the bitmap comparator's hard guards while
    labeling a distinct phase.  It permits no config or program-image change
    and independently binds INIT/EXTEND/BUILD/reuse counts to service totals.
    """
    before_path, before_summary = read_summary(before_arg)
    after_path, after_summary = read_summary(after_arg)
    before_config = require_frozen_benchmark_config(before_summary, before_path,
                                                    f'{label} before M{rows}')
    after_config = require_frozen_benchmark_config(after_summary, after_path,
                                                  f'{label} after M{rows}')
    if before_config.get('qr_profile') != after_config.get('qr_profile'):
        raise ValidationError(f'{label}: panel-schedule comparison requires identical qr_profile')
    result = _pair(before_arg, after_arg, rows, label, frozenset(),
                   require_same_production, frozenset(), frozenset(), 'panel-schedule')
    before_cases, _, _ = load_cases(before_summary, before_path, rows,
                                    f'{label} before M{rows}')
    after_cases, _, _ = load_cases(after_summary, after_path, rows,
                                   f'{label} after M{rows}')
    physical_before = {
        algorithm: _physical_factor_counts(case, f'{label} before M{rows}/{algorithm}')
        for algorithm, case in before_cases.items()
    }
    physical_after = {
        algorithm: _physical_factor_counts(case, f'{label} after M{rows}/{algorithm}')
        for algorithm, case in after_cases.items()
    }
    if physical_before != physical_after:
        raise ValidationError(f'{label}/M{rows}: panel-schedule comparison changed physical QR work')
    result['physical_qr_counts'] = {'before': physical_before, 'after': physical_after}
    return result


def render_pair(name, geometry):
    lines = [f'## {name}: M={geometry["rows"]}, N={geometry["columns"]}', '',
             '| Thuật toán | Cycle trước | Cycle sau | Giảm % | outer | Image đổi | LS/refine | Numeric events |',
             '|---|---:|---:|---:|---:|---|---:|---:|']
    for row in geometry['rows_output']:
        ls = row['logical_ls']
        lines.append(f"| {row['algorithm']} | {row['cycles_before']} | {row['cycles_after']} | {row['reduction_percent']:.2f} | 8 | {'có' if row['image_changed'] else 'không'} | {ls['solver_solve_count']}/{ls['solver_refinement_count']} | {row['numeric_events']} |")
    return lines + ['']


def render(result):
    lines = ['# So sánh chuỗi operand resident A/B/C', '',
             'Mọi cặp là M32/N64/K8 hoặc M64/N256/K8 với outer thực tế bằng 8. Validator fail-closed đối chiếu policy, Phi/Y, X/R, support, status, quality raw, logical LS/correction, numeric events, fixture, trace và executable load artifacts trước khi ghi cycle.', '',
             'A chỉ cô lập remap writeback. B chỉ cô lập `FACTOR_PROJECT_UPDATE` và không có remap. C so sánh hai profile resident/compact từ cùng production source để cô lập scalar insertion; C bao gồm A+B nhưng bảng không gán phần trăm của C cho một thay đổi đơn lẻ. Chỉ tập QR được khai báo rõ có thể đổi image; mọi non-QR phải giữ image giống nhau.', '',
             'Fixed8 quality là diagnostic cùng fixture, không phải held-out application qualification hoặc tuyên bố PPA, synthesis, timing, board hay production bit.', '']
    for phase in result['phases']:
        lines.extend(render_pair(phase['name'], phase['m32']))
        lines.extend(render_pair(phase['name'], phase['m64']))
    return '\n'.join(lines) + '\n'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for phase in ('baseline', 'phase-a', 'phase-b', 'phase-c-resident', 'phase-c-compact'):
        parser.add_argument(f'--{phase}-m32', required=True)
        parser.add_argument(f'--{phase}-m64', required=True)
    parser.add_argument('--phase-a-changed-qr', default='')
    parser.add_argument('--phase-b-changed-qr', required=True)
    parser.add_argument('--phase-c-changed-qr', required=True)
    parser.add_argument('--phase-a-allowed-config-differences', default='')
    parser.add_argument('--phase-b-allowed-config-differences', default='')
    parser.add_argument('--phase-c-allowed-config-differences', default='')
    parser.add_argument('--output', required=True)
    args = parser.parse_args(argv)
    output = Path(args.output)
    if output.exists():
        raise ValidationError(f'output exists: {output}')
    phase_specs = (
        ('A: remap writeback', 'phase_a', 'baseline', 'phase-a', parse_allowed(args.phase_a_changed_qr, 'phase A'), parse_allowed_config(args.phase_a_allowed_config_differences, 'phase A')),
        ('B: FACTOR_PROJECT_UPDATE', 'phase_b', 'baseline', 'phase-b', parse_allowed(args.phase_b_changed_qr, 'phase B'), parse_allowed_config(args.phase_b_allowed_config_differences, 'phase B')),
        ('C: resident → compact', 'phase_c', 'phase-c-resident', 'phase-c-compact', parse_allowed(args.phase_c_changed_qr, 'phase C'), parse_allowed_config(args.phase_c_allowed_config_differences, 'phase C')),
    )
    phases = []
    for name, key, before, after, allowed, allowed_config in phase_specs:
        same_production = key == 'phase_c'
        phases.append({'name': name, 'key': key,
                       'm32': pair(getattr(args, before.replace('-', '_') + '_m32'), getattr(args, after.replace('-', '_') + '_m32'), 32, key, allowed, same_production, allowed_config),
                       'm64': pair(getattr(args, before.replace('-', '_') + '_m64'), getattr(args, after.replace('-', '_') + '_m64'), 64, key, allowed, same_production, allowed_config)})
    result = {'schema': 1, 'status': 'PASS', 'scope': 'source-bound active10 fixed K8/actual outer8; complete A/B/C only', 'phases': phases}
    output.mkdir(parents=True)
    (output / 'resident_chain_comparison.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    (output / 'resident_chain_comparison_vi.md').write_text(render(result), encoding='utf-8')


if __name__ == '__main__':
    main()
