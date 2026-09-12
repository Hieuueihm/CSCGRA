"""Summarize completed application calibration without hiding unselected rows."""
from __future__ import annotations
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'reports/v4'
ALGORITHMS = ('MP', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'IHT', 'HTP', 'GP', 'FISTA', 'ADMM', 'PDHG')
DOMAINS = ('synthetic', 'ecg', 'camera')
LABELS = {'synthetic': 'Synthetic / identity', 'ecg': 'ECG / db4', 'camera': 'Camera / Haar'}
EXPECTED = {'lfsr_application_float_tuning': 534, 'lfsr_basis_feasibility': 48,
            'lfsr_wavelet_float_tuning': 360, 'lfsr_tuned_synthetic_fixed': 33,
            'lfsr_tuned_wavelet_fixed': 32, 'lfsr_outer_contract': 82}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def number(value):
    return float(value) if value is not None else math.nan


def fmt(value, digits=3):
    return '—' if value is None else f'{number(value):.{digits}f}'


def safe(value):
    if isinstance(value, dict):
        return {key: safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [safe(item) for item in value]
    if isinstance(value, float) and not math.isfinite(value):
        return 'nan' if math.isnan(value) else ('inf' if value > 0 else '-inf')
    return value


def verify_sources(name, report, report_path=None, ancestors=()):
    report_path = (report_path or OUT / (name + '.json')).resolve()
    assert report_path.is_relative_to(ROOT)
    assert report_path not in ancestors, 'cyclic assembly provenance'
    sources = report['source_sha256']
    bundle = hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest()
    archive = OUT / 'source_snapshots' / bundle
    base = archive if archive.exists() else ROOT
    for relative, expected in sources.items():
        path = (base / relative).resolve()
        assert path.is_relative_to(base.resolve()), relative
        assert sha(path) == expected, f'{name}: source mismatch {relative}'
    if report.get('selection_report'):
        path = (ROOT / report['selection_report']).resolve()
        assert path.is_relative_to(ROOT)
        assert sha(path) == report['selection_report_sha256'], name + ': changed selection artifact'
    components = []
    if report.get('assembly_only'):
        assert report['source_unchanged_during_assembly'], name
        assert report.get('execution_components'), name + ': missing assembled components'
        loaded_components = {}
        for component in report['execution_components']:
            component_path = (ROOT / component['report']).resolve()
            assert component_path.is_relative_to(ROOT)
            assert sha(component_path) == component['sha256'], str(component_path)
            component_report = json.loads(component_path.read_text(encoding='utf-8'))
            assert component_report['complete'] or component_report.get('interrupted_for_execution_acceleration')
            assert len(component_report['rows']) == component['completed_case_rows']
            loaded_components[component['report']] = component_report
            for key, digest in component_report['source_sha256'].items():
                assert sources[key] == digest, 'mixed execution source revisions'
            components.append(verify_sources(component_path.stem, component_report,
                                            component_path, (*ancestors, report_path)))
        assert all(row.get('execution_provenance') for row in report['rows']), name + ': row provenance missing'
        identity = lambda row: tuple(row[key] for key in ('domain', 'case', 'algorithm', 'recipe_id'))
        for row in report['rows']:
            origin = row['execution_provenance']
            assert origin in report['execution_components']
            originals = [r for r in loaded_components[origin['report']]['rows'] if identity(r) == identity(row)]
            assert len(originals) == 1
            assert {key: value for key, value in row.items() if key != 'execution_provenance'} == originals[0]
        for duplicate in report.get('duplicate_execution_comparisons', []):
            assert duplicate['all_numerical_fields_exactly_equal']
            pair = []
            for source in ('previous_report', 'compared_report'):
                originals = [r for r in loaded_components[duplicate[source]]['rows']
                             if identity(r) == tuple(duplicate['identity'])]
                assert len(originals) == 1
                pair.append({key: value for key, value in originals[0].items() if key != 'model_seconds'})
            assert pair[0] == pair[1], 'duplicate numerical evidence changed'
    return {'report': report_path.relative_to(ROOT).as_posix(), 'report_sha256': sha(report_path),
            'source_bundle_id': bundle, 'source_files': len(sources),
            'verification_location': base.relative_to(ROOT).as_posix() if base != ROOT else 'current_workspace',
            'archived_sources_verified': archive.exists(), 'all_sources_verified': True,
            'assembly_only': bool(report.get('assembly_only')), 'component_reports': components,
            'executed_model_sha256': {key: value for key, value in sources.items() if key.startswith('models/v4/')}}


def selected_rows(report, selections):
    rows = []
    for selection in selections:
        group = [r for r in report['rows'] if r['recipe_id'] == selection['winner']['recipe_id']]
        assert len(group) == len(selection['winner']['case_results'])
        rows.extend(group)
    return rows


def gates(row, floating):
    quality = row['quality_full_original_units']
    relative = bool(quality and quality['arithmetic_quality_pass'])
    absolute = bool(quality and number(quality['float']['snr_db']) >= 20
                    and number(quality['fixed']['snr_db']) >= 20)
    nofault = bool(row['exception'] is None and floating['no_numeric_fault']
                   and row['fixed_result'].get('returned_without_numeric_fault'))
    observed = all(a['diagnostic_accepted'] for a in row['LS_observations'])
    capacity = bool(row['capacity_eligible'])
    combined = relative and absolute and nofault and observed and capacity
    assert observed == row['LS_diagnostic_pass']
    assert combined == row['combined_pass'], (row['case'], row['algorithm'])
    return {'relative_quality': relative, 'absolute_snr20': absolute, 'no_numeric_fault': nofault,
            'LS_diagnostic': observed, 'capacity': capacity, 'combined': combined}


def recipe_label(recipe):
    n = recipe['iterations']
    if 'regularization' in recipe:
        return f"iter={n}, λ={recipe['regularization']:g}, ρ={recipe['admm_rho']:g}"
    return f"K={recipe['sparsity']}, iter={n}, step={recipe['step_multiplier']:g}/L"


def main():
    reports = {}
    for name, count in EXPECTED.items():
        report = json.loads((OUT / (name + '.json')).read_text(encoding='utf-8'))
        if not report['complete']:
            raise ValueError('Study still incomplete: ' + name)
        if report.get('assembly_only'):
            assert report['source_unchanged_during_assembly'], name
        else:
            assert report['source_unchanged_during_run'], name
        assert len(report['rows']) == count, (name, len(report['rows']), count)
        reports[name] = report
    provenance = [verify_sources(name, report) for name, report in reports.items()]
    dct = reports['lfsr_application_float_tuning']
    wavelet = reports['lfsr_wavelet_float_tuning']
    basis = reports['lfsr_basis_feasibility']
    baseline = reports['lfsr_outer_contract']
    synthetic_selections = [s for s in dct['selected_policies'] if s['domain'] == 'synthetic']
    selections = synthetic_selections + wavelet['selected_policies']
    floating_rows = selected_rows(dct, synthetic_selections) + selected_rows(wavelet, wavelet['selected_policies'])
    assert len(floating_rows) == 77 and len(selections) == 33
    float_index = {(r['case'], r['algorithm']): r for r in floating_rows}
    fixed_rows = reports['lfsr_tuned_synthetic_fixed']['rows'] + reports['lfsr_tuned_wavelet_fixed']['rows']
    assert len(fixed_rows) == 65
    fixed_index = {(r['case'], r['algorithm']): r for r in fixed_rows}
    assert len(fixed_index) == 65
    unselected = [r for r in floating_rows if (r['case'], r['algorithm']) not in fixed_index]
    assert len(unselected) == 12 and all(r['domain'] == 'ecg' for r in unselected)
    unselected_below_floor = sum(number(r['full_original_quality']['snr_db']) < 20 for r in unselected)
    unselected_above_floor = sum(number(r['full_original_quality']['snr_db']) >= 20 for r in unselected)
    assert unselected_below_floor + unselected_above_floor == len(unselected)
    assert all(not s['selected_for_fixed_check'] for s in wavelet['selected_policies']
               if s['algorithm'] in {r['algorithm'] for r in unselected} and s['domain'] == 'ecg')
    row_gates = {(r['case'], r['algorithm']): gates(r, float_index[(r['case'], r['algorithm'])]) for r in fixed_rows}
    counts = {key: sum(g[key] for g in row_gates.values()) for key in next(iter(row_gates.values()))}
    audits = [a for r in fixed_rows for a in r['LS_observations']]
    observed_numbers = lambda key: [number(a[key]) for a in audits if a.get(key) is not None]
    max_observed = lambda key: max(observed_numbers(key), default=None)
    ls_summary = {'observations': len(audits), 'returned': sum(a['runtime_returned'] for a in audits),
                  'diagnostic_pass': sum(a['diagnostic_accepted'] for a in audits),
                  'diagnostic_exceptions': sum('diagnostic_exception' in a for a in audits),
                  'rank_deficient_returned': sum(a.get('rank', len(a['ordered_support'])) < len(a['ordered_support']) for a in audits),
                  'max_condition_number': max_observed('condition_number'),
                  'max_coefficient_relative_error': max_observed('coefficient_relative_error'),
                  'max_normal_relative_float64': max_observed('normal_relative_float64'),
                  'max_LS_support': max(len(a['ordered_support']) for a in audits),
                  'status_counts': dict(Counter(a['status'] for a in audits))}
    quality_rows = [r['quality_full_original_units'] for r in fixed_rows if r['quality_full_original_units']]
    worst = {'snr_loss_db': max(number(q['snr_loss_db']) for q in quality_rows),
             'nmse_ratio': max(number(q['nmse_ratio']) for q in quality_rows)}
    improved = []
    for row in fixed_rows:
        q = row['quality_full_original_units']
        if q and number(q['fixed']['snr_db']) > number(q['float']['snr_db']):
            floating = float_index[(row['case'], row['algorithm'])]
            improved.append({'case': row['case'], 'algorithm': row['algorithm'],
                'fixed_snr_gain_db': number(q['fixed']['snr_db']) - number(q['float']['snr_db']),
                'same_final_support': row['fixed_result']['support'] == floating['support']})
    failures = [{**{key: r[key] for key in ('case', 'domain', 'algorithm', 'exception')},
                 'gates': row_gates[(r['case'], r['algorithm'])],
                 'fixed_status': r['fixed_result'].get('status'),
                 'quality': r['quality_full_original_units']}
                for r in fixed_rows if not row_gates[(r['case'], r['algorithm'])]['combined']]
    costs = []
    for selection in selections:
        group = [r for r in fixed_rows if r['domain'] == selection['domain']
                 and r['algorithm'] == selection['algorithm']]
        if not group:
            continue
        traces = [trace for r in group for trace in r['fixed_result'].get('solver_trace', [])]
        cost = {'domain': selection['domain'], 'algorithm': selection['algorithm'],
                'recipe': selection['winner']['recipe'], 'cases': len(group),
                'LS_calls': len(traces), 'LS_steps': sum(t.get('steps', 0) for t in traces),
                'LS_kernel_counts': {key: sum(t.get('counts', {}).get(key, 0) for t in traces)
                                     for key in ('gemv', 'dot', 'div', 'sqrt', 'scale', 'add', 'sub')},
                'LS_certificate_kernel_counts': {key: sum(t.get('counts', {}).get('certificate', {}).get(key, 0) for t in traces)
                                                 for key in ('gemv', 'dot', 'div', 'sqrt')},
                'model_wall_seconds_sum': sum(r['model_seconds'] for r in group),
                'per_case': [{'case': r['case'], 'model_wall_seconds': r['model_seconds'],
                              'execution_provenance': r.get('execution_provenance'),
                              'LS_calls': len(r['fixed_result'].get('solver_trace', [])),
                              'LS_steps': sum(t.get('steps', 0) for t in r['fixed_result'].get('solver_trace', []))}
                             for r in group], 'FPGA_cycles_measured': False}
        costs.append(cost)
    table = []
    for algorithm in ALGORITHMS:
        for domain in DOMAINS:
            selection = next(s for s in selections if s['domain'] == domain and s['algorithm'] == algorithm)
            floating = [r for r in floating_rows if r['domain'] == domain and r['algorithm'] == algorithm]
            fixed = [r for r in fixed_rows if r['domain'] == domain and r['algorithm'] == algorithm]
            table.append({'algorithm': algorithm, 'domain': domain,
                'minimum_float_snr_db': min(number(r['full_original_quality']['snr_db']) for r in floating),
                'minimum_fixed_snr_db': min((number(r['quality_full_original_units']['fixed']['snr_db']) for r in fixed if r['quality_full_original_units']), default=None),
                'fixed_rows': len(fixed), 'full_grid_rows': len(floating),
                'combined_pass': sum(row_gates[(r['case'], r['algorithm'])]['combined'] for r in fixed),
                'selected_for_fixed': selection['selected_for_fixed_check'], 'recipe': selection['winner']['recipe']})
    log_path = OUT / 'lfsr_application_tuning_tests.log'
    log = log_path.read_text(encoding='utf-8-sig')
    test_match = re.search(r'Ran (\d+) tests', log)
    assert test_match and int(test_match.group(1)) > 0 and re.search(r'\nOK\s*$', log)
    test_count = int(test_match.group(1))
    # Numeric models used by the new studies must still be the models now read.
    model_hashes = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted((ROOT / 'models/v4').glob('*.py'))}
    def verify_models(node):
        if node['assembly_only']:
            for component in node['component_reports']:
                verify_models(component)
        else:
            for path, value in model_hashes.items():
                assert node['executed_model_sha256'][path] == value, (node['report'], path)
    for node in provenance:
        if not node['report'].endswith('/lfsr_outer_contract.json'):
            verify_models(node)
    centered_min = min(number(r['quality_centered_original_units']['fixed']['snr_db']) for r in fixed_rows if r['quality_centered_original_units'])
    lines = ['# LFSR: chất lượng ứng dụng sau chỉnh basis và policy', '',
        '**Đây là kết quả calibration; chưa khóa bit production, chưa có RTL/synth/impl hoặc kiểm chứng held-out.**', '',
        'Cấu hình giữ nguyên: D18F14 / C18F16 / S27F22 / X24F20 / ACC64. Chuẩn hóa y bằng 2^e trước D, giữ X qua các vòng ngoài của recovery; FISTA/ADMM/PDHG vẫn lưu D.',
        'Operator LFSR32, M=128, N=256, noise measurement 30 dB; K tối đa32, danh sách support và LS working support tối đa96. Đây chưa phải qualification toàn bộ N≤1024.', '',
        '## Đếm đúng ca kiểm', '',
        f"Đã chạy **{len(fixed_rows)} ca fixed được chọn**: 33 synthetic và32 ứng dụng wavelet. Trong đó **{counts['combined']}/65** đạt đồng thời tất cả các cổng dưới đây.",
        f"Grid ứng dụng mới đầy đủ có **77 ca**: 33 synthetic +22 ECG/db4 +22 camera/Haar. Có **12 ca ECG không được chọn chạy fixed** vì policy dùng chung của6 thuật toán chưa đạt20 dB ở float trên cả hai cửa sổ. Vì vậy bằng chứng đạt hiện là **{counts['combined']}/77**, còn {77-counts['combined']} ca chưa đạt hoặc chưa được xác nhận, không phải77/77.",
        f"Trong12 ca chưa chạy fixed, **{unselected_below_floor} ca có SNR float<20 dB**; **{unselected_above_floor} ca đã có SNR float≥20 dB** nhưng cửa sổ còn lại của cùng domain/thuật toán chưa đạt, nên policy dùng chung không được chọn. Nhóm sau chưa được kiểm fixed, không được gọi là thất bại numerical.",
        'Một policy được chọn cho cả hai cửa sổ trong từng domain/thuật toán; ưu tiên budget thấp nhất có SNR nhỏ nhất≥20,5 dB, sau đó≥20 dB. Các lựa chọn dưới ngưỡng vẫn được giữ trong bảng để thấy rõ thất bại.', '',
        '| Cổng trên65 ca đã chạy fixed | Đạt |', '|---|---:|',
        f"| Sai khác float/fixed: mất≤0,5 dB; NMSE≤1,10× | {counts['relative_quality']}/65 |",
        f"| Float và fixed đều SNR≥20 dB trên tín hiệu gốc đầy đủ | {counts['absolute_snr20']}/65 |",
        f"| Không lỗi số học ở float/fixed | {counts['no_numeric_fault']}/65 |",
        f"| LS certificate và diagnostic độc lập đạt ở mọi LS được gọi | {counts['LS_diagnostic']}/65 |",
        f"| Support/LS không vượt dung lượng96 | {counts['capacity']}/65 |",
        f"| Đồng thời tất cả | {counts['combined']}/65 |", '',
        'Cổng LS là N/A và không chặn các chương trình không gọi LS; đếm quan sát LS thực ở phần bên dưới. Proximal dùng vector đặc N phần tử; tập hệ số khác0 của chúng không phải danh sách support96.',
        f"Mất SNR lớn nhất trên65 ca: {worst['snr_loss_db']:.6f} dB; NMSE ratio lớn nhất: {worst['nmse_ratio']:.8f}.", '',
        f"Có {len(improved)} ca SNR fixed cao hơn float ở budget đã chọn; trong đó {sum(not r['same_final_support'] for r in improved)} ca có support cuối khác nhau. Hiện tượng này có ở CoSaMP/ECG: làm tròn có thể đổi lựa chọn support và quỹ đạo lặp, nên tại budget hữu hạn fixed có thể đi tới nghiệm tốt hơn cho một ca. Đây không phải bằng chứng fixed nói chung chính xác hơn float; float vẫn là tham chiếu của cùng policy, không phải nghiệm tối ưu toàn cục.", '',
        '## SNR nhỏ nhất theo domain và thuật toán', '',
        'Mỗi ô ghi **float / fixed (dB); đạt/grid**. Dấu — nghĩa chưa chạy fixed; không có kết quả fixed để suy ra. Mẫu số synthetic là3 seed; ECG/camera là2 cửa sổ.', '',
        '| Thuật toán | Synthetic / identity | ECG / db4 | Camera / Haar |', '|---|---:|---:|---:|']
    for algorithm in ALGORITHMS:
        cells = []
        for domain in DOMAINS:
            t = next(t for t in table if t['algorithm'] == algorithm and t['domain'] == domain)
            cells.append(f"{fmt(t['minimum_float_snr_db'])} / {fmt(t['minimum_fixed_snr_db'])}; {t['combined_pass']}/{t['full_grid_rows']}")
        lines.append('| ' + algorithm + ' | ' + ' | '.join(cells) + ' |')
    lines += ['', 'SNR chính được tính trên tín hiệu gốc đầy đủ sau hoàn nguyên mean/scale. SNR sau loại mean được lưu riêng, không dùng thay cổng đã chọn.',
        f"SNR centered nhỏ nhất trong65 ca fixed là {centered_min:.3f} dB. Thành phần DC có thể nâng SNR đầy đủ, nhất là patch camera ít biến thiên; đạt20 dB đầy đủ chưa chứng minh giữ morphology ECG hoặc chi tiết ảnh.", '',
        '![SNR ứng dụng](lfsr_application_snr.png)', '', '## Những ca chưa đạt vẫn được giữ', '',
        '| ECG/db4 chưa được chọn fixed | SNR float từng cửa sổ (dB) | Policy dùng chung được giữ |', '|---|---|---|']
    for algorithm in ALGORITHMS:
        group = [r for r in unselected if r['algorithm'] == algorithm]
        if group:
            selection = next(s for s in selections if s['domain'] == 'ecg' and s['algorithm'] == algorithm)
            lines.append(f"| {algorithm} | " + '; '.join(f"{r['case']}: {fmt(r['full_original_quality']['snr_db'])}" for r in group) + f" | {recipe_label(selection['winner']['recipe'])} |")
    if failures:
        lines += ['', '| Ca fixed không đạt đồng thời | Cổng không đạt | Trạng thái |', '|---|---|---|']
        for row in failures:
            lines.append(f"| {row['case']} / {row['algorithm']} | " + ', '.join(k for k, value in row['gates'].items() if not value and k != 'combined') + f" | {row['fixed_status']} |")
    else:
        lines += ['', 'Không có ca fixed thất bại trong65 ca được chọn. Điều này không thay đổi12 ca ECG chưa được chọn.']
    lines += ['', '## LS trên support thực của thuật toán', '',
        f"Đã quan sát **{len(audits)} lần gọi LS**; {ls_summary['returned']} lần trả nghiệm, {ls_summary['diagnostic_pass']} lần đạt diagnostic, {ls_summary['diagnostic_exceptions']} lỗi riêng của bộ quan sát. Support LS lớn nhất: {ls_summary['max_LS_support']}.",
        f"Condition number lớn nhất của B đã lượng tử hóa: {fmt(ls_summary['max_condition_number'], 6)}; sai số hệ số tương đối lớn nhất so SVD cùng B/y: {ls_summary['max_coefficient_relative_error']:.9g}; normal residual float64 lớn nhất: {ls_summary['max_normal_relative_float64']:.9g}.",
        'LSQR runtime dùng normal tolerance1e-5, budget128, certificate trên nghiệm đã lưu X. Diagnostic độc lập yêu cầu đủ rank, sai số hệ số≤1e-3 và normal residual float64≤1e-5. Oracle SVD chỉ quan sát, không sửa nghiệm hoặc điều kiện dừng; lỗi diagnostic không thay đổi return/exception của solver.',
        'Các quan sát chỉ bao phủ support xuất hiện trong65 ca calibration này. Không suy rộng sang mọi seed, mọi support hoặc ma trận gần suy biến tổng quát.', '',
        '## Chi phí numerical và nút thắt LS lặp lại', '',
        'Bảng cộng trên mọi cửa sổ của từng policy đã chạy fixed. GEMV/DIV/SQRT được đếm từ trace **bên trong LSQR**, đã gồm certificate; không phải tổng phép toán của thuật toán ngoài. Các chương trình không gọi LSQR vẫn có công việc GEMV/vector riêng; ADMM có shifted-CG riêng không nằm trong bảng đếm LSQR.',
        'Thời gian là wall time của model Python cùng instrumentation/diagnostic SVD trên máy hiện tại. Đây không phải chu kỳ, throughput hoặc thời gian FPGA. Số lần lặp LS và GEMV dùng để nhận diện công việc cần lập lịch/tái sử dụng trên PE array, chưa chứng minh tốc độ phần cứng.', '',
        'Các ca fixed có thể được ghép từ hai backend thực thi Python tương đương: backend ban đầu và backend cache chuyển đổi ma trận. Cache chỉ tránh việc chuyển đổi dữ liệu lặp lại, không thay đổi phép toán integer; đối chiếu bit-exact và test được giữ riêng. Vì backend và overhead khác nhau, wall time giữa các ca không phải phép so tốc độ thuật toán công bằng, càng không phải so tốc độ FPGA. Mỗi ca giữ provenance của lần chạy; artifact ghép không giả định một lần chạy liền mạch.', '',
        '| Domain / thuật toán | Số ca | LS calls | Tổng LS steps | GEMV | DIV | SQRT | Model giây |',
        '|---|---:|---:|---:|---:|---:|---:|---:|']
    for cost in costs:
        kernel = cost['LS_kernel_counts']
        lines.append(f"| {LABELS[cost['domain']]} / {cost['algorithm']} | {cost['cases']} | {cost['LS_calls']} | {cost['LS_steps']} | {kernel['gemv']} | {kernel['div']} | {kernel['sqrt']} | {cost['model_wall_seconds_sum']:.2f} |")
    lines += ['',
        '## So sánh với DCT cũ và bằng chứng chọn basis', '',
        'Bảng dưới so baseline cũ với cấu hình mới trên cùng cửa sổ nguồn. Cấu hình mới đổi cả basis lẫn policy/budget; đây là tác động kết hợp, không gán toàn bộ cải thiện cho riêng basis. LFSR giữ seed/shape; noise giữ hướng ghép cặp và30 dB, biên độ noise đổi theo năng lượng measurement của basis.', '',
        '| Domain | Baseline cũ đạt20 dB + relative/no-fault | Cấu hình mới đạt đầy đủ/grid |', '|---|---:|---:|']
    for domain in DOMAINS:
        old = [r for r in baseline['rows'] if ((domain == 'synthetic' and r['case'].startswith('synthetic_n256')) or (domain == 'ecg' and r['case'].startswith('ecg')) or (domain == 'camera' and r['case'].startswith('camera')))]
        def old_pass(row):
            q = row['quality_full_original_units']
            return bool(q and number(q['float']['snr_db']) >= 20 and number(q['fixed']['snr_db']) >= 20 and q['arithmetic_quality_pass']
                        and row['float_exception'] is None and row['fixed_exception'] is None
                        and row['float_result']['returned_without_numeric_fault'] and row['fixed_result']['returned_without_numeric_fault'])
        new = [t for t in table if t['domain'] == domain]
        lines.append(f"| {LABELS[domain]} | {sum(old_pass(r) for r in old)}/{len(old)} | {sum(t['combined_pass'] for t in new)}/{sum(t['full_grid_rows'] for t in new)} |")
    lines += ['', '**Study basis kiểm soát riêng48 ca**: 3 cửa sổ ×4 basis ×4 policy cố định (OMP K32, SP K32, FISTA λ0,001/0,003). Mọi tín hiệu giữ đầy đủ; không làm K-sparse trước sensing. Best-K oracle trong artifact chỉ là diagnostic ngoại tuyến.', '',
        '| Basis | Float full SNR≥20 dB /12 | SNR full nhỏ nhất–lớn nhất (dB) |', '|---|---:|---:|']
    for name in ('dct', 'haar', 'db4', 'sym4'):
        group = [r for r in basis['rows'] if r['basis'] == name]
        values = [number(r['quality']['original']['snr_db']) for r in group if r.get('quality')]
        lines.append(f"| {name} | {sum(r.get('original_snr20_pass', False) for r in group)}/12 | {min(values):.3f}–{max(values):.3f} |")
    lines += ['', f"Sau đó quét policy DCT {len(dct['rows'])} ca và wavelet {len(wavelet['rows'])} ca. Toàn bộ kết quả, kể cả {dct['summary']['capacity_ineligible_rows']} ca DCT và {wavelet['summary']['capacity_ineligible_rows']} ca wavelet vượt dung lượng, đều giữ trong JSON. Những ca này không đủ điều kiện chọn vào fixed.", '',
        '## Policy được giữ để tái lập', '', '| Domain | Thuật toán | Policy | Được chọn fixed |', '|---|---|---|---|']
    for selection in selections:
        lines.append(f"| {LABELS[selection['domain']]} | {selection['algorithm']} | {recipe_label(selection['winner']['recipe'])} | {'Có' if selection['selected_for_fixed_check'] else 'Không'} |")
    lines += ['', 'Step chính xác và mọi trường Policy nằm trong artifact float/fixed; L là spectral bound dùng chung cho float và lượng tử hóa C. SP vẫn có rollback khi residual không giảm. Budget hoàn tất không đồng nghĩa convergence.', '',
        '## Kiểm chứng và phạm vi', '',
        f'**{test_count} tests đạt**: bao gồm toán học fixed, normalization/X, observer không ảnh hưởng solver và phép tăng tốc integer có đối chiếu với model gốc. Đây là số test trong log được hash; không phải số bộ dữ liệu.',
        'Mã nguồn thực thi được kiểm tra theo snapshot nếu đã archive, nếu chưa thì đối chiếu workspace hiện tại. Artifact fixed liên kết hash chính xác artifact chọn policy; không chọn lại theo kết quả fixed.',
        '[Verification và hashes](application_tuning_verification.json); [test log](lfsr_application_tuning_tests.log); [534 ca DCT/identity](lfsr_application_float_tuning.json); [48 ca basis](lfsr_basis_feasibility.json); [360 ca wavelet](lfsr_wavelet_float_tuning.json); [33 ca fixed synthetic](lfsr_tuned_synthetic_fixed.json); [32 ca fixed wavelet](lfsr_tuned_wavelet_fixed.json).',
        'Chưa có bệnh nhân/bản ghi/scene held-out; chưa chứng minh11 ứng dụng khác nhau. Đây là3 nhóm bài toán, với2 cửa sổ ECG cùng bản ghi và2 patch cùng ảnh camera. Chưa có staged raw Phi/Psi, LFSR cache/context chạy phần cứng, convergence, RTL hoặc kết quả trên ZCU106. Bộ bit vẫn là shortlist khảo sát.', '']
    markdown = OUT / 'LFSR_APPLICATION_TUNING.md'
    markdown.write_text('\n'.join(lines), encoding='utf-8')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(15, 6.3), sharey=True, layout='constrained')
    for ax, domain in zip(axes, DOMAINS):
        values = [next(t for t in table if t['algorithm'] == algorithm and t['domain'] == domain) for algorithm in ALGORITHMS]
        y = list(range(len(ALGORITHMS)))
        ax.axvspan(0, 20, color='#FBE7E5', alpha=.75)
        ax.axvline(20, color='#A32926', linestyle='--', linewidth=1.2, label='20 dB floor')
        ax.scatter([v['minimum_float_snr_db'] for v in values], y, s=43, marker='o', facecolors='white', edgecolors='#21618C', label='Float: shared policy')
        for index, value in enumerate(values):
            if value['minimum_fixed_snr_db'] is not None:
                ax.scatter(value['minimum_fixed_snr_db'], index, s=36, marker='x', color='#138B68')
            else:
                ax.text(value['minimum_float_snr_db'] + .35, index + .16, 'no fixed run', fontsize=7, color='#A32926')
        ax.scatter([], [], s=36, marker='x', color='#138B68', label='Fixed: selected only')
        ax.set_title(LABELS[domain] + (' (3 seeds)' if domain == 'synthetic' else ' (2 windows)'))
        ax.set_xlabel('Minimum full-original reconstruction SNR (dB)')
        ax.set_yticks(y, ALGORITHMS)
        ax.set_xlim(0, 46)
        ax.set_ylim(len(ALGORITHMS)-.4, -.6)
        ax.grid(axis='x', alpha=.2)
    axes[0].legend(loc='lower left', fontsize=8, frameon=False)
    fig.suptitle('LFSR application calibration: 65 selected fixed rows / 77 full-grid rows\nBasis + policy changes; no held-out or FPGA qualification', fontsize=12)
    figure = OUT / 'lfsr_application_snr.png'
    fig.savefig(figure, dpi=170)
    plt.close(fig)
    verification = {'complete': True, 'schema': 'v4-application-tuning-verification-v1',
        'summarizer_sha256': sha(Path(__file__)), 'studies': provenance,
        'unittest_count': test_count, 'test_log_sha256': sha(log_path),
        'test_source_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted((ROOT/'verification/v4').glob('test_*.py'))},
        'current_models_match_new_studies': True, 'current_model_sha256': model_hashes,
        'selected_fixed_rows': 65, 'full_grid_rows': 77, 'unselected_float_rows': 12,
        'unselected_float_below_snr20': unselected_below_floor,
        'unselected_float_at_or_above_snr20_but_shared_policy_not_selected': unselected_above_floor,
        'gate_counts_over_selected65': counts, 'combined_pass_over_full77': counts['combined'],
        'LS_summary': ls_summary, 'worst_relative_quality': worst,
        'fixed_higher_snr_rows': improved,
        'selected_policy_numerical_costs': costs,
        'per_algorithm_domain': table, 'fixed_failures': failures,
        'unselected': [{k: r[k] for k in ('case', 'algorithm', 'domain', 'recipe_id', 'policy', 'full_original_quality', 'centered_original_quality', 'no_numeric_fault', 'capacity_eligible')} for r in unselected],
        'fixed_status_counts': dict(Counter(r['fixed_result'].get('status') for r in fixed_rows)),
        'artifacts_sha256': {markdown.relative_to(ROOT).as_posix(): sha(markdown), figure.relative_to(ROOT).as_posix(): sha(figure)},
        'heldout_qualified': False, 'convergence_qualified': False, 'RTL_qualified': False,
        'raw_PhiPsi_hardware_qualified': False, 'production_bits_frozen': False}
    (OUT / 'application_tuning_verification.json').write_text(json.dumps(safe(verification), indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({'selected_fixed_rows':65, 'combined_pass':counts['combined'], 'full_grid_rows':77, 'unselected':12, 'LS':ls_summary}, ensure_ascii=False))


if __name__ == '__main__':
    main()
