# Factor service draft

## Feature4 QR append qualification

Profile `reuse` adds generic FACTOR_EXTEND(op19) under the existing program
revision2. OMP/GOMP prove an exact ordered support prefix and immutable Phi/Y;
BUILD_B advances the B generation, and EXTEND imports only new columns at the
next generation. Shrink/reorder/mismatch uses INIT. Corrections still apply
all reflectors and the stored-X certificate is unchanged. The generic backend
checks shape/identity; it does not infer support membership from dimensions.

[QR reuse contract](QR_REUSE.md) records the inert loaded template, generation,
mask and publication rules. [The paired XSim report](../../../reports/v4/qr_reuse_comparison_20260910/qr_reuse_comparison_vi.md)
qualifies all20 fixed8 cases. Later resident/panel-chain/scalar-patch work is
separate; CPU AXI and board timing remain unimplemented/unqualified.

This document freezes the proposed generic transport boundary before its focused RTL gate. It does not claim completed QR RTL or a measured speedup. `stream_kernel` dispatches factor commands to `factor_service`, which instantiates `factor_store`. The kernel retains its single vector pool, PE fabric and scratch publication path. No second multiplier array or QR-phase state machine is introduced.

## Command fields

All three commands select dense B and carry M=`rows` (1..128), S=`cols` (1..96), key, B generation, job, tag and format1. In the current program encoding, dense columns come from `support_length_s`; that scalar continues to hold S during factor commands.

| Opcode | Meaning | `length` | `index` | `aux_length` | `flags` | Pool operand |
|---|---|---|---|---|---|---|
| 13 INIT | Clone published B into private S27 factors | M | 0 | 0 | 0 | None |
| 14 READ | Pack a factor row/column range | L, 1..128 | Fixed row/column | Range start | bit0 row=1, column=0 | Destination, packed L |
| 15 WRITE | Replace a factor row/column range | L, 1..128 | Fixed row/column | Range start | bit0 row=1, column=0 | Source A, packed L |

Other flag bits are zero. READ/WRITE require `start+L` within the varying dimension and the fixed coordinate within its dimension, using widened bounds arithmetic. Compiler branches skip empty ranges; zero-sized INIT and zero-length transfers are explicit command/range faults in this first contract. An all-zero B is valid transport data; numerical rank detection belongs to the loaded QR program. Unused vector addresses cause no RAM reads but remain valid public descriptor bases under the shared command ABI.

READ requires destination capacity L. WRITE requires source A capacity L. INIT requires neither. `aux_length` is a coordinate for these opcodes, not an auxiliary vector length, so controller capacity checks must classify it accordingly. Successful response count is S for INIT and L for READ/WRITE; response data is zero. Nonzero reports whether any active transferred value is nonzero (B for INIT, source range for WRITE, packed output for READ); inactive lanes do not contribute. The normal job/tag/format and fault/detail handshake is retained.

## Ownership and identity

INIT invalidates prior private factors immediately. It snapshots the selected B identity and shape, requests only dense B, and preserves the original B contents. Each original C18F16 value becomes S27F22 by exact sign extension and left shift6, which fits the destination width. Only a complete validated copy publishes factor validity.

The existing core matrix endpoint already exposes current `matrix_valid`, rows, columns, key, generation, job and format. Individual B read responses echo generation, job, format, tag and bank mask; **they do not echo key or shape**. Therefore INIT checks selected metadata at acceptance, at every response and before publication, checks response generation/job/format/tag/mask, and relies on the B endpoint's validation of the requested key. This is the explicit existing-port boundary; no nonexistent response field is assumed.

READ/WRITE require the current selected B metadata to match the factor image and command. Metadata drift during active transport or cancellation invalidates factor ownership. Idle selection may legitimately point to Phi; that does not invalidate retained factors. A new B epoch is detected at the next factor command. Completion is already snapshotted when its response becomes valid; the response stays unchanged under stall and the core retains ownership until it is consumed. A failed WRITE also invalidates the complete private factor image, even if only some physical writes occurred. A malformed/faulting READ must not publish any partial destination to the vector pool. Prior committed job results are owned separately and remain untouched.

`recovery_engine` keeps BUILD_B and factor commands mutually exclusive through whole-job ownership. It supplies the current B generation for dense requests. Factor traffic does not use the top's external host-write path; that path is already reserved for BUILD collection and final result draining and would bypass vector scratch publication.

