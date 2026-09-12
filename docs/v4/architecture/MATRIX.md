# Hợp đồng matrix image v4

**Phạm vi: image reference hai orientation đang chạy trong Python.** Quyết định
phần cứng đã mở lại để so với [một copy đọc hai hướng](MATRIX_TRADEOFF.md) và
[operator tự sinh theo mô hình đo](GENERATED_OPERATOR.md). File này không định
nghĩa ABI của các candidate mới và không chốt hai-copy cho RTL.

Tài liệu này khóa giao diện đóng gói ma trận cho baseline v4. Đây là hợp đồng
host/compiler và verification; chưa phải RTL hay quyết định độ rộng số cuối.

Giải thích từ ví dụ tín hiệu tới bộ nhớ trên board:
[ZCU106 walkthrough](ZCU106.md). Tài liệu dưới đây giữ chi tiết giao diện image.

## Quyết định baseline

Baseline là ma trận dense `A ∈ R^(M×N)` được host cung cấp theo domain đã ghi
trong manifest. Nếu nguồn có dạng `A = Phi Psi`, host tính đầy đủ tích thực
`Phi @ Psi` trước, rồi gọi đúng một phép lượng tử hóa theo
`Profile.coefficient`. `Phi`, `Psi` không được lượng tử hóa riêng rồi nhân lại.
Điều này giữ raw measurement identity: với `Phi=I`, raw `A` sau lượng tử hóa
phải giống hệt lượng tử hóa trực tiếp `Psi`.

`matrix_kind` hiện chỉ nhận giá trị `dense`. Một backend Bernoulli sinh trực
tiếp có thể được thêm sau với kind và provenance riêng. Không dùng các dấu
Bernoulli để giả làm tích `Phi Psi`, cũng không phát hành kind cho backend chưa
có code và test.

Profile phải là `models.v4.fixed.Profile`; coefficient format lấy đúng từ
`profile.coefficient`. Width và số fractional vẫn là candidates của numerical
gate. Bộ đóng gói không chọn width thay cho gate chất lượng.

## API host

```python
image = build_matrix_image(
    A_real, profile,
    source_domain="raw_measurement",
    source_tag="dataset/hash-or-calibration-id",
)
image = build_composed_matrix_image(
    Phi, Psi, profile,
    source_domain="physical_signal",
    source_tag="dataset/hash-or-calibration-id",
)
image.validate()
image.write_bank_images("reports/v4/matrix_example")
```

`compose_operator(Phi, Psi)` chỉ trả tích thực để kiểm tra độc lập; nó không
lượng tử hóa. `build_matrix_image` kiểm tra shape hai chiều, finite values,
profile và source metadata. `Arithmetic.quantize` chạy một lần trên toàn A.
Mọi saturation là lỗi load, kể cả một phần tử vượt signed range. Sau khi
lượng tử hóa, mỗi column phải có ít nhất một raw coefficient khác zero; column
zero hoặc column bị làm tròn thành zero là lỗi rõ ràng, không bị nạp âm thầm.

## Hai orientation resident

Cùng một ma trận integer `A_q` được đưa qua hai instance của `MatrixLayout`:

```text
layout(A):          rows=M, columns=N, transpose=False
layout(transpose_A): rows=M, columns=N, transpose=True
bank    = (output + 8*reduction) % 32
address = (output // 32) * reduction_count + reduction
```

`A` có output `M`, reduction `N`; `transpose_A` có output `N`, reduction `M`.
Do đó đây là hai layout vật lý khác nhau của cùng coefficient set, không phải
hai lần tính/rounding khác nhau. Cả hai đều có 32 bank single-read.

Mỗi bank có depth `ceil(output_count/32)*reduction_count`. Output tail được
pad tới nhóm 32 và mọi ô tail được ghi zero rõ ràng. Ô coefficient hợp lệ
không được là `None`; thiếu ô, sai depth, sai signed width, alias địa chỉ hoặc
tail khác zero đều làm validation fail. `unpack("A")` trả ma trận M×N và
`unpack("transpose_A")` trả ma trận N×M; điều kiện bắt buộc là:

