import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from scripts.v4 import report_resident_chain_comparison as subject

HASH_A = 'a' * 64
HASH_B = 'b' * 64


def normalized_hash(path):
    return hashlib.sha256(path.read_text(encoding='utf-8').replace('\r\n', '\n').encode('utf-8')).hexdigest()


def case(algorithm, rows):
    columns = 64 if rows == 32 else 256
    return {
        'algorithm': algorithm, 'rows': rows, 'columns': columns,
        'requested_sparsity': 8, 'requested_outer_iterations': 8,
        'outer_iterations': 8, 'planted_support': list(range(8)),
        'raw_phi_sha256': HASH_A, 'raw_y_sha256': HASH_B,
        'output_raw_x_sha256': HASH_A, 'output_raw_r_sha256': HASH_B,
        'accepted_support': list(range(8)), 'accepted_support_scope': 'published',
        'inner_iterations': 1, 'status': 'max_iterations', 'returncode': 0,
        'fixed_numeric_events': 0, 'fixed_model_trace': HASH_A,
        'fixed_solver_trace': HASH_B, 'solver_invocations': 1,
        'solver_solve_count': 1, 'solver_refinement_count': 0,
        'maximum_ls_support': 8, 'total_committed_inner_iterations': 1,
        'factor_init_calls': 1, 'factor_extend_calls': 0, 'builds': 0,
        'qr_reuse_enabled': True,
        'policy': {'name': 'fixed8'}, 'quality': {'fixed': {'snr_db': 30.0}, 'floating': {'snr_db': 30.0}, 'nmse_ratio': 1.0},
        'job_cycles': 1000, 'retired_instructions': 10, 'instruction_limit': 99,
        'cycle_profile': {'service_totals': {'KERNEL:13': {'calls': 1, 'clocks': 4, 'accepted_frames': 0},
                                             'KERNEL:19': {'calls': 0, 'clocks': 0, 'accepted_frames': 0},
                                             'BUILD:0': {'calls': 0, 'clocks': 0, 'accepted_frames': 0}}},
    }


def summary(rows):
    columns = 64 if rows == 32 else 256
    return {'status': 'PASS', 'changed_sources': [], 'untracked_imports': [],
            'source_sha256': {},
            'config': {'rows': rows, 'columns': columns, 'scale': 1, 'sparsity': 8, 'outer': 8,
                       'gomp_extra': 0, 'inner_limit': 24, 'qr_refinements': 2,
                       'qr_panel_min_columns': 8, 'expected_phi_sha256': HASH_A,
                       'expected_y_sha256': HASH_B, 'fixed_iteration_benchmark': True,
                       'accelerated_oracle': True, 'fast_elaboration': True,
                       'instruction_limit_override': None, 'algorithms': list(subject.ACTIVE),
                       'qr_profile': 'reuse', 'report_name': 'synthetic'},
            'cases': [case(algorithm, rows) for algorithm in subject.ACTIVE]}