## Store and internal interfaces

The fixed physical layout is logical bank `(row+column) mod32`, address `3*row+floor(column/32)`. Logical banks contain 384 words of27 bits: 331,776 raw data bits in total. The September 11 synthesis correction implements each logical bank as an independent 512x27 RAM, keeping the sixteen-pair generate hierarchy. Fill and request writes share one explicitly muxed write port per RAM; the synchronous read and response credits retain their timing. This replaces the previous disjoint halves of sixteen 1024x27 arrays without changing logical addresses, allocated bit capacity or introducing another factor image. Coordinate hole checks for M<128 or S<96 belong to the worker. Actual physical resource usage is established by the synthesis reports and implementation remains separate.

The store owns begin/ordered-fill publication and image identity. Begin carries rows8, columns7, key128, generation32, job16 and format8. Fill order is column outermost and 32-row block innermost, with `fill_col[6:0]`, `fill_block[1:0]`, mask32, packed data864 and exact final `last`. Held load status distinguishes success from malformed/incomplete filling. After publication, generic requests carry read/write, bank mask32, addresses288, data864 and identity/tag. Responses include read/write echo, data, mask, generation/job/tag/format and fault. Two response credits support read and write acknowledgments. The worker can use one outstanding bundle initially without changing the store interface.

The worker uses the core's existing tagged pool-read service and candidate stream. WRITE stages the complete source range in at most four 32-word bundles and validates every returned mask/tag/fault before its first factor mutation. READ emits dense ordered packed candidate blocks into the existing scratch collector; the core publishes the destination only after the worker completes successfully. Factor store requests and responses are likewise checked before success.

All transfers operate on full 32-lane bundles per granted memory response, with a combinational or registered lane rotation between logical banks and packed order. There is no one-element-per-cycle packing loop. INIT needs `S*ceil(M/32)` source grants and ordered fill bundles. READ and WRITE each need `ceil(L/32)` factor bundles; WRITE additionally needs the same number of pool-read bundles. These are grant counts, not complete command-cycle predictions. Stalls, validation, pipeline registers and publication add cycles that must be measured.

Reset/cancel flush pending and held transactions. Store cancellation invalidates private factors; physical RAM contents need not be erased. Ordinary rejected low-level store requests perform no write, but a worker failure cancels the store to prevent reuse of a partially updated numerical factorization.

## Generic QR lowering

The loaded program initializes factors from B, then loops over columns. It reads the active column, computes tail/full energies using loaded MAC reductions, obtains the norm through SQRT, and forms beta, tau and the scaled reciprocal using explicit checked S27 arithmetic and DIV. Numeric S27 subtraction remains a shared-PE operation; ADD64/SUB64 are not substitutes for its range check. A one-element constant vector plus REPLACE_RANGE supplies the reflector's implicit leading one without modifying every lane0 of later blocks.

For each trailing column, READ packs its active range. Loaded MAC DOT returns raw Q44; RESCALE rounds it to S27 before the tau multiplication, preserving the candidate model's round point. Scalar multiplication is a one-active-lane loaded MAC plus RESCALE on the same PE array. Loaded SCALE and SUB update the column before WRITE. The diagonal stores beta and the lower column stores the reflector tail.

QtY uses SLICE/REPLACE_RANGE around the same reflector operations. Backsolve uses row READ plus solution SLICE, DOT, RESCALE, checked subtraction and DIV. STORE narrows to X24F20, and the original B supplies the exact stored-X normal certificate. Optional bounded refinement reuses retained factors; it does not invoke LSQR. The first numerical calibration gate required no refinement.

For a nonzero-tail 128x96 factorization, the structural trailing-column count alone is 4,560 DOT operations; QtY, backsolve, norm and certificate reductions are additional. Full-bundle transport is necessary to keep memory packing from adding a 32-fold per-element schedule. No total latency improvement is asserted until the complete lowered program is measured.

A conservative allocation envelope reserves six full-N outer vectors (192 blocks at N1024), four M128 vectors (16), three support96 vectors (9), eight packed QR128 buffers (32), three coefficient96 vectors (9), and two scalar-vector blocks: 260 public blocks and26 descriptors. This is a planning envelope, not a completed liveness proof. The actual compiler must prove nonoverlap, live caller preservation, at most32 descriptors and at most480 public blocks for every exported package; factor RAM is separate private working storage. Original B and the externally committed result remain separately owned.
