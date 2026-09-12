"""Apply the configured application SNR floor to existing, immutable outer evidence.

No reconstruction or metric is recomputed, and no original result is rewritten.
This is a retrospective calibration assessment, never held-out qualification.
"""
from __future__ import annotations

from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'reports/v4'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def number(value):
    # Existing JSON represents nonfinite diagnostics with explicit string tags.
    if value == 'inf':
        return math.inf
    if value == '-inf':
        return -math.inf
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f'invalid numeric evidence: {value!r}')
    if math.isnan(value):
        raise ValueError('NaN metric cannot qualify')
    return value


def main():
    config_path = ROOT / 'config/v4_design.json'
    source_path = OUT / 'lfsr_outer_contract.json'
    source_digest = digest(source_path)
    source = json.loads(source_path.read_text(encoding='utf-8'))
    config = json.loads(config_path.read_text(encoding='utf-8'))['numerical']
    policy = config['application_quality']
    floor = policy['absolute_snr_min_db']
    assert source['complete'] and len(source['rows']) == source['rows_expected']
    cases = {case['name']: case for case in source['cases']}
    assert len(cases) == len(source['cases'])
    rows = []
    seen = set()
    for row in source['rows']:
        key = (row['case'], row['algorithm'])
        assert key not in seen
        seen.add(key)
        truth = cases[row['case']]['original']
        energy = sum(float(x) ** 2 for x in truth)
        q = row['quality_full_original_units']
        no_fault = all(
            row[f'{domain}_exception'] is None
            and row[f'{domain}_result'].get('returned_without_numeric_fault') is True
            for domain in ('float', 'fixed')
        )
        eligible = energy > 0 and q is not None
        relative = bool(eligible and number(q['snr_loss_db']) <= config['max_snr_loss_db']
                        and number(q['nmse_ratio']) <= config['max_nmse_ratio'])
        float_floor = bool(eligible and number(q['float']['snr_db']) >= floor)
        fixed_floor = bool(eligible and number(q['fixed']['snr_db']) >= floor)
        failed = []
        for label, ok in [('nonzero_truth_and_metrics', eligible), ('no_numeric_fault', no_fault),
                          ('relative_quality', relative), ('float_SNR_floor', float_floor),
                          ('fixed_SNR_floor', fixed_floor)]:
            if not ok:
                failed.append(label)
        rows.append({
            'case': row['case'], 'algorithm': row['algorithm'], 'track': row['track'],
            'source_domain': 'real' if row['coefficient_domain_track'] else 'synthetic',
            'source_report_row_index': len(rows),
            'float_SNR_db': q['float']['snr_db'] if q else None,
            'fixed_SNR_db': q['fixed']['snr_db'] if q else None,
            'centered_quality_diagnostic_only': row['quality_centered_original_units'],
            'relative_quality_pass': relative, 'no_numeric_fault': no_fault,
            'float_floor_pass': float_floor, 'fixed_floor_pass': fixed_floor,
            'combined_pass': not failed, 'failed_gates': failed,
            'float_status': row['float_status'], 'fixed_status': row['fixed_status'],
        })

    def counts(items):
        return {'passed': sum(r['combined_pass'] for r in items), 'total': len(items)}

    def group(field):
        grouped = defaultdict(list)
        for row in rows:
            grouped[row[field]].append(row)
        return dict(grouped)

    report = {
        'schema': 'v4-lfsr-application-floor-reassessment-v1', 'complete': True,
        'scope': 'retrospective_calibration_reassessment_no_new_solves_no_heldout',
        'source_report': source_path.relative_to(ROOT).as_posix(),
        'source_report_sha256': source_digest,
        'config': config_path.relative_to(ROOT).as_posix(), 'config_sha256': digest(config_path),
        'script_sha256': digest(Path(__file__)),
        'policy': policy, 'max_snr_loss_db': config['max_snr_loss_db'],
        'max_nmse_ratio': config['max_nmse_ratio'],
        'numeric_outputs_or_original_metrics_recomputed': False,
        'old_relative_results_preserved': True, 'heldout_qualified': False,
        'convergence_qualified': False, 'production_profile_selected': False,
        'summary': counts(rows),
        'by_source_domain': {k: counts(v) for k, v in group('source_domain').items()},
        'by_case': {k: counts(v) for k, v in group('case').items()},
        'by_algorithm': {k: counts(v) for k, v in group('algorithm').items()},
        'rows': rows,
    }
    # SNR and NMSE must be the same original-signal metric, not PSNR in disguise.
    for row in source['rows']:
        q = row['quality_full_original_units']
        if q:
            for domain in ('float', 'fixed'):
                nmse = number(q[domain]['nmse'])
                if math.isfinite(nmse) and nmse > 0:
                    assert math.isclose(number(q[domain]['snr_db']), -10 * math.log10(nmse), abs_tol=1e-9)
    assert digest(source_path) == source_digest
    (OUT / 'lfsr_snr20_reassessment.json').write_text(
        json.dumps(report, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    lines = ['# LFSR: đánh giá lại theo SNR khôi phục tối thiểu 20 dB', '',
             'Ngưỡng do người dùng chọn: **SNR float và fixed đều ≥20 dB**, đồng thời',
             'SNR loss≤0,5 dB, NMSE ratio≤1,10 và không lỗi số học. Áp trên từng ca.',
             'SNR tính trên tín hiệu gốc sau inverse transform và undo normalization;',
             'với năng lượng tín hiệu khác0, SNR20 dB tương đương NMSE0,01.', '',
             f"**{report['summary']['passed']}/{len(rows)} ca đạt đầy đủ.** Kết quả cũ 82/82 chỉ là relative quality/no-fault.",
             'Đây là đánh giá lại calibration đã có; không chạy lại solver, chỉnh tín hiệu,',
             'đổi tham số hay sửa kết quả gốc. Chưa có held-out hoặc chứng nhận hội tụ.', '',
             '| Nhóm | Đạt đầy đủ |', '|---|---:|']
    for name, count in report['by_source_domain'].items():
        lines.append(f"| {name} | {count['passed']}/{count['total']} |")
    lines += ['', '| Ca | Đạt đầy đủ | Fixed SNR min–max (dB) |', '|---|---:|---:|']
    for case, cr in group('case').items():
        values = [number(r['fixed_SNR_db']) for r in cr if r['fixed_SNR_db'] is not None]
        limits = f'{min(values):.2f}–{max(values):.2f}' if values else 'unavailable'
        c = counts(cr)
        lines.append(f"| {case} | {c['passed']}/{c['total']} | {limits} |")
    lines += ['', '| Thuật toán | Toàn bộ | Synthetic | Real |', '|---|---:|---:|---:|']
    for algorithm, ar in group('algorithm').items():
        cc = [counts(ar)] + [counts([r for r in ar if r['source_domain'] == d]) for d in ('synthetic', 'real')]
        lines.append(f"| {algorithm} | " + ' | '.join(f"{c['passed']}/{c['total']}" for c in cc) + ' |')
    lines += ['', '## Giới hạn và hành động numerical tiếp theo', '',
              '- Hai ECG windows chưa đạt20 dB ngay cả ở float; cần kiểm basis, sampling ratio, K, regularization và budget trên calibration trước khi quy lỗi cho bit.',
              '- Full SNR có thể cao ở patch ảnh gần hằng do năng lượng DC lớn. Giữ centered SNR trong từng row để thấy sai số phần biến thiên; không tự áp thêm ngưỡng20 dB cho centered metric.',
              '- Giữ mọi seed/window/algorithm thất bại trong bảng so sánh; chọn application showcase và khóa tham số trước dữ liệu held-out.',
              '- Chưa tăng bit, đổi LFSR, chạy RTL hoặc suy ra throughput/board qualification từ đánh giá này.', '',
              '[Từng row và provenance](lfsr_snr20_reassessment.json); [kết quả numerical gốc](lfsr_outer_contract.json);',
              '[protocol hiện hành](../../docs/v4/NUMERICAL_PROTOCOL.md).', '']
    (OUT / 'LFSR_SNR20_REASSESSMENT.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('summary', 'by_source_domain', 'by_case')}, indent=2))


if __name__ == '__main__':
    main()
