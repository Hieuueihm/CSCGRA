"""Build the K=8 comparison from retained legacy evidence and frozen xsim runs."""
from pathlib import Path
import csv
import hashlib
import io
import json
import math
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'reports/v4/k8_comparison_20260909'
ALGORITHMS = ('OMP', 'CoSaMP', 'IHT', 'HTP', 'SP', 'GP', 'GOMP', 'MP')
EXTRA = ('FISTA', 'ADMM', 'PDHG')
V3 = 'reports/v3/m13_correctness_sweep_p1_selection_policy_regression_20260908'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    consumed = {}

    def read(name):
        data = (ROOT / name).read_bytes()
        consumed[name] = hashlib.sha256(data).hexdigest()
        target = OUT / 'sources' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return data.decode('utf-8-sig')

    read('scripts/v4/summarize_k8.py')
    legacy = json.loads(read('reports/v4/legacy_cycle_baselines_20260909/baselines.json'))
    configuration_audit = json.loads(read('reports/v4/k8_legacy_configuration_20260909.json'))
    read('reports/v4/k8_legacy_configuration_20260909.md')
    v2 = {r['algorithm']: r for r in legacy['records']
          if r['version'] == 'V2' and (r['m'], r['n'], r['k']) == (64, 256, 8)}
    assert set(v2) == set(ALGORITHMS)
    v3 = {}
    for row in csv.DictReader(io.StringIO(read(f'{V3}/results.csv'))):
        geometry = (int(row['m']), int(row['n']))
        if geometry not in ((64, 256), (32, 64)) or row['profile'] != 'strict_paper' or row['k'] != '8':
            continue
        algorithm = next(a for a in ALGORITHMS if a.lower() == row['algorithm'])
        assert row['outer_iteration_limit'] == '8'
        assert (*geometry, algorithm) not in v3
        log_name = f"{V3}/{Path(row['log']).name}"
        log = read(log_name)
        pattern = r'M13 E2E CASE PASS m=(\d+) n=(\d+) k=(\d+) algorithm=(\d+) profile=(\d+) cycles=(\d+)'
        expected = (*geometry, 8, ALGORITHMS.index(algorithm), 0, int(row['cycles']))
        assert row['status'] == 'PASS' and not re.search(r'^FAIL:', log, re.M), log_name
        assert expected in [tuple(map(int, x)) for x in re.findall(pattern, log)], log_name
        iterations = re.findall(r'M13 E2E ITERATIONS .*?actual=(\d+) expected=(\d+)', log)
        assert iterations, log_name
        v3[(*geometry, algorithm)] = dict(row, algorithm=algorithm,
            actual_outer=int(iterations[-1][0]), log=log_name,
            validation='CSV and raw PASS log agree; no FAIL line')
    assert len(v3) == 16
    assert len({r['source_bundle_hash'] for r in v3.values()}) == 1

    v4, suites = {}, []
    for m, n in ((64, 256), (32, 64)):
        folder = f'reports/v4/k8_m{m}_n{n}_rtl_20260909'
        summary = json.loads(read(f'{folder}/summary.json'))
        assert summary['status'] == 'PASS', folder
        assert not summary['changed_sources'] and not summary['untracked_imports'], folder
        cfg = summary['config']
        assert (cfg['rows'], cfg['columns'], cfg['scale'], cfg['sparsity'], cfg['outer']) == (m, n, 8192 if m == 64 else 11585, 8, 8)
        assert cfg['inner_limit'] == 24 and cfg['qr_refinements'] == 2
        for name, expected_hash in summary['source_sha256'].items():
            archived = ROOT / folder / 'source_snapshot' / name
            assert hashlib.sha256(archived.read_bytes()).hexdigest() == expected_hash, str(archived)
            if name.startswith(('rtl/v4/', 'compiler/v4/', 'models/v4/')):
                assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == expected_hash, name
        cases = summary.get('cases') or json.loads(read(f'{folder}/evidence.json'))
        for case in cases:
            assert (case['rows'], case['columns']) == (m, n)
            assert len(case['planted_support']) == 8
            assert case['scale_raw'] == cfg['scale']
            assert case['sparse_forward'] == (case['algorithm'] in ('MP','GP','IHT'))
            assert case['storage'] == ('D18F14' if case['algorithm'] in EXTRA else 'X24F20')
            policy = case['policy']
            assert policy['max_iterations'] == case['requested_outer_iterations']
            assert policy['step_size'] == .1
            if case['algorithm'] in EXTRA:
                assert (policy['regularization'],policy['pd_sigma'],policy['admm_rho'],policy['inner_max_iterations'],policy['inner_rtol']) == (.01,1.,1.,24,1e-4)
            else:
                assert (policy['sparsity'],policy['residual_atol'],policy['group_size'],policy['ls_normal_rtol']) == (8,1e-6,2,1e-4)
            assert all(k in case for k in ('solver_invocations','solver_refinement_count','maximum_ls_support','program_length','template_count','load_record_count'))
            key = (m, n, case['algorithm'], case['requested_outer_iterations'])
            assert key not in v4
            v4[key] = dict(case, evidence_folder=folder)
        assert all((m, n, a, 8) in v4 for a in ALGORITHMS + EXTRA)
        assert len({r['raw_phi_sha256'] for r in cases}) == 1
        assert len({r['raw_y_sha256'] for r in cases}) == 1
        suites.append(dict(folder=folder, summary=summary))

    def number(value):
        return f'{int(value):,}'

    def snr(case, kind='fixed'):
        metric = case['quality'][kind]
        return '∞' if metric['nmse'] == 0 else f"{metric['snr_db']:.2f}"

    def gate(case):
        quality = case['quality']
        fixed, floating = quality['fixed'], quality['floating']
        ratio = fixed['nmse']/floating['nmse'] if floating['nmse'] else (1.0 if fixed['nmse'] == 0 else float('inf'))
        loss = 10*math.log10(ratio) if ratio > 0 else -float('inf')
        absolute = max(fixed['nmse'], floating['nmse']) <= .01
        relative = loss <= .5 and ratio <= 1.10
        return absolute, relative, ratio, loss

    lines = ['# So sánh K=8: V2, V3 và v4', '',
        'Ngày 2026-09-09. **Hai bộ xsim mới chạy đủ 11 thuật toán**, thêm GOMP bốn vòng ở M64/N256.',
        'Mỗi bộ v4 dùng cùng ma trận, measurement và truth có đúng tám hệ số khác 0 cho tất cả thuật toán.',
        'Đây là benchmark có budget cố định và điều kiện dừng tự nhiên, chưa phải cycle tới cùng chất lượng trên dữ liệu held-out.', '',
        '## Đọc bảng đúng phạm vi', '',
        '- Cycle v4 tính từ accepted START đến DONE, gồm BUILD, QR/inner solve, scalar và result commit; loại cold Phi/program/Y preload và đọc kết quả của host.',
        '- V2 đếm seq_busy; V3 đếm engine_busy, gồm Phi runtime và result DMA. Seed, measurement operator, độ rộng bit, solver và điểm làm tròn khác nhau.',
        '- Vì vậy số cũ là mốc kiến trúc; không gán tỷ lệ speedup công bằng hoặc kết luận chất lượng tương đương từ bảng này.',
        '- V2 chỉ còn báo cáo signoff cho các cycle này; log gốc thiếu. Budget V2 được đối chiếu từ test hiện còn, chưa được xác nhận bằng source gốc của lượt đo. V3 dưới đây dùng một suite/source-bundle nhất quán, đã đối chiếu đủ 16 dòng CSV với log PASS.',
        '- Budget tám không có nghĩa luôn chạy tám vòng: ghi số vòng thực tế trong bảng. SP còn có solve khởi tạo ngoài bộ đếm outer; GOMP chọn hai atom mỗi vòng.', '',
        '## M=64, N=256, K=8', '',
        '| Thuật toán | V2 cycle / budget | V3 cycle / vòng thực | v4 cycle / vòng thực | v4 SNR fixed / float (dB) |',
        '|---|---:|---:|---:|---:|']
    for a in ALGORITHMS:
        old, previous, current = v2[a], v3[(64,256,a)], v4[(64,256,a,8)]
        lines.append(f"| {a} | {number(old['cycles'])} / {old['outer_limit']} | {number(previous['cycles'])} / {previous['actual_outer']} | {number(current['job_cycles'])} / {current['outer_iterations']} | {snr(current)} / {snr(current,'floating')} |")
    extra_gomp = v4[(64,256,'GOMP',4)]
    lines += ['', f"**GOMP budget bốn để bám V2:** v4 {number(extra_gomp['job_cycles'])} cycle, {extra_gomp['outer_iterations']} vòng thực, support {len(extra_gomp['accepted_support'])}, SNR fixed/float {snr(extra_gomp)}/{snr(extra_gomp,'floating')} dB.",
        'V2 không ghi riêng số vòng thực trong evidence còn giữ. Các dòng v4 chính dùng budget tám, gồm cả GOMP.', '',
        '## M=32, N=64, K=8', '',
        'Dùng cùng revision V3 như bảng trên; không trộn một số OMP từ revision khác vào suite cũ.', '',
        '| Thuật toán | V3 cycle / vòng thực | v4 cycle / vòng thực | v4 SNR fixed / float (dB) |',
        '|---|---:|---:|---:|']
    for a in ALGORITHMS:
        previous, current = v3[(32,64,a)], v4[(32,64,a,8)]
        lines.append(f"| {a} | {number(previous['cycles'])} / {previous['actual_outer']} | {number(current['job_cycles'])} / {current['outer_iterations']} | {snr(current)} / {snr(current,'floating')} |")
    lines += ['', '## Ba thuật toán bổ sung', '',
        'FISTA/ADMM/PDHG vẫn nhận cùng truth K=8. Chúng giải LASSO với regularization, không dùng K làm giới hạn support. Không có số V2/V3 trong các bộ đối chiếu.', '',
        '| Thuật toán | M / N | Cycle / vòng thực | SNR fixed / float (dB) | Status |',
        '|---|---|---:|---:|---|']
    for a in EXTRA:
        for m,n in ((64,256),(32,64)):
            r=v4[(m,n,a,8)]
            lines.append(f"| {a} | {m} / {n} | {number(r['job_cycles'])} / {r['outer_iterations']} | {snr(r)} / {snr(r,'floating')} | {r['status']} |")
    lines += ['', '## Cấu hình v4 đã thực thi', '',
        '| Thuộc tính | V2 signoff | V3 suite được chọn | v4 benchmark mới |',
        '|---|---|---|---|',
        '| Dữ liệu / accumulator | signed24 Q16 / ACC64 | D18F14, S27F19 / ACC62 | D18F14, C18F16, S27F22 / ACC64 |',
        '| Operator | LFSR, audit seed17, scale0.25 | Threefry, seed41 hoặc7, scale0.125 | LFSR32, seed0x12345678, scale gần 1/sqrt(M) |',
        '| Support LS | Normal equations có regularization, LDLT/factor cache | CGLS-style restricted refinement | Householder QR; tối đa hai correction |',
        '| Datapath | 4×8 PE và đường LS dùng chung | Hai4×4 PE, thêm các dịch vụ số học dùng chung | Hai4×4 PE; QR dùng cùng32PE, fold trung tâm |',
        '| SNR/NMSE cùng suite cycle | Không có | Không có | Fixed và float trên cùng quantized Phi/Y/truth |', '',
        'Cấu hình V2/V3 được đối chiếu từ nguồn còn giữ; đặc biệt V2 thiếu source archive gốc cho bảng cycle, nên không gán byte-level identity cho cấu hình suy ra từ test hiện có. Xem audit nguồn bên dưới.', '',
        '| M / N | Phi raw C18F16 | Norm cột | Seed Phi / truth | Truth K / budget |',
        '|---|---:|---|---|---|',
        '| 64 / 256 | ±8192 | 1 | 0x12345678 / 2229 | 8 / 8, thêm GOMP 4 |',
        '| 32 / 64 | ±11585 | xấp xỉ 1 | 0x12345678 / 2005 | 8 / 8 |', '',
        'LFSR32, A=Phi ở miền hệ số (Psi=I); một cache dấu tám bank, một B ghép 16 bank TDP. Hai array 4×4, đúng 32 PE; feeder bốn frame, hai block vector cache, hai read credits.',
        'D18F14/C18F16/S27F22/ACC64; tám greedy lưu X24F20, ba proximal lưu D18F14. Bit vẫn là candidate.',
        'MP/GP/IHT bật sparse_forward=True; gradient/correlation vẫn chạy toàn N. GP dùng rᵀq/qᵀq, cập nhật gradient trên support, cho phép chọn lại atom.',
        'R1/R4 dùng lựa chọn auto của compiler hiện hành; mỗi quyết định theo PC và cost estimate được lưu trong mapping_metadata. Đây không phải kết quả chứng minh mapping tối ưu; bảng cycle lấy từ xsim thật.',
        'Năm thuật toán có support LS dùng Householder QR, tối đa hai correction, giữ B gốc để kiểm nghiệm đã lưu. CoSaMP có thể yêu cầu 3K=24 cột, không ép mọi solve lên capacity 96.',
        'Greedy: residual_atol=1e-6, step_size=0.1 cho IHT/HTP, group_size=2, ls_normal_rtol=1e-4 trong fixture này. Ngưỡng này được giữ từ policy test, không thay thế calibration ứng dụng dùng ngưỡng khác.',
        'Proximal: lambda=0.01, step=0.1, PDHG sigma=1, ADMM rho=1, inner limit=24 và inner_rtol=1e-4. Toàn bộ policy và program/template được lưu trong evidence.',
        'Truth sinh cố định một lần cho mỗi geometry, chuẩn hóa measurement peak về 0.5 trước D18; gain này được lưu như preprocessing của fixture, không chứng nhận đường chuẩn hóa host trên board.', '',
        '## Chất lượng và công việc thực tế của từng ca', '',
        'PASS RTL nghĩa là bit-exact X/residual/support/status và PC trace với model/VM. Cột 20 dB yêu cầu cả fixed và float đạt; cột relative yêu cầu SNR loss≤0.5 dB và NMSE ratio≤1.10. Chúng là các kiểm riêng.', '',
        '| M / N | Thuật toán / budget | Support cuối | QR calls / correction | SNR loss (dB) | NMSE fixed / float | Ratio | ≥20 dB | Relative | Status |',
        '|---|---|---:|---:|---:|---:|---:|---|---|---|']
    flat=[]
    for key,r in sorted(v4.items()):
        m,n,a,budget=key
        absolute,relative,ratio,loss=gate(r)
        q=r['quality']
        lines.append(f"| {m} / {n} | {a} / {budget} | {len(r['accepted_support']) if a not in EXTRA else 'không giới hạn K'} | {r['solver_invocations']} / {r['solver_refinement_count']} | {loss:.6g} | {q['fixed']['nmse']:.6g} / {q['floating']['nmse']:.6g} | {ratio:.6g} | {'PASS' if absolute else 'FAIL'} | {'PASS' if relative else 'FAIL'} | {r['status']} |")
        flat.append(dict(m=m,n=n,algorithm=a,budget=budget,cycles=r['job_cycles'],actual_outer=r['outer_iterations'],
            published_support_count=0 if a in EXTRA else len(r['accepted_support']),
            model_support_or_nonzero_count=len(r['accepted_support']),status=r['status'],fixed_snr_db=q['fixed']['snr_db'],
            float_snr_db=q['floating']['snr_db'],fixed_nmse=q['fixed']['nmse'],float_nmse=q['floating']['nmse'],
            snr_loss_db=loss,nmse_ratio=ratio,absolute_quality_pass=absolute,relative_quality_pass=relative))
    lines += ['', '## Program, context và support LS thực', '',
        'Program words là độ dài image nạp; retired instructions là số lệnh thực thi, có tính vòng lặp. Hai số khác nhau. Số bước CG chỉ áp dụng ADMM và cộng trên các outer đã commit.', '',
        '| M / N | Thuật toán / budget | Program words | Templates | Load records | Lệnh thực thi | S lớn nhất của QR | Tổng bước CG đã commit |',
        '|---|---|---:|---:|---:|---:|---:|---:|']
    for (m,n,a,budget),r in sorted(v4.items()):
        lines.append(f"| {m} / {n} | {a} / {budget} | {r['program_length']} | {r['template_count']} | {r['load_record_count']} | {number(r['retired_instructions'])} | {r['maximum_ls_support']} | {r['total_committed_inner_iterations']} |")
    lines += ['', '## Chi phí dịch vụ, drain và preload', '',
        'Các nhóm service bên dưới không chồng lấp trong program controller; phần còn lại gồm control và publication ngoài service. GEMV gồm Phi và B. Số cycle toàn testbench không được dùng làm cycle thuật toán.', '',
        '| M / N | Thuật toán / budget | GEMV | Factor transfer | Kernel còn lại | Scalar | BUILD | Drain/commit cuối | Tổng START–DONE |',
        '|---|---|---:|---:|---:|---:|---:|---:|---:|']
    for (m,n,a,budget),r in sorted(v4.items()):
        totals=r['cycle_profile']['service_totals']
        group={'gemv':0,'factor':0,'kernel':0,'scalar':0,'build':0}
        for name,s in totals.items():
            kind,op=name.split(':')
            category=('gemv' if op=='1' else 'factor' if op in ('13','14','15') else 'kernel') if kind=='KERNEL' else kind.lower()
            group[category]+=s['clocks']
        lines.append(f"| {m} / {n} | {a} / {budget} | {number(group['gemv'])} | {number(group['factor'])} | {number(group['kernel'])} | {number(group['scalar'])} | {number(group['build'])} | {number(r['cycle_profile']['result_drain_clocks'])} | {number(r['job_cycles'])} |")
    lines += ['', 'Preload chưa được đo thành một latency DMA độc lập. Evidence giữ mốc stdout Phi-ready/program-loaded/START và tổng overhead của fixture; overhead đó còn gồm kiểm tra kết quả và hai job nên không gọi là cold-preload latency.',
        '100 MHz là mục tiêu: nếu đạt timing thì 100,000 cycle tương ứng 1 ms. Chưa synth/impl v4; không biến phép quy đổi này thành Fmax/throughput đã đo.', '',
        '## Kết luận từ bộ K8 này', '',
        'Đường Phi đã giảm cycle, nhưng QR hiện còn nhiều chi phí kernel vector, copy/range, factor và control. Các ca OMP/CoSaMP/HTP trong bảng chưa cho phép kết luận kiến trúc đã cân bằng so với mốc cũ.',
        'GP đạt trên20dB trên hai fixture này với gradient và line search giữ đúng. MP/IHT/HTP và ba proximal có ca dưới20dB ngay cả float ở budget tám; không quy các ca đó thành lỗi RTL hay cho rằng tăng bit sẽ tự giải quyết.',
        'OMP/GOMP/CoSaMP/SP có SNR cao ở các fixture này, nhưng outer tolerance1e-6 và chính sách dừng còn ảnh hưởng rất lớn tới số vòng. Chưa đo cycle tối thiểu đạt20dB; không tự giảm vòng để làm đẹp bảng.', '',
        '## Nguồn và giới hạn so sánh', '',
        '- [Audit cấu hình V2/V3](k8_legacy_configuration_20260909.md): bit, operator, solver, GP/CoSaMP khác biệt và timing evidence.',
        f'- [Suite V3 dùng cho cả hai bảng](../v3/m13_correctness_sweep_p1_selection_policy_regression_20260908/results.csv): một source bundle, natural stops. Bộ forced-eight cũ có OMP CSV PASS nhưng log FAIL; không dùng dòng đó hoặc ghép revision.',
        '- [M64/N256: xsim và source đóng băng](k8_m64_n256_rtl_20260909/summary.json).',
        '- [M32/N64: xsim và source đóng băng](k8_m32_n64_rtl_20260909/summary.json).',
        '- [JSON đầy đủ](k8_comparison_20260909/comparison.json), [CSV v4](k8_comparison_20260909/v4_cases.csv), [hash nguồn báo cáo](k8_comparison_20260909/source_manifest.json).',
        '- [GP contract](../../docs/v4/architecture/GRADIENT_PURSUIT.md), [pipeline](../../docs/v4/architecture/OPERATOR_PIPELINE.md).', '',
        'V2 GP mặc định là full-gradient/IHT-like và CoSaMP có delta canonical đã ghi nhận. V3 GP là restricted gradient nhưng có nhánh dùng ||g_S||² thay rᵀq; không mặc nhiên bit-exact trong fixed point.',
        'Không chọn thuật toán thắng bằng trung bình. Cần dùng workload/policy đạt chất lượng, cùng operator/input/precision và cùng ranh giới đếm trước khi kết luận speedup cho paper.', '']
    (ROOT/'reports/v4/K8_COMPARISON.md').write_text('\n'.join(lines),encoding='utf-8')
    payload=dict(scope='Measured K8 cycles with explicit configuration and quality, not equal-work/equal-quality speedup',
        v2=list(v2.values()),v3=list(v3.values()),configuration_audit=configuration_audit,v4_cases=list(v4.values()),suites=suites)
    (OUT/'comparison.json').write_text(json.dumps(payload,indent=2)+'\n',encoding='utf-8')
    with (OUT/'v4_cases.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(flat[0]))
        writer.writeheader();writer.writerows(flat)
    (OUT/'source_manifest.json').write_text(json.dumps(consumed,indent=2)+'\n',encoding='utf-8')
    print(f'K8 comparison: {len(v4)} verified v4 cases, {len(v3)} verified V3 rows, {len(v2)} retained V2 rows')


if __name__=='__main__':
    main()
