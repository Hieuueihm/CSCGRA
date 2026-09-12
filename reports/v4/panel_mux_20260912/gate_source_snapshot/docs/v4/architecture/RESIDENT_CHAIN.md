# Resident operand sequence implementation contract

Đợt tiếp theo đã bổ sung đọc range, retire-time fetch, GEMV group prefetch và panel hẹp. Xem [báo cáo hiện hành](../../../reports/v4/context_stream_final_20260910/README.md) và [hợp đồng range](RANGE_TEMPLATE.md). Các quy tắc ownership/commit dưới đây vẫn giữ nguyên.

The installed resident QR closure keeps Householder arithmetic, loaded program revision2, exactly two 4×4 PE arrays (32 PEs), one shared vector pool, and existing fault/cancel behavior. It does not add a QR FSM, public Q, vector/factor RAM, PE, multiplier, AXI/MMIO/DMA, or CPU register map. The scalar RF32×64 belongs to the loaded program sequencer.

Prefix reuse is allowed only after the loaded program proves an ordered support prefix and unchanged Phi/RHS/job identity. A nonprefix, support shrink, or reorder forces INIT. Fault, cancel, and identity failure invalidate the affected factor state according to the factor ownership contract.

## Phase A: installed generic block ownership

Sequencer vector bases remain logical pool addresses with the same width, capacity checks, and program ABI. The kernel translates every physical pool request only at final memory arbitration. Public logical blocks are 0..479. A permutation of the existing 512 physical blocks consists of 480 public mappings and 32 private scratch handles; no vector or factor data RAM is added.

At reset public mappings are identity and scratch handles are 480..511. A lazy-valid bitmap permits this identity state without a distributed map reset. All validity is indexed by logical address. Host, operator-feeder, support, factor, panel, and ordinary compute reads use the same translation. Private scratch writes use their current scratch handle; public callers cannot address 480 or above.

The two-credit synchronous `stream_vector_store` RAM and its read/write handshake remain unchanged. After service output masks validate, the kernel swaps one destination mapping with its scratch handle per cycle while busy and while host access is disabled. Destination validity is invalidated before the sequence and published only after the final swap. This replaces COPY_READ/WAIT/WRITE; it retains the scratch-output arithmetic stage.

Each swap preserves a complete permutation. Cancellation during a multi-block commit retains swaps already made, clears the destination's full invalidation extent, flushes transactions, and exposes no partial result. It does not reset mappings while keeping unrelated valid data. Reset can restore identity because it clears logical validity. Mapping addresses and scratch masks remain stable under backpressure.

The kernel swaps only actual produced output blocks. TOPK/UNION may request more extent than they return: the requested extent is invalidated as before, while unproduced blocks are not swapped. Zero-result commands invalidate their extent without swapping. Exact tail masks, repeated-address destination semantics, and required source-valid masks remain unchanged. Commands with unsupported layouts retain the legacy copy path. `SCALAR_INSERT` guarantees a full requested-vector result and full requested-vector commit.

All command reads complete under the pre-command mapping, so source/destination alias semantics remain unchanged. The mapping metadata has no timing/resource claim.

## Phase B: installed loaded project update

Feature5 opcode20 `FACTOR_PROJECT_UPDATE` operates on a private factor rectangle with the existing three round points: `q=round22(A^T v)`, `q=round22(alpha*q)`, and `A=checked_S27(A-round22(v*q^T))`. It performs no support selection, reflector construction, LS solve, certificate, or algorithm decision.

Descriptor31 (kind3, sources A/B, increment) is reserved for this operation: context word0 is canonical direct-A/B MAC mode1, word1 direct-A/B MUL mode1, word2 direct-A/B SUB mode1, and words3..31 are zero. Full 64-bit contexts, reserved bits, scalar bindings, and padding are validated. Ordinary operations reject kind3. Program record width/revision remains2; feature5 is explicit and older feature packages retain prior validation.

The panel worker expands the loaded primitives at configuration boundaries: dot uses MAC on all32 PEs, scale uses MUL on all32, and rank update uses MUL on low16 with SUB on high16 through the existing cascade. `a_cache[128]` retains v and `b_cache[96]` retains private q across the phases. No public Q vector is written or reread. Dot completes over the rectangle before scale; scale completes before rank; dot, scale, and rank rounding boundaries remain separate. Two factor passes remain necessary.

The command fields are length=row count, aux_length=row start, index=first column, support_length=total S, src_a=packed v, scalar_a=alpha, dense=1, fmt=1 and matching rows/key/B-generation/job. Unused operands/flags are canonical zero. It returns count0/length0 and no public candidate like FACTOR_RANK1. Completion waits for every factor write acknowledgement. The tagged factor bridge validates phase context and scalar before mutation and suppresses stale responses; factor validity follows fault/cancel rules.

## Feature6 compact backsolve

`SCALAR_INSERT` captures a checked S27F22 scalar RF value and replaces one lane while forming the full destination vector through existing scratch slots and the Phase-A commit protocol. It retains source-mask, tail, alias, fault/cancel, triangular write order, and stored-X certificate semantics. It is neither in-place nor changed-word-only publication. Its unused descriptor indices are canonical zero; the sequencer drives unused raw `src_b`, support-base, and auxiliary-base buses to literal zero even if descriptor0 has a nonzero legal base. Vector0 is not reserved and no null-vector RAM exists.

The primary VM and unaccelerated reference VM share `Arithmetic` as recorded by the numerical archive. Dedicated RTL phase gates use independent integer expected values; this does not claim independent VM arithmetic implementations.

## Evidence and boundaries

Vivado XSim evidence covers 17 kernel tests, 14 sequencer tests/166 cases, 2 factor leaf gates, 11 support groups/156 records, and 40 matched active10 fixed8 whole-program runs (`resident` and `compact`) at M32/N64/K8 and M64/N256/K8. See [five-step report](../../../reports/v4/five_optimizations_20260910/README.md), [A/B/C comparison](../../../reports/v4/resident_chain_comparison_20260910/resident_chain_comparison_vi.md), [RTL qualification](../../../reports/v4/scalar_insert_rtl_20260910/qualification.json), and [numerical archive](../../../reports/v4/scalar_insert_numerical_20260910/archive_manifest.json).

There is no synthesis, timing, PPA, board, production-bit, or held-out application-quality conclusion. Fixed8 quality remains diagnostic and may include float SNR below20dB. `compact` is selected explicitly with `--qr-profile compact --target-kernel-revision 6`; `balanced` remains the compatibility default.
