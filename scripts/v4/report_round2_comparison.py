"""Strict, source-clean round-two K=8 cycle comparison report.

The tool accepts completed M32/M64 archives only.  It rejects a candidate
whose numerical identity, program package, fixed iteration envelope, source
cleanliness, or algorithm coverage differs from its matching baseline.
"""
import argparse
import hashlib
import json
from pathlib import Path


ALL_ALGORITHMS = ('MP', 'GP', 'IHT', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP',
                  'FISTA', 'PDHG', 'ADMM')
REFERENCE_ALGORITHM = 'ADMM'
ACTIVE_ALGORITHMS = tuple(algorithm for algorithm in ALL_ALGORITHMS
                          if algorithm != REFERENCE_ALGORITHM)
QR_ALGORITHMS = {'OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'}
IDENTITY_FIELDS = (
    'rows', 'columns', 'requested_sparsity', 'requested_outer_iterations',
    'outer_iterations', 'raw_phi_sha256', 'raw_y_sha256', 'policy',
    'output_raw_x_sha256', 'output_raw_r_sha256', 'status',
    'accepted_support', 'inner_iterations', 'fixed_numeric_events',
    'package_sha256', 'fixed_model_trace', 'fixed_solver_trace',
    'solver_invocations', 'solver_solve_count', 'solver_refinement_count',
    'maximum_ls_support', 'total_committed_inner_iterations',
)
QUALITY_IDENTITY_FIELDS = (
    'rows', 'columns', 'requested_sparsity', 'requested_outer_iterations',
    'outer_iterations', 'raw_phi_sha256', 'raw_y_sha256', 'policy',
    'output_raw_x_sha256', 'output_raw_r_sha256', 'status',
    'accepted_support', 'inner_iterations', 'fixed_numeric_events',
    'package_sha256', 'fixed_model_trace', 'fixed_solver_trace',
)
REQUIRED_CASE_FIELDS = set(IDENTITY_FIELDS) | {
    'algorithm', 'job_cycles', 'quality', 'cycle_profile',
    'program_length', 'template_count', 'load_record_count', 'planted_support',
}


class ValidationError(ValueError):
    """An archive cannot support a fair comparison."""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_summary(path):
    path = Path(path)
    if path.is_dir():
        path = path / 'summary.json'
    if not path.is_file():
        raise ValidationError(f'missing summary: {path}')
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValidationError(f'invalid JSON {path}: {error}') from error
    return path.resolve(), value


def require_clean(summary, label):
    if summary.get('status') != 'PASS':
        raise ValidationError(f'{label}: summary status is not PASS')
    for key in ('changed_sources', 'untracked_imports'):
        value = summary.get(key)
        if value != []:
            raise ValidationError(f'{label}: {key} must be an empty list')
    if not (summary.get('source_sha256') or summary.get('source_manifests')):
        raise ValidationError(f'{label}: missing source-clean provenance')


def cases_by_algorithm(summary, label, rows):
    require_clean(summary, label)
    config = summary.get('config')
    if not isinstance(config, dict):
        raise ValidationError(f'{label}: missing config')
    if config.get('rows') != rows or config.get('sparsity') != 8 or config.get('outer') != 8:
        raise ValidationError(f'{label}: expected M{rows}, K8, outer8 config')
    cases = summary.get('cases')
    if not isinstance(cases, list) or len(cases) not in (len(ACTIVE_ALGORITHMS), len(ALL_ALGORITHMS)):
        raise ValidationError(f'{label}: requires ten active cases, optionally paired with ADMM reference')
    result = {}
    for case in cases:
        if not isinstance(case, dict):
            raise ValidationError(f'{label}: non-object case')
        algorithm = case.get('algorithm')
        if algorithm not in ALL_ALGORITHMS or algorithm in result:
            raise ValidationError(f'{label}: invalid or duplicate algorithm {algorithm!r}')
        missing = sorted(REQUIRED_CASE_FIELDS - set(case))
        if missing:
            raise ValidationError(f'{label}/{algorithm}: missing required evidence {missing}')
        # Proximal policies have no requested_sparsity field, but every
        # fixture still uses the common planted K=8 signal.
        if (case['rows'] != rows or case['requested_sparsity'] not in (8, None)
                or len(case['planted_support']) != 8):
            raise ValidationError(f'{label}/{algorithm}: geometry or K mismatch')
        if case['requested_outer_iterations'] != 8 or case['outer_iterations'] != 8:
            raise ValidationError(f'{label}/{algorithm}: actual outer iteration count is not 8')
        if not isinstance(case['quality'].get('fixed', {}).get('snr_db'), (float, int)):
            raise ValidationError(f'{label}/{algorithm}: missing fixed SNR')
        if not isinstance(case['job_cycles'], int) or case['job_cycles'] <= 0:
            raise ValidationError(f'{label}/{algorithm}: invalid job_cycles')
        result[algorithm] = case
    expected = ALL_ALGORITHMS if len(cases) == len(ALL_ALGORITHMS) else ACTIVE_ALGORITHMS
    if tuple(result) != expected:
        raise ValidationError(f'{label}: algorithms must be canonical active ten, optionally followed by ADMM reference')
    return result