class ResidentChainComparisonTests(unittest.TestCase):
    def archive(self, root, name, payload, suffix):
        path = root / name
        path.mkdir()
        source = path / 'source_snapshot' / 'rtl' / 'v4'
        source.mkdir(parents=True)
        source_file = source / 'example.sv'
        source_file.write_text('module example; endmodule\n', encoding='utf-8')
        vm_file = path / 'source_snapshot' / 'verification' / 'v4' / 'recovery_program_vm.py'
        vm_file.parent.mkdir(parents=True)
        vm_file.write_text('def execute(): return 1\n', encoding='utf-8')
        benchmark_file = path / 'source_snapshot' / 'benchmark_config.json'
        benchmark_file.write_text(json.dumps(payload['config'], indent=2) + '\n', encoding='utf-8')
        payload['source_sha256'] = {
            'rtl/v4/example.sv': hashlib.sha256(source_file.read_bytes()).hexdigest(),
            'verification/v4/recovery_program_vm.py': hashlib.sha256(vm_file.read_bytes()).hexdigest(),
            'benchmark_config.json': hashlib.sha256(benchmark_file.read_bytes()).hexdigest(),
        }
        for index, item in enumerate(payload['cases']):
            case_path = path / f'case{index}.txt'
            trace_path = path / f'trace{index}.txt'
            package_dir = path / f'package{index}'
            package_dir.mkdir()
            case_path.write_text(f'fixture {item["algorithm"]}\n', encoding='utf-8')
            trace_path.write_text(f'trace {item["algorithm"]}\n', encoding='utf-8')
            load_path = package_dir / 'load.txt'
            load_path.write_text(f'load {suffix} {item["algorithm"]}\n', encoding='utf-8')
            load_hash = normalized_hash(load_path)
            package_path = package_dir / 'package.json'
            package_path.write_text(json.dumps({
                'algorithm': item['algorithm'], 'load_sha256': load_hash,
                # The legacy-baseline validator inspects rehashed decoded
                # words, rather than trusting a claimed interface revision.
                'decoded': [{'kind': 1, 'kernel': 22}],
            }), encoding='utf-8')
            item['package_sha256'] = hashlib.sha256(package_path.read_bytes()).hexdigest()
            item['trace_sha256'] = hashlib.sha256(trace_path.read_bytes()).hexdigest()
            item['fixture_sha256'] = hashlib.sha256(case_path.read_bytes()).hexdigest()
            item['stdout'] = ('fixture=' + str(case_path).replace('\\', '/') +
                              ' trace=' + str(trace_path).replace('\\', '/') +
                              ' -testplusarg scale=1 -testplusarg instruction_limit=99 PASS cycles=1000')
        (path / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
        return path

    def write_summary_with_frozen_config(self, path, payload):
        benchmark = path / 'source_snapshot' / 'benchmark_config.json'
        benchmark.write_text(json.dumps(payload['config'], indent=2) + '\n', encoding='utf-8')
        payload['source_sha256']['benchmark_config.json'] = hashlib.sha256(benchmark.read_bytes()).hexdigest()
        (path / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')

    def write_frozen_kernel_interface(self, path, revision):
        interface = path / 'source_snapshot' / 'config' / 'v4_kernel_interface.json'
        interface.parent.mkdir(parents=True, exist_ok=True)
        interface.write_text(json.dumps({'revision': revision}) + '\n', encoding='utf-8')
        payload = json.loads((path / 'summary.json').read_text())
        payload['source_sha256']['config/v4_kernel_interface.json'] = hashlib.sha256(interface.read_bytes()).hexdigest()
        (path / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')

    def pair(self, root, rows, before_name, after_name, changed=()):
        before = summary(rows)
        after = copy.deepcopy(before)
        for item in after['cases']:
            item['job_cycles'] = 900
        before_path = self.archive(root, before_name, before, 'shared')
        after_path = self.archive(root, after_name, after, 'shared')
        for algorithm in changed:
            load = after_path / f'package{subject.ACTIVE.index(algorithm)}' / 'load.txt'
            load.write_text(f'load changed {algorithm}\n', encoding='utf-8')
            meta = load.with_name('package.json')
            meta.write_text(json.dumps({
                'algorithm': algorithm, 'load_sha256': normalized_hash(load),
                'decoded': [{'kind': 1, 'kernel': 22}],
            }), encoding='utf-8')
            after['cases'][subject.ACTIVE.index(algorithm)]['package_sha256'] = hashlib.sha256(meta.read_bytes()).hexdigest()
        (after_path / 'summary.json').write_text(json.dumps(after), encoding='utf-8')
        return before_path, after_path

    def operand_pair(self, root, rows, changed=('GP', 'IHT', 'FISTA', 'PDHG')):
        before, after = self.pair(root, rows, 'operand-before', 'operand-after', changed)
        before_payload = json.loads((before / 'summary.json').read_text())
        after_payload = json.loads((after / 'summary.json').read_text())
        before_payload['config']['operand_chains'] = False
        after_payload['config']['operand_chains'] = True
        self.write_summary_with_frozen_config(before, before_payload)
        self.write_summary_with_frozen_config(after, after_payload)
        return before, after

    def legacy_operand_pair(self, root, rows, changed=('GP',)):
        before, after = self.pair(root, rows, 'legacy-before', 'legacy-after', changed)
        after_payload = json.loads((after / 'summary.json').read_text())
        after_payload['config']['operand_chains'] = True
        self.write_summary_with_frozen_config(after, after_payload)
        self.write_frozen_kernel_interface(before, 7)
        return before, after

    def factor_range_pair(self, root, rows, changed=('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP')):
        before, after = self.pair(root, rows, 'factor-before', 'factor-after', changed)
        before_payload = json.loads((before / 'summary.json').read_text())
        after_payload = json.loads((after / 'summary.json').read_text())
        before_payload['config']['factor_range_template'] = False
        after_payload['config']['factor_range_template'] = True
        self.write_summary_with_frozen_config(before, before_payload)
        self.write_summary_with_frozen_config(after, after_payload)
        return before, after

    def argv(self, root, bad_nonqr=False):
        b32, a32 = self.pair(root, 32, 'base32', 'a32')
        b64, a64 = self.pair(root, 64, 'base64', 'a64')
        _, pb32 = self.pair(root, 32, 'ignore32', 'b32', ('GOMP',))
        _, pb64 = self.pair(root, 64, 'ignore64', 'b64', ('GOMP',))
        cr32, cc32 = self.pair(root, 32, 'cr32', 'cc32', ('GOMP',))
        cr64, cc64 = self.pair(root, 64, 'cr64', 'cc64', ('GOMP',))
        if bad_nonqr:
            load = cc32 / f'package{subject.ACTIVE.index("MP")}' / 'load.txt'
            load.write_text('load changed MP\n', encoding='utf-8')
            meta = load.with_name('package.json')
            meta.write_text(json.dumps({
                'algorithm': 'MP', 'load_sha256': normalized_hash(load),
                'decoded': [{'kind': 1, 'kernel': 22}],
            }), encoding='utf-8')
            value = json.loads((cc32 / 'summary.json').read_text())
            value['cases'][subject.ACTIVE.index('MP')]['package_sha256'] = hashlib.sha256(meta.read_bytes()).hexdigest()
            (cc32 / 'summary.json').write_text(json.dumps(value), encoding='utf-8')
        return ['--baseline-m32', str(b32), '--baseline-m64', str(b64),
                '--phase-a-m32', str(a32), '--phase-a-m64', str(a64),
                '--phase-b-m32', str(pb32), '--phase-b-m64', str(pb64),
                '--phase-c-resident-m32', str(cr32), '--phase-c-resident-m64', str(cr64),
                '--phase-c-compact-m32', str(cc32), '--phase-c-compact-m64', str(cc64),
                '--phase-b-changed-qr', 'GOMP', '--phase-c-changed-qr', 'GOMP',
                '--output', str(root / 'out')]

    def test_requires_complete_abc_and_renders(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            subject.main(self.argv(root))
            result = json.loads((root / 'out' / 'resident_chain_comparison.json').read_text())
            self.assertEqual(result['status'], 'PASS')
            self.assertEqual(len(result['phases']), 3)
            self.assertIn('A/B/C', (root / 'out' / 'resident_chain_comparison_vi.md').read_text())

    def test_rejects_nonqr_image_change_and_raw_output_change(self):
        with tempfile.TemporaryDirectory() as raw:
            with self.assertRaisesRegex(subject.ValidationError, 'outside explicit'):
                subject.main(self.argv(Path(raw), bad_nonqr=True))
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); argv = self.argv(root)
            candidate = Path(argv[argv.index('--phase-b-m32') + 1])
            payload = json.loads((candidate / 'summary.json').read_text())
            payload['cases'][0]['output_raw_x_sha256'] = HASH_B
            (candidate / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'mathematical evidence'):
                subject.main(argv)

    def test_rejects_tampered_source_snapshot(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); argv = self.argv(root)
            candidate = Path(argv[argv.index('--phase-b-m32') + 1])
            (candidate / 'source_snapshot' / 'rtl' / 'v4' / 'example.sv').write_text('tampered\n', encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'source_snapshot digest mismatch'):
                subject.main(argv)

    def test_rejects_phase_c_production_source_difference(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); argv = self.argv(root)
            compact = Path(argv[argv.index('--phase-c-compact-m32') + 1])
            source = compact / 'source_snapshot' / 'verification' / 'v4' / 'recovery_program_vm.py'
            source.write_text('def execute(): return 2\n', encoding='utf-8')
            payload = json.loads((compact / 'summary.json').read_text())
            payload['source_sha256']['verification/v4/recovery_program_vm.py'] = hashlib.sha256(source.read_bytes()).hexdigest()
            (compact / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'production source manifests differ'):
                subject.main(argv)

    def test_accepts_reordered_active_algorithm_config_only(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw); argv = self.argv(root)
            candidate = Path(argv[argv.index('--phase-b-m32') + 1])
            payload = json.loads((candidate / 'summary.json').read_text())
            payload['config']['algorithms'].reverse()
            self.write_summary_with_frozen_config(candidate, payload)
            subject.main(argv)
            self.assertEqual(json.loads((root / 'out' / 'resident_chain_comparison.json').read_text())['status'], 'PASS')

    def test_rejects_duplicate_missing_or_unknown_active_algorithm_config(self):
        for name, algorithms in (
                ('duplicate', list(subject.ACTIVE[:-1]) + [subject.ACTIVE[0]]),
                ('missing', list(subject.ACTIVE[:-1])),
                ('unknown', list(subject.ACTIVE[:-1]) + ['NOT_AN_ALGORITHM'])):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as raw:
                root = Path(raw); argv = self.argv(root)
                candidate = Path(argv[argv.index('--phase-b-m32') + 1])
                payload = json.loads((candidate / 'summary.json').read_text())
                payload['config']['algorithms'] = algorithms
                self.write_summary_with_frozen_config(candidate, payload)
                with self.assertRaisesRegex(subject.ValidationError, 'active algorithm config mismatch'):
                    subject.main(argv)

    def test_threshold_config_allowance_is_explicit_and_narrow(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.pair(root, 32, 'before', 'after')
            payload = json.loads((after / 'summary.json').read_text())
            payload['config']['qr_panel_min_columns'] = 16
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'config differs outside explicit allowance'):
                subject.pair(before, after, 32, 'threshold', frozenset())
            result = subject.pair(before, after, 32, 'threshold', frozenset(),
                                  allowed_config_differences={'qr_panel_min_columns'})
            self.assertEqual(result['allowed_config_differences'], ['qr_panel_min_columns'])

    def test_threshold_allowance_cannot_hide_other_config_changes(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.pair(root, 32, 'before', 'after')
            payload = json.loads((after / 'summary.json').read_text())
            payload['config']['qr_panel_min_columns'] = 16
            payload['config']['inner_limit'] = 25
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'inner_limit'):
                subject.pair(before, after, 32, 'threshold', frozenset(),
                             allowed_config_differences={'qr_panel_min_columns'})
            with self.assertRaisesRegex(subject.ValidationError, 'not permitted'):
                subject.pair(before, after, 32, 'threshold', frozenset(),
                             allowed_config_differences={'inner_limit'})

    def test_operand_chain_allowance_is_explicit_and_limited_to_four_programs(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.operand_pair(root, 32)
            result = subject.pair_operand_chain(
                before, after, 32, 'operand-chain', {'GP', 'IHT', 'FISTA', 'PDHG'})
            self.assertEqual(result['allowance_kind'], 'operand-chain')
            self.assertEqual(result['allowed_config_differences'], ['operand_chains'])
            self.assertEqual(result['actual_changed_images'], ['FISTA', 'GP', 'IHT', 'PDHG'])
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.operand_pair(root, 32, ('OMP',))
            with self.assertRaisesRegex(subject.ValidationError, 'outside explicit'):
                subject.pair_operand_chain(before, after, 32, 'operand-chain', frozenset())
            with self.assertRaisesRegex(subject.ValidationError, 'unsupported algorithms'):
                subject.pair_operand_chain(before, after, 32, 'operand-chain', {'OMP'})

    def test_operand_chain_rejects_raw_certificate_and_fixed_iteration_changes(self):
        mutations = (
            ('raw-output', lambda payload: payload['cases'][0].__setitem__('output_raw_x_sha256', HASH_B),
             'mathematical evidence'),
            ('certificate-support', lambda payload: payload['cases'][0].__setitem__('accepted_support', [7]),
             'mathematical evidence'),
            ('fixed-iteration', lambda payload: payload['config'].__setitem__('fixed_iteration_benchmark', False),
             'expected M32/N64/K8/fixed outer8'),
        )
        for name, mutate, expected in mutations:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                before, after = self.operand_pair(root, 32, ('GP',))
                payload = json.loads((after / 'summary.json').read_text())
                mutate(payload)
                self.write_summary_with_frozen_config(after, payload)
                with self.assertRaisesRegex(subject.ValidationError, expected):
                    subject.pair_operand_chain(before, after, 32, 'operand-chain', {'GP'})

    def test_operand_chain_requires_explicit_false_to_true_config(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.operand_pair(root, 32, ('GP',))
            payload = json.loads((after / 'summary.json').read_text())
            payload['config']['operand_chains'] = False
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'explicit false→true'):
                subject.pair_operand_chain(before, after, 32, 'operand-chain', {'GP'})

    def test_operand_chain_legacy_baseline_is_opt_in_and_rehashed(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.legacy_operand_pair(Path(raw), 32)
            with self.assertRaisesRegex(subject.ValidationError, 'explicit false→true'):
                subject.pair_operand_chain(before, after, 32, 'operand-chain', {'GP'})
            result = subject.pair_operand_chain(
                before, after, 32, 'operand-chain', {'GP'}, allow_legacy_baseline=True)
            self.assertEqual(result['legacy_pre_operand_chain_baseline'],
                             {'kernel_revision': 7, 'packages_checked': 10})

    def test_operand_chain_legacy_baseline_rejects_revision8_and_opcode23(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.legacy_operand_pair(Path(raw), 32)
            self.write_frozen_kernel_interface(before, 8)
            with self.assertRaisesRegex(subject.ValidationError, 'revision <= 7'):
                subject.pair_operand_chain(before, after, 32, 'operand-chain', {'GP'},
                                           allow_legacy_baseline=True)

    def test_factor_range_template_is_qr_only_and_binds_physical_counts(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_range_pair(Path(raw), 32)
            result = subject.pair_factor_range_template(
                before, after, 32, 'factor-range', {'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'})
            self.assertEqual(result['allowance_kind'], 'factor-range-template')
            self.assertEqual(result['allowed_config_differences'], ['factor_range_template'])
            self.assertEqual(result['actual_changed_images'], ['CoSaMP', 'GOMP', 'HTP', 'OMP', 'SP'])
            self.assertEqual(result['physical_qr_counts']['after']['OMP']['factor_init_calls'], 1)
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_range_pair(Path(raw), 32, ('GP',))
            with self.assertRaisesRegex(subject.ValidationError, 'non-QR'):
                subject.pair_factor_range_template(before, after, 32, 'factor-range', {'GP'})

    def test_factor_range_template_rejects_profile_and_forged_physical_counts(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_range_pair(Path(raw), 32)
            payload = json.loads((after / 'summary.json').read_text())
            payload['config']['qr_profile'] = 'other'
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'identical qr_profile'):
                subject.pair_factor_range_template(before, after, 32, 'factor-range', set(subject.QR))
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_range_pair(Path(raw), 32)
            payload = json.loads((after / 'summary.json').read_text())
            payload['cases'][0]['factor_init_calls'] = 2
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'factor_init_calls disagrees'):
                subject.pair_factor_range_template(before, after, 32, 'factor-range', set(subject.QR))
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.legacy_operand_pair(Path(raw), 32)
            package = before / 'package0' / 'package.json'
            value = json.loads(package.read_text())
            value['decoded'] = [{'kind': 1, 'kernel': 23}]
            package.write_text(json.dumps(value), encoding='utf-8')
            summary_payload = json.loads((before / 'summary.json').read_text())
            summary_payload['cases'][0]['package_sha256'] = hashlib.sha256(package.read_bytes()).hexdigest()
            (before / 'summary.json').write_text(json.dumps(summary_payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'kernel opcode 23'):
                subject.pair_operand_chain(before, after, 32, 'operand-chain', {'GP'},
                                           allow_legacy_baseline=True)

    def test_bitmap_sort_requires_identical_images_config_and_physical_work(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.pair(root, 32, 'bitmap-before', 'bitmap-after')
            result = subject.pair_bitmap_sort(before, after, 32, 'bitmap-sort')
            self.assertEqual(result['allowance_kind'], 'bitmap-sort')
            self.assertEqual(result['actual_changed_images'], [])
            self.assertEqual(result['physical_qr_counts']['before'],
                             result['physical_qr_counts']['after'])

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.pair(root, 32, 'bitmap-before', 'bitmap-after')
            load = after / 'package0' / 'load.txt'
            load.write_text('load bitmap image changed\n', encoding='utf-8')
            package = load.with_name('package.json')
            package.write_text(json.dumps({'algorithm': 'MP', 'load_sha256': normalized_hash(load),
                                           'decoded': [{'kind': 1, 'kernel': 22}]}), encoding='utf-8')
            payload = json.loads((after / 'summary.json').read_text())
            payload['cases'][0]['package_sha256'] = hashlib.sha256(package.read_bytes()).hexdigest()
            (after / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'outside explicit'):
                subject.pair_bitmap_sort(before, after, 32, 'bitmap-sort')

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.pair(root, 32, 'bitmap-before', 'bitmap-after')
            payload = json.loads((after / 'summary.json').read_text())
            payload['config']['inner_limit'] = 25
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'inner_limit'):
                subject.pair_bitmap_sort(before, after, 32, 'bitmap-sort')

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before, after = self.pair(root, 32, 'bitmap-before', 'bitmap-after')
            payload = json.loads((after / 'summary.json').read_text())
            payload['cases'][0]['factor_extend_calls'] = 1
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'factor_extend_calls disagrees'):
                subject.pair_bitmap_sort(before, after, 32, 'bitmap-sort')

    def test_panel_schedule_requires_identical_images_config_and_physical_work(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.pair(Path(raw), 32, 'schedule-before', 'schedule-after')
            result = subject.pair_panel_schedule(before, after, 32, 'panel-schedule')
            self.assertEqual(result['allowance_kind'], 'panel-schedule')
            self.assertEqual(result['actual_changed_images'], [])
            self.assertEqual(result['physical_qr_counts']['before'],
                             result['physical_qr_counts']['after'])

        with tempfile.TemporaryDirectory() as raw:
            before, after = self.pair(Path(raw), 32, 'schedule-before', 'schedule-after')
            load = after / 'package0' / 'load.txt'
            load.write_text('load schedule image changed\n', encoding='utf-8')
            package = load.with_name('package.json')
            package.write_text(json.dumps({'algorithm': 'MP', 'load_sha256': normalized_hash(load),
                                           'decoded': [{'kind': 1, 'kernel': 22}]}), encoding='utf-8')
            payload = json.loads((after / 'summary.json').read_text())
            payload['cases'][0]['package_sha256'] = hashlib.sha256(package.read_bytes()).hexdigest()
            (after / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'outside explicit'):
                subject.pair_panel_schedule(before, after, 32, 'panel-schedule')

        with tempfile.TemporaryDirectory() as raw:
            before, after = self.pair(Path(raw), 32, 'schedule-before', 'schedule-after')
            payload = json.loads((after / 'summary.json').read_text())
            payload['config']['inner_limit'] = 25
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'inner_limit'):
                subject.pair_panel_schedule(before, after, 32, 'panel-schedule')

        with tempfile.TemporaryDirectory() as raw:
            before, after = self.pair(Path(raw), 32, 'schedule-before', 'schedule-after')
            payload = json.loads((after / 'summary.json').read_text())
            payload['cases'][0]['factor_extend_calls'] = 1
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'factor_extend_calls disagrees'):
                subject.pair_panel_schedule(before, after, 32, 'panel-schedule')


    def factor_energy_pair(self, root, rows,
                           changed=('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP')):
        before, after = self.pair(root, rows, 'energy-before', 'energy-after', changed)
        before_payload = json.loads((before / 'summary.json').read_text())
        after_payload = json.loads((after / 'summary.json').read_text())
        before_payload['config']['factor_energy_tap'] = False
        after_payload['config']['factor_energy_tap'] = True
        self.write_summary_with_frozen_config(before, before_payload)
        self.write_summary_with_frozen_config(after, after_payload)
        return before, after

    def legacy_factor_energy_pair(self, root, rows, changed=('OMP',)):
        before, after = self.pair(root, rows, 'legacy-energy-before',
                                  'legacy-energy-after', changed)
        after_payload = json.loads((after / 'summary.json').read_text())
        after_payload['config']['factor_energy_tap'] = True
        self.write_summary_with_frozen_config(after, after_payload)
        self.write_frozen_kernel_interface(before, 9)
        return before, after

    def test_factor_energy_tap_is_qr_only_and_binds_same_physical_work(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_energy_pair(Path(raw), 32)
            result = subject.pair_factor_energy_tap(
                before, after, 32, 'factor-energy', set(subject.QR))
            self.assertEqual(result['allowance_kind'], 'factor-energy-tap')
            self.assertEqual(result['allowed_config_differences'], ['factor_energy_tap'])
            self.assertEqual(result['actual_changed_images'],
                             ['CoSaMP', 'GOMP', 'HTP', 'OMP', 'SP'])
            self.assertEqual(result['physical_qr_counts']['before'],
                             result['physical_qr_counts']['after'])
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_energy_pair(Path(raw), 32, ('GP',))
            with self.assertRaisesRegex(subject.ValidationError, 'non-QR'):
                subject.pair_factor_energy_tap(before, after, 32,
                                               'factor-energy', {'GP'})

    def test_factor_energy_tap_rejects_image_config_quality_and_output_changes(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_energy_pair(Path(raw), 32, ('MP',))
            with self.assertRaisesRegex(subject.ValidationError, 'outside explicit'):
                subject.pair_factor_energy_tap(before, after, 32,
                                               'factor-energy', set(subject.QR))
        for name, mutate, expected in (
                ('config', lambda payload: payload['config'].__setitem__('inner_limit', 25),
                 'inner_limit'),
                ('quality', lambda payload: payload['cases'][0]['quality']['fixed'].__setitem__('snr_db', 29.0),
                 'changed raw quality'),
                ('output', lambda payload: payload['cases'][0].__setitem__('output_raw_x_sha256', HASH_B),
                 'mathematical evidence')):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as raw:
                before, after = self.factor_energy_pair(Path(raw), 32, ('OMP',))
                payload = json.loads((after / 'summary.json').read_text())
                mutate(payload)
                self.write_summary_with_frozen_config(after, payload)
                with self.assertRaisesRegex(subject.ValidationError, expected):
                    subject.pair_factor_energy_tap(before, after, 32,
                                                   'factor-energy', {'OMP'})

    def test_factor_energy_tap_rejects_source_and_physical_work_changes(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_energy_pair(Path(raw), 32, ('OMP',))
            (after / 'source_snapshot' / 'rtl' / 'v4' / 'example.sv').write_text(
                'tampered\n', encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'source_snapshot digest mismatch'):
                subject.pair_factor_energy_tap(before, after, 32,
                                               'factor-energy', {'OMP'})
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.factor_energy_pair(Path(raw), 32, ('OMP',))
            payload = json.loads((after / 'summary.json').read_text())
            target = payload['cases'][subject.ACTIVE.index('OMP')]
            target['factor_init_calls'] = 2
            target['cycle_profile']['service_totals']['KERNEL:13']['calls'] = 2
            self.write_summary_with_frozen_config(after, payload)
            with self.assertRaisesRegex(subject.ValidationError, 'changed physical QR work'):
                subject.pair_factor_energy_tap(before, after, 32,
                                               'factor-energy', {'OMP'})

    def test_factor_energy_tap_legacy_baseline_is_opt_in_and_revision_bounded(self):
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.legacy_factor_energy_pair(Path(raw), 32)
            with self.assertRaisesRegex(subject.ValidationError, 'explicit false→true'):
                subject.pair_factor_energy_tap(before, after, 32,
                                               'factor-energy', {'OMP'})
            result = subject.pair_factor_energy_tap(
                before, after, 32, 'factor-energy', {'OMP'}, allow_legacy_baseline=True)
            self.assertEqual(result['legacy_pre_factor_energy_tap_baseline'],
                             {'kernel_revision': 9, 'packages_checked': 10})
        with tempfile.TemporaryDirectory() as raw:
            before, after = self.legacy_factor_energy_pair(Path(raw), 32)
            self.write_frozen_kernel_interface(before, 10)
            with self.assertRaisesRegex(subject.ValidationError, 'revision <= 9'):
                subject.pair_factor_energy_tap(
                    before, after, 32, 'factor-energy', {'OMP'}, allow_legacy_baseline=True)


if __name__ == '__main__':
    unittest.main()
