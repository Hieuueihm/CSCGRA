"""Rejection coverage for strict round-two comparison evidence."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from scripts.v4 import report_round2_comparison as report


def summary(rows):
    cases = []
    for index, algorithm in enumerate(report.ALL_ALGORITHMS):
        cases.append(dict(
            algorithm=algorithm, rows=rows, columns=256 if rows == 64 else 64, requested_sparsity=8, planted_support=list(range(8)),
            requested_outer_iterations=8, outer_iterations=8, raw_phi_sha256=f'phi-{rows}',
            raw_y_sha256=f'y-{rows}', policy={'max_iterations': 8},
            output_raw_x_sha256=f'x-{algorithm}', output_raw_r_sha256=f'r-{algorithm}',
            status='max_iterations', accepted_support=[index], inner_iterations=0,
            fixed_numeric_events={'saturation': 0}, package_sha256=f'package-{algorithm}',
            fixed_model_trace=[], fixed_solver_trace=[], floating_model_trace=[],
            solver_invocations=8 if algorithm == 'HTP' else 0,
            solver_solve_count=8 if algorithm == 'HTP' else 0,
            solver_refinement_count=0, maximum_ls_support=8 if algorithm == 'HTP' else 0,
            total_committed_inner_iterations=86 if algorithm == 'ADMM' else 0, job_cycles=100 + index,
            quality={'fixed': {'snr_db': 25.0}, 'floating': {'snr_db': 25.0}, 'nmse_ratio': 1.0, 'snr_loss_db': 0.0},
            cycle_profile={'service_totals': {'KERNEL:13': {'calls': 1 if algorithm == 'HTP' else 0}}}, program_length=1, template_count=1, load_record_count=1,
        ))
    return dict(status='PASS', changed_sources=[], untracked_imports=[], source_sha256={'tool': 'hash'},
                config={'rows': rows, 'columns': 256 if rows == 64 else 64, 'sparsity': 8, 'outer': 8}, cases=cases)


class RoundTwoComparisonTests(unittest.TestCase):
    def write(self, directory, name, value):
        path = Path(directory) / name
        path.write_text(json.dumps(value))
        return path

    def test_self_comparison_is_zero_percent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write(directory, 'm32.json', summary(32))
            result = report.compare_geometry(path, path, 32)
            self.assertEqual(len(result['rows_output']), 10)
            self.assertTrue(all(row['reduction_percent'] == 0 for row in result['rows_output']))
            htp = next(row for row in result['rows_output'] if row['algorithm'] == 'HTP')
            admm = result['reference_admm']
            self.assertEqual((htp['factor_calls'], htp['ls_solves'], htp['total_cg']), (1, 8, 0))
            self.assertEqual((admm['factor_calls'], admm['ls_solves'], admm['total_cg']), (0, 0, 86))

    def test_active_ten_without_admm_is_valid_but_unpaired_reference_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            active = summary(32)
            active['cases'].pop()
            baseline = self.write(directory, 'active.json', active)
            result = report.compare_geometry(baseline, baseline, 32)
            self.assertEqual([row['algorithm'] for row in result['rows_output']], list(report.ACTIVE_ALGORITHMS))
            self.assertIsNone(result['reference_admm'])
            paired = self.write(directory, 'paired.json', summary(32))
            with self.assertRaises(report.ValidationError):
                report.compare_geometry(baseline, paired, 32)

    def test_markdown_states_geometry_cycle_scope_and_skipped_admm_quality(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write(directory, 'm32.json', summary(32))
            geometry = report.compare_geometry(path, path, 32)
            text = report.render_markdown({'geometries': [geometry], 'quality_admm64': None})
            self.assertIn('M=32, N=64, K=8', text)
            self.assertIn('M=64, N=256, K=8', text)
            self.assertIn('so sánh chu kỳ fixed8', text)
            self.assertIn('không trở thành đạt ngưỡng 20 dB', text)
            self.assertIn('không được chạy trong báo cáo này', text)
            self.assertIn('quality_admm64_m64_20260909', text)

    def test_rejects_outer_hash_status_and_missing_case(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline = summary(32)
            baseline_path = self.write(directory, 'baseline.json', baseline)
            for name, mutate in (
                ('outer', lambda value: value['cases'][0].update(outer_iterations=7)),
                ('hash', lambda value: value['cases'][0].update(raw_y_sha256='other')),
                ('status', lambda value: value['cases'][0].update(status='residual_tolerance')),
                ('missing', lambda value: value['cases'].pop(0)),
            ):
                candidate = copy.deepcopy(baseline)
                mutate(candidate)
                path = self.write(directory, name + '.json', candidate)
                with self.subTest(name=name), self.assertRaises(report.ValidationError):
                    report.compare_geometry(baseline_path, path, 32)

    def test_separate_admm64_quality_outer64_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline = summary(64)
            baseline['config']['outer'] = 64
            baseline['cases'] = [next(case for case in baseline['cases'] if case['algorithm'] == 'ADMM')]
            baseline['cases'][0]['requested_outer_iterations'] = 64
            baseline['cases'][0]['outer_iterations'] = 64
            baseline['cases'][0]['policy'] = {'max_iterations': 64}
            baseline_path = self.write(directory, 'baseline_admm.json', baseline)
            candidate_path = self.write(directory, 'candidate_admm.json', copy.deepcopy(baseline))
            self.assertEqual(report.validate_admm_quality(baseline_path, candidate_path)['status'], 'PASS')
            altered = copy.deepcopy(baseline)
            altered['cases'][0]['quality']['floating']['snr_db'] = 25.001
            altered_path = self.write(directory, 'altered_admm.json', altered)
            with self.assertRaises(report.ValidationError):
                report.validate_admm_quality(baseline_path, altered_path)


if __name__ == '__main__':
    unittest.main()