def physical_factor_calls(case):
    """Read actual FACTOR_INIT service calls, never model-level LS invocations."""
    totals = case['cycle_profile'].get('service_totals')
    if not isinstance(totals, dict):
        raise ValidationError(f"{case['algorithm']}: missing cycle_profile.service_totals")
    factor = totals.get('KERNEL:13')
    if case['algorithm'] in QR_ALGORITHMS and not isinstance(factor, dict):
        raise ValidationError(f"{case['algorithm']}: missing physical KERNEL:13 FACTOR_INIT counter")
    if factor is None:
        return 0
    calls = factor.get('calls')
    if not isinstance(calls, int) or calls < 0:
        raise ValidationError(f"{case['algorithm']}: invalid physical KERNEL:13 calls")
    return calls


def compare_case(before, after, rows, algorithm):
    """Require identity, then emit one same-geometry cycle comparison row."""
    mismatches = [field for field in IDENTITY_FIELDS if before[field] != after[field]]
    if mismatches:
        raise ValidationError(f'M{rows}/{algorithm}: changed identity evidence {mismatches}')
    if before['quality'] != after['quality']:
        raise ValidationError(f'M{rows}/{algorithm}: changed fixed/floating quality evidence')
    # New RTL is the only permitted scheduled-path delta.  These prove the
    # package and loaded shape did not change while retaining trace evidence.
    for field in ('program_length', 'template_count', 'load_record_count'):
        if before[field] != after[field]:
            raise ValidationError(f'M{rows}/{algorithm}: changed scheduled metadata {field}')
    old_factor, new_factor = physical_factor_calls(before), physical_factor_calls(after)
    if old_factor != new_factor:
        raise ValidationError(f'M{rows}/{algorithm}: changed physical FACTOR_INIT count')
    old_cycles, new_cycles = before['job_cycles'], after['job_cycles']
    return dict(
        geometry=dict(rows=before['rows'], columns=before['columns'], sparsity=8),
        algorithm=algorithm, old_job_cycles=old_cycles, new_job_cycles=new_cycles,
        reduction_percent=(old_cycles - new_cycles) * 100.0 / old_cycles,
        fixed_snr_db_before=before['quality']['fixed']['snr_db'],
        fixed_snr_db_after=after['quality']['fixed']['snr_db'], actual_outer=before['outer_iterations'],
        max_qr_support=before['maximum_ls_support'], factor_calls=old_factor,
        total_cg=before['total_committed_inner_iterations'],
        ls_solves=before['solver_solve_count'], ls_refinements=before['solver_refinement_count'],
        model_ls_invocations=before['solver_invocations'], inner_iterations=before['inner_iterations'],
        package_sha256=before['package_sha256'], raw_x_sha256=before['output_raw_x_sha256'],
        raw_r_sha256=before['output_raw_r_sha256'], status=before['status'],
    )


def compare_geometry(baseline_path, candidate_path, rows):
    baseline_path, baseline = read_summary(baseline_path)
    candidate_path, candidate = read_summary(candidate_path)
    old = cases_by_algorithm(baseline, f'baseline M{rows}', rows)
    new = cases_by_algorithm(candidate, f'candidate M{rows}', rows)
    if (REFERENCE_ALGORITHM in old) != (REFERENCE_ALGORITHM in new):
        raise ValidationError(f'M{rows}: ADMM reference must be present in both archives or neither')
    output = [compare_case(old[algorithm], new[algorithm], rows, algorithm)
              for algorithm in ACTIVE_ALGORITHMS]
    reference = (compare_case(old[REFERENCE_ALGORITHM], new[REFERENCE_ALGORITHM], rows, REFERENCE_ALGORITHM)
                 if REFERENCE_ALGORITHM in old else None)
    return dict(rows=rows, baseline=dict(path=str(baseline_path), sha256=digest(baseline_path)),
                candidate=dict(path=str(candidate_path), sha256=digest(candidate_path)), rows_output=output,
                reference_admm=reference)


