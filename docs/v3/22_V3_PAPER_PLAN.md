# 22 - V3 paper plan (nâng cấp paper CSR lên kiến trúc v3)

Ngày lập: 2026-08-27. Quyết định đã duyệt: **hướng B** — không nộp tiếp bản
thảo v2, viết lại paper trên kiến trúc v3. Bản thảo v2
(`CSR__A_Reconfigurable_Architecture_..._Copy_ (6).pdf` ở repo root) trở thành
**baseline so sánh nội bộ**, không phải khung sườn.

Quy tắc tối cao: mọi con số trong paper phải trace được về một file evidence
trong `reports/v3/`; không claim vượt bằng chứng (rule doc 13 §6 áp dụng cho
cả paper).

## 1. Câu chuyện và tiêu đề

Câu chuyện chính: **tám thuật toán sparse recovery là tám chương trình context
do compiler sinh, chạy trên một CGRA hai cluster 4x4 dùng chung một PC**, với
các cơ chế mới ở tầng thực thi: guaranteed-commit elastic-static execution
(N1), load-time context certification + capability fail-closed (N2),
candidate-symbol capture trên generated-Phi stream (N3), transactional sparse
state (N5) và certificate-cadence control (N4). Novelty nằm ở **ngữ nghĩa
commit/chứng thực và đồng thiết kế compiler-fabric**, không nằm ở interconnect
(rule doc 15).

Tiêu đề ứng viên (chọn khi chốt venue):

1. "A Context-Programmed CGRA with Certified Commit Semantics for
   Multi-Algorithm Compressive Sensing Recovery"
2. "Guaranteed-Commit Context Execution for Eight Sparse Recovery Algorithms
   on a Dual-Cluster CGRA with Generated Sensing Matrices"
3. "Certify-then-Replay: Load-Time Certified Context Programs for
   Multi-Algorithm Compressive Sensing on FPGA"

## 2. Contribution map

| C | Nội dung | Novelty | Evidence hôm nay | Còn thiếu | Gate |
| --- | --- | --- | --- | --- | --- |
| C1 | Guaranteed-commit elastic-static context machine | N1 | RTL M3 + FORMAL/directed PASS | trace end-to-end trên operator thật | M8 |
| C2 | Load-time certification + capability fail-closed | N2 | certifier M3/M4/M5; `CAPABILITY_OWNERSHIP_STATUS` 2026-08-26 | negative campaign trên harness tích hợp | M8 |
| C3 | Candidate-symbol capture trên generated Phi | N3 | M7 leaf (cache capture/promote/replay) | TOP-K insert path | M9a/M9b |
| C4 | Certificate-cadence control | N4 | M0 study (**phải re-run sau Gate A** — số hiện tại đứng trên latency cũ) | RTL M10 | M10 |
| C5 | Transactional sparse support state | N5 | contract doc 21 | RTL M9b | M9b |
| C6 | Compiler chain typed SSA / MMG / bank allocation sinh context image | — | M3.5/M3.6 evidence đầy đủ | kernel correlation (chờ M9a) | M8 |

N6 (speculative phase overlap) chỉ xuất hiện trong Future work — không claim.

## 3. Related work — hai trục định vị

**Trục CGRA** (bảng so control paradigm): ADRES-class static modulo-scheduled;
STRELA full-elastic; SNAFU ordered-dataflow hybrid; HyCUBE/Morpher multi-hop;
CGRA-ME/OpenCGRA/Pillars framework. V3 = static modulo-scheduled + elastic
chỉ tại biên stream/resource + **N1 bypass có chứng minh compiler** + **N2
certification mà không framework công khai nào có** (mapper được tin tuyệt
đối trong mọi framework đã review).

Điều kiện trước khi viết section này: mở rộng
`reports/v3/CGRA_OPEN_SOURCE_IMPLEMENTATION_REVIEW.md` với review thật
RipTide, SNAFU, Pillars, STRELA (hiện ADRES chỉ là "class", các tên kia vắng
mặt — đang over-claim breadth, xem re-audit P1).

