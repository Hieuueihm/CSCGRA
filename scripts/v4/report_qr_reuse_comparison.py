"""Fail-closed fixed-eight comparison for the command-local support reuse gate."""
import argparse
import hashlib
import json
from pathlib import Path


ACTIVE = ('MP', 'GP', 'IHT', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP', 'FISTA', 'PDHG')
IMAGE_CHANGE = {'OMP', 'GOMP'}
IDENTITY = (
    'rows', 'columns', 'requested_sparsity', 'requested_outer_iterations',
    'outer_iterations', 'raw_phi_sha256', 'raw_y_sha256',
    'output_raw_x_sha256', 'output_raw_r_sha256', 'status',
    'accepted_support', 'inner_iterations', 'fixed_numeric_events',
    'fixed_model_trace', 'fixed_solver_trace', 'solver_invocations',
    'solver_solve_count', 'solver_refinement_count', 'maximum_ls_support',
    'total_committed_inner_iterations',
)
COUNTERS = ('KERNEL:13', 'KERNEL:19')


class ValidationError(ValueError):
    """The evidence is incomplete or does not describe a fair pair."""


def file_sha256(path):
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


def require_clean(summary, label):
    if summary.get('status') != 'PASS':
        raise ValidationError(f'{label}: status must be PASS')
    if summary.get('changed_sources') != []:
        raise ValidationError(f'{label}: changed_sources must be an explicit empty list')
    if summary.get('untracked_imports') != []:
        raise ValidationError(f'{label}: untracked_imports must be an explicit empty list')
    if not (summary.get('source_sha256') or summary.get('source_manifests')):
        raise ValidationError(f'{label}: missing source provenance')


def load_digest(case, label, archive_root=None):
    value = case.get('load_image_sha256', case.get('load_sha256'))
    if archive_root is None:
        if not isinstance(value, str) or len(value) != 64:
            raise ValidationError(f'{label}: missing executable load digest')
        return value
    package_sha = case.get('package_sha256')
    if not isinstance(package_sha, str) or len(package_sha) != 64:
        raise ValidationError(f'{label}: missing package hash for archived image lookup')
    matches = [p for p in Path(archive_root).rglob('package.json') if file_sha256(p) == package_sha]
    if len(matches) != 1:
        raise ValidationError(f'{label}: package artifact match count {len(matches)}')
    package = json.loads(matches[0].read_text(encoding='utf-8'))
    if package.get('algorithm') != case.get('algorithm'):
        raise ValidationError(f'{label}: archived package algorithm mismatch')
    load_path = matches[0].with_name('load.txt')
    if not load_path.is_file():
        raise ValidationError(f'{label}: archived package lacks load.txt')
    actual = hashlib.sha256(load_path.read_text(encoding='utf-8').replace('\r\n', '\n').encode('utf-8')).hexdigest()
    if package.get('load_sha256') != actual:
        raise ValidationError(f'{label}: package load digest does not match load.txt')
    if value is not None and value != actual:
        raise ValidationError(f'{label}: summary load digest disagrees with artifact')
    return actual


def service_intervals(case):
    totals = case.get('cycle_profile', {}).get('service_totals')
    if not isinstance(totals, dict):
        raise ValidationError(f"{case.get('algorithm')}: missing cycle-profile service totals")
    out = {}
    for name, total in totals.items():
        if not isinstance(total, dict):
            raise ValidationError(f"{case.get('algorithm')}: invalid service total {name}")
        calls, clocks, frames = total.get('calls'), total.get('clocks'), total.get('accepted_frames')
        if not isinstance(calls, int) or not isinstance(clocks, int) or not isinstance(frames, int):
            raise ValidationError(f"{case.get('algorithm')}: incomplete interval total {name}")
        out[name] = {'calls': calls, 'clocks': clocks, 'accepted_frames': frames}
    return out


def kernel_counter(intervals, name):
    value = intervals.get(name)
    if value is None:
        # Profiles only emit executed service kinds. Preserve that provenance
        # instead of treating an omitted key as independently observed zero.
        return {'observed': False, 'calls': 0, 'clocks': 0, 'accepted_frames': 0}
    return {'observed': True, **value}


def cases(summary, label, rows, archive_root=None):
    require_clean(summary, label)
    config = summary.get('config', {})
    if config.get('rows') != rows or config.get('sparsity') != 8 or config.get('outer') != 8:
        raise ValidationError(f'{label}: expected M{rows}/K8/fixed outer8 configuration')
    columns = 64 if rows == 32 else 256
    found = {}
    for case in summary.get('cases', []):
        algorithm = case.get('algorithm')
        if algorithm in found or algorithm not in ACTIVE:
            raise ValidationError(f'{label}: invalid active algorithm {algorithm!r}')
        missing = [field for field in IDENTITY if field not in case]
        if missing:
            raise ValidationError(f'{label}/{algorithm}: missing fairness fields {missing}')
        if (case['rows'] != rows or case['columns'] != columns or
                case['requested_sparsity'] not in (8, None) or
                len(case.get('planted_support', [])) != 8 or
                case['requested_outer_iterations'] != 8 or case['outer_iterations'] != 8):
            raise ValidationError(f'{label}/{algorithm}: geometry, K, or actual outer mismatch')
        # The fixed-eight suite accepts documented terminal model statuses such
        # as max_iterations; summary PASS plus returncode zero is the gate.
        # The status itself is an identity field and must match its paired run.
        if not isinstance(case.get('status'), str) or case.get('returncode') != 0:
            raise ValidationError(f'{label}/{algorithm}: missing accepted execution status or nonzero return code')
        if not isinstance(case.get('job_cycles'), int) or case['job_cycles'] <= 0:
            raise ValidationError(f'{label}/{algorithm}: invalid job cycles')
        quality = case.get('quality')
        if not isinstance(quality, dict) or not isinstance(quality.get('fixed', {}).get('snr_db'), (int, float)):
            raise ValidationError(f'{label}/{algorithm}: incomplete raw quality evidence')
        case['_load_digest'] = load_digest(case, f'{label}/{algorithm}', archive_root)
        case['_intervals'] = service_intervals(case)
        found[algorithm] = case
    missing = sorted(set(ACTIVE) - set(found))
    if missing:
        raise ValidationError(f'{label}: missing active cases {missing}')
    return found


def compare(before, after, rows, algorithm, before_root=None, after_root=None):
    changed = [field for field in IDENTITY if before[field] != after[field]]
    if changed:
        raise ValidationError(f'M{rows}/{algorithm}: changed mathematical evidence {changed}')
    if before.get('policy') != after.get('policy'):
        raise ValidationError(f'M{rows}/{algorithm}: changed policy')
    if before.get('quality') != after.get('quality'):
        raise ValidationError(f'M{rows}/{algorithm}: changed raw quality evidence')
    old_load = load_digest(before, f'M{rows}/{algorithm}/before', before_root)
    new_load = load_digest(after, f'M{rows}/{algorithm}/after', after_root)
    image_changed = old_load != new_load
    if image_changed and algorithm not in IMAGE_CHANGE:
        raise ValidationError(f'M{rows}/{algorithm}: executable image changed outside OMP/GOMP allowance')
    old_intervals, new_intervals = before['_intervals'], after['_intervals']
    if algorithm not in IMAGE_CHANGE:
        changed_factor = [name for name in COUNTERS
                          if kernel_counter(old_intervals, name) != kernel_counter(new_intervals, name)]
        if changed_factor:
            raise ValidationError(f'M{rows}/{algorithm}: FACTOR_INIT/EXTEND changed outside OMP/GOMP allowance')
    interval_names = sorted(set(old_intervals) | set(new_intervals))
    return {
        'algorithm': algorithm,
        'before_job_cycles': before['job_cycles'],
        'after_job_cycles': after['job_cycles'],
        'reduction_percent': (before['job_cycles'] - after['job_cycles']) * 100 / before['job_cycles'],
        'actual_outer_iterations': 8,
        'quality': after['quality'],
        'logical_ls': {
            key: after[key] for key in ('solver_invocations', 'solver_solve_count',
                                         'solver_refinement_count', 'maximum_ls_support',
                                         'total_committed_inner_iterations')
        },
        'corrections': after['solver_refinement_count'],
        'numeric_events': after['fixed_numeric_events'],
        'retired_instructions': {'before': before.get('retired_instructions'), 'after': after.get('retired_instructions')},
        'kernel_counts': {name: {'before': kernel_counter(old_intervals, name),
                                 'after': kernel_counter(new_intervals, name)} for name in COUNTERS},
        'service_intervals': {name: {'before': old_intervals.get(name, {'calls': 0, 'clocks': 0, 'accepted_frames': 0}),
                                     'after': new_intervals.get(name, {'calls': 0, 'clocks': 0, 'accepted_frames': 0})}
                              for name in interval_names},
        'load_image_before': old_load,
        'load_image_after': new_load,
        'program_image_changed': image_changed,
    }


def geometry(before_path, after_path, rows):
    before_file, before_summary = read_summary(before_path)
    after_file, after_summary = read_summary(after_path)
    before = cases(before_summary, f'baseline M{rows}', rows, before_file.parent)
    after = cases(after_summary, f'candidate M{rows}', rows, after_file.parent)
    return {
        'rows': rows,
        'columns': 64 if rows == 32 else 256,
        'baseline_summary_sha256': file_sha256(before_file),
        'candidate_summary_sha256': file_sha256(after_file),
        'rows_output': [compare(before[algorithm], after[algorithm], rows, algorithm,
                                before_file.parent, after_file.parent)
                        for algorithm in ACTIVE],
        'reference_admm': {
            'algorithm': 'ADMM',
            'scope': 'historical reference-only; excluded from active10 reuse execution',
            'candidate_execution': 'not requested',
            'comparison': None,
        },
    }


def render(result):
    lines = [
        '# Cập nhật QR và tái sử dụng dữ liệu (K=8, outer thực tế=8)', '',
        'Phạm vi là M=32,N=64,K=8 và M=64,N=256,K=8, fixed eight outer iterations. '
        'Validator đối chiếu Phi/Y thô, X/R, support, status, policy, logical LS/correction, '
        'numeric event và raw quality trước khi tính cycle. Đây là đo cycle fixed8; không phải '
        'xác nhận chất lượng held-out ứng dụng hoặc ngưỡng 20 dB.', '',
        'Chỉ OMP và GOMP được phép thay executable image cho INIT→EXTEND. Các ảnh chương trình '
        'active khác phải giống nhau. ADMM là hàng tham chiếu lịch sử, không được chạy lại trong active10.', '',
        'Compiler giữ RU_S/RU_T/RU_QTY persistent kích thước O(2S+M) trong vector pool hiện có; '
        'không tạo factor copy. Phần cứng mới giới hạn ở hai block operand đã xác thực trong một lệnh '
        'và 32 winner records TOPK; không có PE, multiplier, bản sao vector đầy đủ, hay tuyên bố '
        'timing/tài nguyên/synthesis.', '',
        '## Microgate support transport', '',
        'Gate Vivado xsim nguồn-ràng-buộc gồm 107 ca (`TOPK` 22, `SLICE` 38, `REPLACE_RANGE` 47), '
        'bao gồm tail tới length/K=1024, alias, held payload, tag/mask/fault và cancel. Xem '
        '[qualification manifest](../qr_reuse_rtl_20260909/qualification.json) để kiểm source snapshot và kết quả gốc.', '',
        '| Lệnh micro M=128 | Cycle baseline | Reads baseline | Cycle candidate | Reads candidate | Quyết định |',
        '|---|---:|---:|---:|---:|---|',
        '| SLICE start=1, output=32 | 33 | 2 | 33 | 2 | bypass nhỏ; giữ lịch cũ |',
        '| SLICE start=32, output=65 | 46 | 3 | 46 | 3 | bypass aligned; giữ lịch cũ |',
        '| SLICE start=1, output=65 | 53 | 5 | 53 | 3 | cache command-local giảm hai reads, không giảm cycle micro này |', '',
        '| TOPK micro | Cycle baseline | Reads baseline | Cycle candidate | Reads candidate | Quyết định |',
        '|---|---:|---:|---:|---:|---|',
        '| N=64, K=1 | 45 | 2 | 45 | 2 | legacy k=1 |',
        '| N=64, K=2 | 70 | 4 | 70 | 4 | legacy break-even |',
        '| N=64, K=3 | 94 | 6 | 92 | 4 | winner cache |',
        '| N=256, K=2 | 199 | 16 | 141 | 9 | winner cache |', '',
        'Bảng micro chỉ là đo lá service; không suy ra giảm cycle chương trình hay thời gian nhàn rỗi. '
        'Bảng whole-program bên dưới dùng cặp archive source-bound riêng.', ''
    ]
    for geometry_result in result['geometries']:
        lines += [f"## M={geometry_result['rows']}, N={geometry_result['columns']}", '',
                  '| Thuật toán | Cycle trước | Cycle sau | Giảm % | outer | Retired trước→sau | INIT calls trước→sau | EXTEND calls trước→sau | Ảnh đổi |',
                  '|---|---:|---:|---:|---:|---:|---:|---:|---|']
        for row in geometry_result['rows_output']:
            init = row['kernel_counts']['KERNEL:13']
            extend = row['kernel_counts']['KERNEL:19']
            retired = row['retired_instructions']
            count = lambda value: str(value['calls']) if value['observed'] else 'không ghi'
            lines.append(
                f"| {row['algorithm']} | {row['before_job_cycles']} | {row['after_job_cycles']} | "
                f"{row['reduction_percent']:.2f} | {row['actual_outer_iterations']} | "
                f"{retired['before']}→{retired['after']} | {count(init['before'])}→{count(init['after'])} | "
                f"{count(extend['before'])}→{count(extend['after'])} | {'có' if row['program_image_changed'] else 'không'} |"
            )
        lines += ['', '### Khoảng dịch vụ đã đo', '',
                  'Các số dưới đây là tổng calls/clocks/accepted frames do profiler báo cáo. '
                  'Chênh lệch không được suy luận là idle hoặc một lớp pipeline chưa được đo.', '']
        for row in geometry_result['rows_output']:
            changed = [(name, values) for name, values in row['service_intervals'].items()
                       if values['before'] != values['after']]
            if changed:
                values = '; '.join(
                    f"{name}: {entry['before']['calls']}/{entry['before']['clocks']}/{entry['before']['accepted_frames']}→"
                    f"{entry['after']['calls']}/{entry['after']['clocks']}/{entry['after']['accepted_frames']}"
                    for name, entry in changed)
                lines.append(f"- **{row['algorithm']}**: {values}")
        lines += ['', '### Quality và solver', '',
                  '| Thuật toán | Fixed SNR dB | Float SNR dB | NMSE ratio | LS solves/refines | Max S | Numeric events |',
                  '|---|---:|---:|---:|---:|---:|---:|']
        for row in geometry_result['rows_output']:
            quality = row['quality']
            fixed = quality.get('fixed', {}).get('snr_db')
            floating = quality.get('floating', {}).get('snr_db')
            ratio = quality.get('nmse_ratio')
            ls = row['logical_ls']
            lines.append(f"| {row['algorithm']} | {fixed:.6g} | {floating:.6g} | {ratio:.6g} | "
                         f"{ls['solver_solve_count']}/{ls['solver_refinement_count']} | "
                         f"{ls['maximum_ls_support']} | {row['numeric_events']} |")
        admm = geometry_result['reference_admm']
        lines += ['', '| Thuật toán | Phạm vi | Kết quả candidate |', '|---|---|---|',
                  f"| {admm['algorithm']} | {admm['scope']} | Không chạy lại trong active10; không dùng để kết luận performance round này. |", '']
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-m32', required=True)
    parser.add_argument('--candidate-m32', required=True)
    parser.add_argument('--baseline-m64', required=True)
    parser.add_argument('--candidate-m64', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args(argv)
    output = Path(args.output)
    if output.exists():
        raise ValidationError(f'output exists: {output}')
    result = {
        'schema': 1,
        'status': 'PASS',
        'scope': 'source-bound active10 fixed K8/actual outer8; ADMM historical reference-only',
        'geometries': [geometry(args.baseline_m32, args.candidate_m32, 32),
                       geometry(args.baseline_m64, args.candidate_m64, 64)],
    }
    output.mkdir(parents=True)
    (output / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    (output / 'qr_reuse_comparison_vi.md').write_text(render(result), encoding='utf-8')


if __name__ == '__main__':
    main()