def render_markdown(comparison):
    lines = [
        '# So sánh chu kỳ round 2 (fixed K=8, outer thực tế=8)', '',
        'Phạm vi hình học: M=32, N=64, K=8 và M=64, N=256, K=8. Cột `outer thực tế` phải bằng 8 trong từng hàng.', '',
        'Đây là so sánh chu kỳ fixed8, không phải xác nhận chất lượng ứng dụng. SNR thấp của MP/IHT/HTP/FISTA/PDHG không trở thành đạt ngưỡng 20 dB chỉ vì chất lượng trước/sau không đổi.', '',
        'Báo cáo chỉ so sánh cùng hình học và cùng đầu vào số nguyên. Mỗi hàng phải giữ nguyên Phi/Y, X/R, support, trạng thái, policy, package và chứng chỉ mô hình; nếu thiếu hoặc khác, công cụ dừng thay vì tạo tỷ lệ không công bằng.', '',
    ]
    for geometry in comparison['geometries']:
        rows = geometry['rows']
        lines += [f'## M={rows}', '',
                  f"Baseline: `{geometry['baseline']['path']}`", '',
                  f"Candidate: `{geometry['candidate']['path']}`", '',
                  '| Thuật toán | Chu kỳ cũ | Chu kỳ mới | Giảm % | SNR fixed cũ/mới (dB) | outer thực tế | QR support lớn nhất | FACTOR_INIT vật lý | Total CG | LS solves | LS refinement |',
                  '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
        for row in geometry['rows_output']:
            lines.append('| {algorithm} | {old_job_cycles} | {new_job_cycles} | {reduction_percent:.2f} | {fixed_snr_db_before:.3f}/{fixed_snr_db_after:.3f} | {actual_outer} | {max_qr_support} | {factor_calls} | {total_cg} | {ls_solves} | {ls_refinements} |'.format(**row))
        lines.append('')
        reference = geometry['reference_admm']
        if reference:
            lines += [
                '### ADMM tham chiếu (ngoài bảng 10 thuật toán active)', '',
                'ADMM được giữ làm bằng chứng tham chiếu đã ghép cặp; không thuộc tổng hợp tối ưu hóa active.', '',
                '| Thuật toán | Chu kỳ cũ | Chu kỳ mới | Giảm % | SNR fixed cũ/mới (dB) | outer thực tế | Total CG |',
                '|---|---:|---:|---:|---:|---:|---:|',
                '| {algorithm} | {old_job_cycles} | {new_job_cycles} | {reduction_percent:.2f} | {fixed_snr_db_before:.3f}/{fixed_snr_db_after:.3f} | {actual_outer} | {total_cg} |'.format(**reference),
                '',
            ]
    lines += [
        'Các số V2/V3 chỉ là liên kết lịch sử trong hồ sơ gốc; không có tỷ lệ chu kỳ chéo phiên bản trong báo cáo này vì hình học, input và ràng buộc thực thi không đồng nhất.',
        '',
    ]
    if comparison.get('quality_admm64') is None:
        lines += [
            'Kiểm tra chất lượng ADMM64 outer=64 không được chạy trong báo cáo này vì phạm vi round2 đã dừng ADMM. `quality_admm64_m64_20260909` chỉ là hồ sơ tham chiếu cũ, không phải kết quả mới.',
        ]
    else:
        lines += [
            'Kiểm tra chất lượng ADMM64 outer=64 đã được chạy trên cặp đầu vào riêng: Phi/Y, policy, X/R, trace, trạng thái và inner phải khớp; cả SNR fixed/float phải đạt ngưỡng đã yêu cầu.',
        ]
    return '\n'.join(lines) + '\n'


def admm_quality_case(path, label):
    summary_path, summary = read_summary(path)
    require_clean(summary, label)
    cases = summary.get('cases')
    if not isinstance(cases, list) or len(cases) != 1 or cases[0].get('algorithm') != 'ADMM':
        raise ValidationError(f'{label}: requires exactly one ADMM case')
    case = cases[0]
    required = set(QUALITY_IDENTITY_FIELDS) | {'quality', 'floating_model_trace', 'planted_support'}
    missing = sorted(required - set(case))
    if missing:
        raise ValidationError(f'{label}: missing ADMM quality evidence {missing}')
    if case['rows'] != 64 or case['columns'] != 256 or case['requested_outer_iterations'] != 64 or case['outer_iterations'] != 64:
        raise ValidationError(f'{label}: requires M64/N256/outer64')
    if len(case['planted_support']) != 8:
        raise ValidationError(f'{label}: requires planted K8')
    events = case['fixed_numeric_events']
    if not isinstance(events, dict) or any(events.values()):
        raise ValidationError(f'{label}: fixed numeric events must all be zero')
    quality = case['quality']
    fixed = quality.get('fixed', {})
    floating = quality.get('floating', {})
    if min(fixed.get('snr_db', float('-inf')), floating.get('snr_db', float('-inf'))) < 20.0:
        raise ValidationError(f'{label}: fixed and floating SNR must both be at least 20 dB')
    if quality.get('nmse_ratio') is None or quality['nmse_ratio'] > 1.1:
        raise ValidationError(f'{label}: NMSE ratio exceeds 1.1')
    if quality.get('snr_loss_db') is None or quality['snr_loss_db'] > 0.5:
        raise ValidationError(f'{label}: SNR loss exceeds 0.5 dB')
    return summary_path, case


def validate_admm_quality(baseline_path, candidate_path):
    baseline_summary, before = admm_quality_case(baseline_path, 'baseline ADMM64 quality')
    candidate_summary, after = admm_quality_case(candidate_path, 'candidate ADMM64 quality')
    fields = QUALITY_IDENTITY_FIELDS + ('floating_model_trace', 'quality')
    mismatches = [field for field in fields if before[field] != after[field]]
    if mismatches:
        raise ValidationError(f'ADMM64 quality: changed exact evidence {mismatches}')
    return dict(status='PASS', threshold_snr_db=20.0, baseline=dict(path=str(baseline_summary), sha256=digest(baseline_summary)),
                candidate=dict(path=str(candidate_summary), sha256=digest(candidate_summary)), case=dict(
                    fixed_snr_db=after['quality']['fixed']['snr_db'], floating_snr_db=after['quality']['floating']['snr_db'],
                    nmse_ratio=after['quality']['nmse_ratio'], snr_loss_db=after['quality']['snr_loss_db'],
                    raw_x_sha256=after['output_raw_x_sha256'], raw_r_sha256=after['output_raw_r_sha256'],
                    status=after['status'], inner_iterations=after['inner_iterations'], package_sha256=after['package_sha256']))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-m32', required=True)
    parser.add_argument('--candidate-m32', required=True)
    parser.add_argument('--baseline-m64', required=True)
    parser.add_argument('--candidate-m64', required=True)
    parser.add_argument('--output', required=True, help='new directory; never an existing published report')
    parser.add_argument('--baseline-admm-quality', help='separate source-clean M64 ADMM outer64 quality baseline')
    parser.add_argument('--admm-quality', help='separate source-clean M64 ADMM outer64 quality candidate')
    args = parser.parse_args(argv)
    output = Path(args.output)
    if output.exists():
        raise ValidationError(f'output already exists: {output}')
    output.mkdir(parents=True)
    comparison = dict(schema=2, status='PASS',
                      scope='Fair fixed K8, outer8 M32/M64 primary active10 only; paired ADMM is reference-only; no V2/V3 ratios.',
                      geometries=[compare_geometry(args.baseline_m32, args.candidate_m32, 32),
                                  compare_geometry(args.baseline_m64, args.candidate_m64, 64)],
                      quality_admm64=None)
    if bool(args.baseline_admm_quality) != bool(args.admm_quality):
        raise ValidationError('--baseline-admm-quality and --admm-quality must be supplied together')
    if args.admm_quality:
        comparison['quality_admm64'] = validate_admm_quality(args.baseline_admm_quality, args.admm_quality)
    (output / 'round2_comparison.json').write_text(json.dumps(comparison, indent=2) + '\n', encoding='utf-8')
    (output / 'round2_comparison_vi.md').write_text(render_markdown(comparison), encoding='utf-8')
    print(output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