```text
unpack(A) == A_q
unpack(transpose_A) == transpose(A_q)
```

Validator dựng inverse address map và kiểm tra bijection đúng toàn bộ
`M*N` coefficient. Manifest hash là SHA-256 của dimensions và raw integer
matrix với JSON canonical (sorted keys, separators không có whitespace).

## Signed hex và manifest

Mỗi bank image có đúng `bank_depth` dòng. Mỗi dòng là số hex lowercase đủ
`ceil(width/4)` chữ số, mã signed two's-complement của raw coefficient. Các
bit cao không thuộc width bị từ chối. Manifest duy nhất là `manifest.json`;
nó ghi schema, matrix hash, `matrix_kind`, source domain/tag, dimensions,
profile/coefficient numeric format, và cho từng orientation:

```text
bank_count, bank_depth, bank_words,
payload_words, payload_bits, payload_bytes,
padded_bits, padded_bytes
```

`payload_bytes` dùng số bit coefficient thực (không tự ý làm tròn mỗi word
thành một byte width khác); `padded_bytes` tính cả 32-bank tail. Ví dụ
`M=128, N=1024, coefficient width=18` có 131072 words ở mỗi orientation và
`128*1024*18/8 = 294912` payload bytes mỗi orientation, tổng resident payload
**589824 bytes = 576 KiB**. Đây là payload accounting, chưa phải BRAM tile
granularity hay DMA framing.

`read_matrix_image(directory, profile)` (nếu dùng) chỉ nhận `manifest.json`
và đúng 64 bank files là direct children với tên canonical. Missing/extra
file, duplicate hoặc path traversal trong manifest, sai depth/hex/hash,
uninitialized coefficient/tail, và A/AT không transpose đều fail. Import dùng
raw integers đã đọc; không quantize lần hai.

## Support gather và chi phí baseline

Khi support ordered `j[s]`, baseline rebuild tách source resident stores và
destination support stores, chạy hai pass đầy đủ, không overlap với compute
trên cùng store:

```text
create A_S:    P_forward  = S * ceil(M/32)
create A_S^T:  P_transpose = S * ceil(M/4)
```

Forward đọc 32 rows mỗi issue theo bank rotation. Transpose chỉ có bốn read
bank hợp lệ cho fixed output và ghi bốn words mỗi issue; không tuyên bố
transpose 32 words/cycle từ single-read bank. Với `M=128,S=8`, payload issue
count là `32 + 256 = 288`, chưa tính synchronous startup/drain, index reads,
context/control bubbles và arbitration. Direct forward cộng packed transpose
là ablation bắt buộc; cache chỉ có lợi sau khi tính đủ preparation và reuse.

## Rank, unit column và normalization

Matrix loader phải ghi rank/degeneracy metadata trong report kiểm chứng. Column
zero bị reject ở load; rank thiếu hoặc dependent columns không bị biến thành
rank đầy đủ bằng padding. Unit-column/identity cases là correctness vectors:
chúng kiểm tra mapping, signs, transpose và raw measurement identity độc lập
với quality application.

Nếu chuẩn hóa `A=A0*C^-1` để cân bằng column norms, solver coordinates đổi
`z=Cx`. Với objective L1 gốc, penalty đúng là
`lambda * sum_j(|z_j|/c_j)`; bỏ trọng số rồi gọi cùng objective là sai. Manifest
phải ghi standardized coordinate hoặc physical coordinate và normalization
tag. Norms dùng để normalized ranking phải tính từ chính `A_q`, không từ float
matrix trước quantization.

Các thông tin rank, normalization, support cache key và numerical profile phải
được giữ cùng source hash trong report. Chúng không làm thay đổi quy tắc rằng
hai orientation được đóng gói từ đúng một `A_q`.
