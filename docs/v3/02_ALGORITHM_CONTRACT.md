# v3 - Paper algorithm contract

Trạng thái: **paper mathematical golden đã khóa; hardware golden đã có model
và phase trace; AXI4-Lite shell đã có RTL, algorithm datapath chưa triển khai**.

## 1. Chuỗi nguồn sự thật

```text
paper gốc
  -> models/v3/paper.py          floating-point mathematical golden
  -> models/v3/hardware.py       D18F14/S27F19/A62 bit-accurate model
  -> phase golden JSON.gz
  -> RTL phase dump
  -> exact phase comparator
```

RTL, testbench và hardware model không được định nghĩa lại thuật toán. Thay đổi
phase, support rule, LS semantics hoặc stop policy phải sửa paper contract và
regenerate golden trước.

## 2. Nguồn và phase normative

Citation đầy đủ, DOI và link open-access của cả tám nguồn được lưu tập trung tại
[`references/README.md`](references/README.md).

| Algorithm | Nguồn | Phase một iteration |
| --- | --- | --- |
| OMP | [Tropp & Gilbert](https://doi.org/10.1109/TIT.2007.909108) | proxy -> select new atom -> LS trên full support -> residual |
| CoSaMP | [Needell & Tropp](https://doi.org/10.1016/j.acha.2008.07.002) | proxy -> Top-2K -> union -> LS union -> prune K -> residual |
| IHT | [Blumensath & Davies](https://doi.org/10.1016/j.acha.2009.04.002) | gradient -> `x+mu*A^T*r` -> hard threshold K -> residual |
| HTP | [Foucart](https://doi.org/10.1137/100806278) | `x+mu*A^T*r` -> Top-K support -> LS support -> residual |
| SP | [Dai & Milenkovic](https://doi.org/10.1109/TIT.2009.2016006) | explicit initialization; proxy -> union -> LS 2K -> prune K -> LS K -> residual check |
| GP | [Blumensath & Davies](https://doi.org/10.1109/TSP.2007.916124) | proxy -> select/reselect -> restricted gradient -> exact line search -> update residual |
| gOMP | [Wang, Kwon & Shim](https://doi.org/10.1109/TSP.2012.2218810) | proxy -> select L new atoms -> LS full support -> residual |
| MP | [Mallat & Zhang](https://doi.org/10.1109/78.258082) | normalized proxy -> select/reselect -> rank-one projection -> residual |

Tie-break bổ sung cho hardware determinism: magnitude bằng nhau thì index nhỏ
hơn thắng. Đây không thay đổi tập nghiệm khi paper không quy định tie.

Profile v3 dùng đúng các biến thể `IHT_mu` và `HTP_mu` được paper mô tả. `mu`
là gradient normalization/step size nằm trong từng case manifest; nó không phải
regularization và không đi vào normal equation của LS.

## 3. Những điểm đã sửa so với v2 golden

### CoSaMP

Paper giữ trực tiếp `x = H_K(b)` sau khi LS trên union. Không có LS/debias thứ
hai sau prune. Nếu cần debiased CoSaMP thì phải đặt algorithm ID khác; không
được gọi là CoSaMP paper profile.

### SP

SP có initialization riêng: Top-K từ `A^T y`, LS và residual ban đầu. Sau mỗi
iteration, nếu residual không giảm thì rollback về state trước. Không gộp init
thành iteration 0 thông thường.

### GP

GP cho phép atom đã có trong support được chọn lại. Re-selection thực hiện thêm
gradient step trên support hiện tại. Cấm re-selection sẽ đổi thuật toán.

### gOMP

Mỗi iteration chọn đúng `L` atom mới. Với `L=2`, paper cho phép tối đa
`min(K, floor(M/L))` iteration, do đó support worst-case là `2K=64`. Không trim
group cuối để ép support về K.

### MP

Selection dùng normalized correlation. Hardware Bernoulli v3 có equal-norm
columns nên comparator magnitude raw là tương đương; hardware model reject
matrix profile có column norms khác nhau.

## 4. LS contract

Paper golden dùng ordinary least squares/pseudoinverse, không regularization.
Hardware golden revision 3 dùng matrix-free restricted CGLS với `lambda=0` và
post-D18 normal-residual certificate.

Target hardware authority dùng unified restricted refinement trong
[11_LS_SOLVER_ARRAY_BLUEPRINT.md](11_LS_SOLVER_ARRAY_BLUEPRINT.md). Strict
profile chạy tới post-D18 certificate; bounded profile có golden/manifest riêng.
Max-iteration, breakdown, divide-by-zero, saturation hoặc overflow phát rollback;
x/support/residual cũ không được commit. Micro-phase chỉ được đổi sau numerical
sweep, end-to-end review và regenerate hardware golden/manifest.

Profile `lambda>0` là variant khác và phải dùng explicit refinement profile.
Nó không được dùng để tạo paper-equivalent golden.

## 5. Stop policy

Paper thường để stop criterion cho implementation. Golden tách stop policy ra
khỏi công thức:

- `max_iterations`;
- `residual_atol`;
- `step_size` cho IHT/HTP;
- `group_size` cho gOMP;
- SP reject-on-non-decrease.

Mỗi giá trị nằm trong case manifest. RTL phải đọc cùng run configuration hoặc dùng
compile-time profile trùng manifest.

## 6. Phase-golden interface

Mỗi phase record chứa:

- `seq`, `iteration`, `name`;
- `support`, `candidates`;
- các vector output của phase;
- scalar/certificate;
- cumulative numeric fault counters.

Hardware trace là exact signed integer. RTL testbench sẽ dump cùng schema và
so bằng:

```powershell
py -3 scripts/golden/compare_v3_phase_trace.py `
  --golden verification/v3/golden/m16_n24_k4_seed1.hardware.json.gz `
  --observed <rtl-phase-dump.json>
```

Mỗi macro-phase của paper xuất hiện nguyên tên và đúng thứ tự trong hardware
trace. Target micro-phase của một macro LS/refinement là:

```text
REFINEMENT_BEGIN -> REFINEMENT_STEP* -> REFINEMENT_CERTIFICATE
-> REFINEMENT_COMMIT/ROLLBACK -> macro LS
```

Golden restricted-refinement sau M0 là immutable input cho RTL debug; chỉ đổi
khi paper/hardware authority đổi và manifest được regenerate/review riêng.

Vì vậy có thể check riêng arithmetic/solver ở micro-phase, rồi check decision
và state transition ở macro-phase mà không trộn hai mức abstraction.

Golden được sinh/check bằng:

```powershell
py -3 scripts/golden/generate_v3_phase_golden.py --suite smoke
py -3 scripts/golden/generate_v3_phase_golden.py --suite smoke --check
py -3 scripts/golden/generate_v3_phase_golden.py --suite scale
py -3 scripts/golden/generate_v3_phase_golden.py --suite scale --check
```

Manifest giữ SHA-256 của paper model, hardware model, generator và từng output;
chỉnh tay phase file sẽ làm check fail. Generator cũng từ chối positive golden
nếu phase sequence đứt, support lỗi, có numeric fault hoặc `REFINEMENT_ROLLBACK`.

Suite `scale` dùng budget hữu hạn ghi rõ trong manifest để kiểm tra conformance
ở `N=1024, K=32`; đây không phải tuyên bố rằng mọi thuật toán phải exact-recover
trong đúng K iteration. Recovery/cycle benchmark sẽ có policy riêng theo từng
algorithm và không được dùng để đổi paper semantics.

## 7. Assertion bắt buộc cho RTL

- phase order đúng algorithm ID;
- CoSaMP có đúng một LS trước prune;
- SP không commit iteration có residual không giảm;
- GP/MP cho phép re-selection;
- gOMP support capacity tối thiểu `L*K`;
- LS không commit khi certificate fail;
- score tie chọn index thấp hơn;
- support không duplicate;
- numeric fault làm reconstruction fail, không chỉ tăng telemetry.