**Trục CS accelerator**: Ge QR-OMP (TVLSI'19), Bai OMP+AMP (ICECS'12),
Roy incremental-GE OMP (TIM'20), và **CSR v2 của chính nhóm** làm baseline
đa thuật toán trực tiếp. V3 khác biệt: matrix-free restricted CGLS +
certificate thay Gaussian elimination; Threefry generated Phi + capture thay
LFSR; D18F14/S27F19/A62 có width study thay 24-bit ad-hoc; N=1024/M=128/K=32
thay 256/64/16.

## 4. Outline ↔ nguồn nội dung ↔ trạng thái

| Section | Nguồn repo | Trạng thái |
| --- | --- | --- |
| I. Introduction | mới; motivation giữ từ v2 paper | viết được ngay |
| II. Background + kernel sharing | Table I của v2 paper nâng cấp theo doc 02 (8 thuật toán, phase chuẩn) | viết được ngay |
| III. Architecture: context machine 684-bit, 2x4x4 shared PC, stream/scratchpad, sidecar 16 lane, Phi Threefry | doc 00/01/06/08/09 + leaf OOC M5/M6/M7 | viết được ngay |
| IV. Compiler + certification (N2, C6) | doc 07/08, M3.5/M3.6 status, capability ownership | viết được ngay |
| V. Numeric contract + restricted refinement + cadence (N4) | doc 03/11, `FIXED_POINT_SELECTION_STUDY`, certificate study | phần cadence chờ Gate A re-run |
| VI. Results | xem §5 | gated |
| VII. Related work | §3 | sau khi mở rộng review |
| VIII. Conclusion + future (N6, K64 seam, M13 P&R) | doc 09/15 | viết được ngay |

## 5. Results plan và milestone gating

| Bảng/Hình | Nguồn dữ liệu | Gate |
| --- | --- | --- |
| Resource/timing từng macroblock (LUT/FF/DSP/BRAM/WNS OOC) | `reports/v3/m5/m6/m7_vivado` + status | **có ngay** |
| Integrated control spine + phase trace | M1-M4 harness status | **có ngay** |
| Correlation checkpoint: cycle RTL == compiler schedule | M8 exit gate | Gate C (doc 18) |
| Bảng cycle 8 thuật toán (thay Table II v2; N=1024/M=128/K=32, ba profile strict/balanced/fast) | M11 trace | M11 |
| Reconstruction quality (thay Table III v2; K32 golden + RTL trace) | M11 | M11 |
| MRI source-domain quality: Shepp-Logan, BrainWeb normal/MS sweep, fastMRI official manifest | `reports/v3/mri_paper_quality_gate`, `reports/v3/brainweb_sweep`, `reports/v3/fastmri_source_quality_gate` | BrainWeb measured; fastMRI remains gated until official HDF5 evidence |
| So sánh CSR v2 vs v3 (quy đổi cycle/resource cùng bài toán) | v2 paper + M11 | M11 |
| Fig. 1 nâng cấp thành scatter dữ liệu thật (x = cycles/iteration đo được, y = reconstruction SNR đo tại một mức measurement-SNR cố định) — thay bản ordinal | M11 trace + quality run | M11; phụ thuộc đóng anomaly IHT=GP của Table III v2 |
| Cadence optimization (CoSaMP/SP/HTP % cycle) | cycle sim **sau khi re-run measured** | Gate A |
| Full P&R ZCU106 | M13 | chỉ cần cho journal; conference dùng OOC + ghi rõ |

**Minimum publishable increment**: sau M8 có thể nộp workshop/short paper
(architecture + compiler + N1/N2 + correlation checkpoint đo thật). Full
conference paper sau M11. Không chờ M13 trừ khi nhắm journal.

## 6. Honesty rules riêng cho paper

- FORMAL viết là "property elaboration + simulated assertions", không viết
  "formally proven" (rule doc 13 §6).
- RIP wording theo doc 12: "satisfies RIP with high probability + empirical
  seed qualification", không claim RIP deterministic.
- Nhãn measured/modeled theo `timing_status` trong architecture
  configuration; số modeled không được xuất hiện trong bảng results.
- Số certificate-cadence hiện hành (CoSaMP -30.3%...) **bị cấm dùng** cho tới
  khi cycle simulator chạy lại với measured latency (Gate A, doc 18).
- Không claim novelty interconnect; không claim K64.
- Không claim direct raw-k-space/Fourier RTL hoặc clinical equivalence. BrainWeb
  là simulated MRI; fastMRI chỉ được ghi là real-MRI source-domain evidence sau
  khi manifest official/checksum/slice coverage pass. Protocol authority:
  `docs/v3/25_MRI_EVALUATION_PROTOCOL.md`.

## 7. Việc làm ngay, không chờ RTL

1. **Đóng nghi vấn IHT/GP của paper v2**: Table III v2 có hai hàng giống hệt
   (10.63/22.33/28.65/31.46) — xác định lỗi số liệu hay bug code path SDK v2.
   Ảnh hưởng trực tiếp bảng so sánh v2-vs-v3 ở §5.
2. Sửa mâu thuẫn MRCA multiply (`MRCA2_ARCHITECTURE_REVIEW.md` vs doc 01/06)
   bằng supersession note — architecture section không được viết trên tài
   liệu tự mâu thuẫn.
3. Mở rộng CGRA review (RipTide/SNAFU/Pillars/STRELA) như §3.
4. Chốt venue để định dạng độ dài (quyết định của tác giả).
5. Dựng skeleton LaTeX: điền trước các section "viết được ngay" (§4) và bảng
   resource/timing "có ngay" (§5).
