import copy
import json
import tempfile
import unittest
from pathlib import Path

from scripts.v4 import report_qr_reuse_comparison as subject


ACTIVE = subject.ACTIVE
HASH_A = 'a' * 64
HASH_B = 'b' * 64


def case(algorithm, rows, image=HASH_A):
    columns = 64 if rows == 32 else 256
    profile = {
        'KERNEL:13': {'calls': 8 if algorithm in {'OMP', 'GOMP'} else 0, 'clocks': 80, 'accepted_frames': 0},
        'KERNEL:19': {'calls': 0, 'clocks': 0, 'accepted_frames': 0},
        'SUPPORT:TOPK': {'calls': 8, 'clocks': 64, 'accepted_frames': 16},
    }
    return {
        'algorithm': algorithm, 'rows': rows, 'columns': columns, 'requested_sparsity': 8,
        'requested_outer_iterations': 8, 'outer_iterations': 8, 'planted_support': list(range(8)),
        'raw_phi_sha256': HASH_A, 'raw_y_sha256': HASH_B, 'output_raw_x_sha256': HASH_A,
        'output_raw_r_sha256': HASH_B, 'status': 'PASS', 'returncode': 0, 'accepted_support': list(range(8)),
        'inner_iterations': 0, 'fixed_numeric_events': 0, 'fixed_model_trace': HASH_A,
        'fixed_solver_trace': HASH_B, 'solver_invocations': 0, 'solver_solve_count': 0,
        'solver_refinement_count': 0, 'maximum_ls_support': 0,
        'total_committed_inner_iterations': 0, 'policy': {'name': 'fixed8'}, 'job_cycles': 1000,
        'quality': {'fixed': {'snr_db': 7.0}, 'floating': {'snr_db': 7.0}, 'nmse_ratio': 1.0},
        'load_image_sha256': image, 'retired_instructions': 50,
        'cycle_profile': {'service_totals': profile},
    }


def summary(rows, cases):
    return {'status': 'PASS', 'changed_sources': [], 'untracked_imports': [], 'source_sha256': HASH_A,
            'config': {'rows': rows, 'sparsity': 8, 'outer': 8}, 'cases': cases}


class QrReuseComparisonTests(unittest.TestCase):
    def write(self, root, name, payload):
        directory = root / name
        directory.mkdir()
        for item in payload['cases']:
            artifact = directory / 'artifacts' / item['algorithm']
            artifact.mkdir(parents=True)
            load = f"{item['algorithm']}:{item['load_image_sha256']}\n"
            load_path = artifact / 'load.txt'
            load_path.write_text(load, encoding='utf-8')
            digest = __import__('hashlib').sha256(load.encode('utf-8')).hexdigest()
            package = {'algorithm': item['algorithm'], 'load_sha256': digest}
            package_path = artifact / 'package.json'
            package_path.write_text(json.dumps(package), encoding='utf-8')
            item['load_image_sha256'] = digest
            item['package_sha256'] = __import__('hashlib').sha256(package_path.read_bytes()).hexdigest()
        (directory / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
        return directory

    def pair(self, root, rows, nonallowed_image_change=False):
        before = [case(a, rows) for a in reversed(ACTIVE)]
        # fixed-eight reports accept this documented terminal state; it remains
        # a strict identity field rather than being rewritten to PASS.
        before[0]['status'] = 'max_iterations'
        after = copy.deepcopy(before)
        for item in after:
            item['job_cycles'] = 900
        for item in after:
            if item['algorithm'] in {'OMP', 'GOMP'}:
                item['load_image_sha256'] = HASH_B
                item['cycle_profile']['service_totals']['KERNEL:13']['calls'] = 0
                item['cycle_profile']['service_totals']['KERNEL:19'] = {'calls': 8, 'clocks': 40, 'accepted_frames': 0}
            if nonallowed_image_change and item['algorithm'] == 'MP':
                item['load_image_sha256'] = HASH_B
        return self.write(root, f'before{rows}', summary(rows, before)), self.write(root, f'after{rows}', summary(rows, after))

    def render_report(self, root, before32, after32, before64, after64):
        output = root / 'out'
        subject.main(['--baseline-m32', str(before32), '--candidate-m32', str(after32),
                      '--baseline-m64', str(before64), '--candidate-m64', str(after64), '--output', str(output)])
        return output

    def test_accepts_unordered_active_pairs_and_renders_reference_admm(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before32, after32 = self.pair(root, 32)
            before64, after64 = self.pair(root, 64)
            output = self.render_report(root, before32, after32, before64, after64)
            result = json.loads((output / 'comparison.json').read_text())
            self.assertEqual(result['status'], 'PASS')
            self.assertEqual([r['algorithm'] for r in result['geometries'][0]['rows_output']], list(ACTIVE))
            self.assertEqual(result['geometries'][0]['reference_admm']['candidate_execution'], 'not requested')
            report = (output / 'qr_reuse_comparison_vi.md').read_text()
            self.assertIn('ADMM', report)
            self.assertIn('KERNEL:19', report)
            self.assertIn('Cập nhật QR và tái sử dụng dữ liệu', report)
            self.assertIn('RU_S/RU_T/RU_QTY', report)
            self.assertIn('| N=256, K=2 | 199 | 16 | 141 | 9 |', report)

    def test_rejects_changed_raw_output_or_quality(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before32, after32 = self.pair(root, 32)
            before64, after64 = self.pair(root, 64)
            payload = json.loads((after32 / 'summary.json').read_text())
            payload['cases'][0]['output_raw_x_sha256'] = HASH_B
            (after32 / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'mathematical evidence'):
                self.render_report(root, before32, after32, before64, after64)

    def test_rejects_non_omp_gomp_program_image_change(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before32, after32 = self.pair(root, 32, nonallowed_image_change=True)
            before64, after64 = self.pair(root, 64)
            with self.assertRaisesRegex(subject.ValidationError, 'outside OMP/GOMP'):
                self.render_report(root, before32, after32, before64, after64)

    def test_rejects_non_omp_gomp_factor_counter_change(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before32, after32 = self.pair(root, 32)
            before64, after64 = self.pair(root, 64)
            payload = json.loads((after32 / 'summary.json').read_text())
            mp = next(item for item in payload['cases'] if item['algorithm'] == 'MP')
            mp['cycle_profile']['service_totals']['KERNEL:19'] = {'calls': 1, 'clocks': 9, 'accepted_frames': 0}
            (after32 / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'FACTOR_INIT/EXTEND'):
                self.render_report(root, before32, after32, before64, after64)

    def test_rejects_missing_source_closure_and_actual_outer(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            before32, after32 = self.pair(root, 32)
            before64, after64 = self.pair(root, 64)
            payload = json.loads((after64 / 'summary.json').read_text())
            payload['untracked_imports'] = None
            (after64 / 'summary.json').write_text(json.dumps(payload), encoding='utf-8')
            with self.assertRaisesRegex(subject.ValidationError, 'untracked_imports'):
                self.render_report(root, before32, after32, before64, after64)


if __name__ == '__main__':
    unittest.main()
