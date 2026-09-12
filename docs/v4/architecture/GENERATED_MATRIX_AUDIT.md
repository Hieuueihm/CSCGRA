# Audit: stored `A` versus generated Phi in v2/v3

Audit date: 2026-09-08. This is a bounded source audit of the checked-in v2/v3
generators and their compiler/configuration/model evidence. It does not change
v2/v3 RTL, configuration, or numerical models. The source tree has no `psi`
file and no v2/v3 `measurement_generator` module; the generated object in both
generations is a Bernoulli/Rademacher `Phi`, not a general dense `A`.

## Executive finding

The v3 generator is the reusable idea for a generated-Phi backend: a
coordinate-addressed, deterministic Threefry2x32-20 sign map. Its software
contract is `phi_sign(seed,row,column)` and its RTL request is
`(seed,column,row_pair)`. Each invocation returns two 32-bit sign words. The
software `matrix()` helper materializes those signs at its legacy/default
`+1/8` or `-1/8` scale and `phi_q3_14()` exposes raw magnitude `2^11`; this is
not the whole active v3 runtime magnitude. Runtime configuration supplies an
independent UQ1.17 mantissa and signed exponent to the Phi normalizer. Requests
are order independent in the model. The
RTL source actually contains a ten-stage folded pipeline with a two-pass
feedback scheme; the checked-in M7 test asserts first response latency 21 cycles
and the architecture contract records II=2 per 64-sign request. The raw output
gearbox exposes one 32-bit sign word per accepted output cycle.

The v2 generator is a different contract. `rtl/v2/datapath/lfsr_phi.v` emits
`COLS` signed values from one mutable 32-bit Galois LFSR state on each `gen_en`
cycle. A zero seed is replaced with `DEADBEEF`; the sign is selected by the
current state LSB and the magnitude is the configured signed `phi_scale_q8_8`.
It is sequential and stateful. The v2 controller adds fixed jump matrices and
row/column scan state for correlation, but that is a schedule-specific way to
reconstruct the stream, not a general random `(row,column)` address interface.

Neither generator can replace the v4 stored arbitrary dense `A` contract by
itself. v4's current matrix image takes physical `A`, quantizes it once, and
creates resident `A` and `transpose_A` orientations. A future generated backend
must define the coefficient family, exact indexing for both orientations and
arbitrary support, provenance, numeric scale, and a separate quality gate.

## v3 generated-Phi contract

The host model is explicit in `models/v3/phi_generator.py:1-9,19-27`:

* `THREEFRY_ROUNDS=20`, parity `0x1BD11BDA`, rotations
  `(13,15,26,6,17,29,16,24)`;
* `PHI_ROWS_PER_WORD=32` and `PHI_WORDS_PER_COUNTER=2`;
* bit 1 maps to a positive sign and bit 0 to a negative sign;
* `PHI_SCALE=1/8` is the software materialization helper scale;
* `PHI_Q3_14_MAGNITUDE=1<<11`, so `phi_q3_14` returns signed D18F14 raw
  `+2048/-2048` (`+0.125/-0.125`) for that helper view.

The exact coordinate map is in `models/v3/phi_generator.py:63-97`:

```text
key = (u32(seed), u32(seed >> 32))
counter = (u32(column), u32(row_block >> 1))
word = Threefry2x32-20(counter, key)[row_block & 1]
row_block = floor(row / 32)
entry(seed,row,column) = sign(bit(word, row mod 32)) * 2^11
```

The model validates a 64-bit seed, 32-bit column, and 33-bit row block
(`:71-76`). `matrix()` materializes only for software/golden use and loops
column-major over `column` then `row` (`:100-109`); its docstring says the RTL
does not materialize the matrix. `words_for_column()` yields valid lane mask
and sign word in column-major RTL order, with a masked final 32-row block
(`:112-122`).

The active runtime scale is `alpha = mantissa_uq17 * 2^exponent / 2^17`.
`runtime_scale_s27()` applies that scale to an accumulated F19 value, rounds,
and saturates to S27 (`models/v3/phi_generator.py:124-148`). The run
configuration carries the same 18-bit UQ1.17 mantissa and signed five-bit
exponent, constrains the exponent and optionally checks `M*alpha^2` against
unit norm (`compiler/v3/run_configuration.py:103-122`). In RTL, Phi sign
accumulation applies the sign to a data operand and accumulates it; the
normalizer performs the configured mantissa/exponent scaling and narrowing
(`rtl/v3/cgra/phi_pe_alu.v:83-101`; `rtl/v3/phi/phi_operator_normalizer.v:66-80,108-139`).
Consequently, the generator supplies signs; it does not hardwire every active
runtime coefficient to `+/-1/8`.

The RTL reproduces the same mapping. `rtl/v3/phi/threefry2x32_folded_pipeline.v:26-80`
defines parity, ten pipeline stages, the eight rotation constants, modular
32-bit add/rotate/xor, and key injection every four rounds. Request packing
uses seed low/high halves as key words and `parity ^ seed_low ^ seed_high` as
the third key word (`:115-125`); the request counter is zero extended
`column` and `row_pair` (`:121-125`). The pipeline accepts a new external
request only while `external_phase` is true and alternates that phase
(`:115-117,142-183`). A request is run through a first pass and a feedback
second pass; response valid requires the final stage's `second_pass` bit
(`:106-113,152-205`).

`rtl/v3/phi/phi_symbol_generator.v:6-99` wires the request queue, folded
Threefry, symbol builder, and response gearbox. The symbol builder's
`lane_mask(measurement_count,row_block)` masks rows past M and passes the two
32-bit words unchanged (`rtl/v3/phi/phi_symbol_builder.v:25-54`). The response
gearbox stores two words per request and emits the selected row block, one
32-bit `sign` plus mask/coordinate/tag per output transfer
(`rtl/v3/phi/phi_response_gearbox.v:34-58,65-89`).

### Access order and supported schedules

At the pure function level, v3 is random access: the model docstring says
requests may be issued in any order without changing results
(`models/v3/phi_generator.py:63-69`), and the test compares forward and reverse
coordinate requests (`verification/v3/test_phi_generator.py:24-35`). The RTL
provider exposes five schedule modes (`rtl/v3/phi/phi_stream_provider.v:52-56`):

* sequential: `base + i*stride`, with bounds checked (`:90-109,250-293`);
* support-list: columns arrive through `support_column`, each checked against
  `active_signal_length` (`:136-144,274-281`);
* repeat: a configured base/stride is replayed by the regular stream;
* cache and cache-row-major: the provider asks a support cache for slots in
  column-major or row-major order (`:172-212,298-325`).

Thus support-list provides arbitrary support IDs at the provider boundary, but
there is no direct arbitrary `(row,column)` request mode in the provider. The
generator itself is order independent; the provider is a finite streaming
schedule with M-dependent row-pair limits. Configuration rejects zero count,
out-of-range row pairs, illegal memory-space/write bits, and invalid base/last
items (`:87-109`).

The compiler uses the same `PHI_SIGN_WORD` generator resource for correlation,
forward restricted support, and transpose restricted support. The graph records
the `phi_generator -> phi_accumulate` broadcast for each routine
(`compiler/v3/reconstruction_graphs.py:232-317`). The transpose routine changes
the vector input/output and reduction direction; it does not introduce a
different Phi coefficient source (`:303-317`).

### Cache role and limits

`support_phi_symbol_cache.v` is a sign-word cache, not a full dense matrix. Its
capacity is `RECON_PHI_SUPPORT_CACHE_SLOTS=96`, candidate cache slots are 64,
and max row blocks are 4 (`rtl/v3/include/architecture_parameters.vh:69-84`).
It stores one 32-bit sign word per support slot and row block, plus column IDs;
the cache's address functions are candidate `slot*4+row` and active
`CANDIDATE_WORDS + slot*4+row` (`rtl/v3/phi/support_phi_symbol_cache.v:63-106`).
Replay is synchronous, has a two-entry response FIFO, only serves valid active
slots, and returns a computed lane mask for the current M
(`:138-179,226-244,333-362`).

The cache supports ordered support preparation, candidate capture/promotion,
sequential fill, invalidation, and replay. It becomes `cache_valid` only after
the complete expected support/row-block payload is present
(`:366-421,426-505`). This is useful for repeated `A_S`/`A_S^T` operations,
but it does not provide all N columns of A and does not prove a generated
arbitrary-support backend for v4.

## v2 generated-Phi contract

`rtl/v2/datapath/lfsr_phi.v:1-75` is the complete datapath generator. Defaults
are `LFSR_W=32`, `COLS=8`, `DATA_W=24`, taps `32'h80200003`
(`:1-6`). `galois_step` shifts right and xors taps if the prior LSB is one
(`:24-34`). A zero seed maps to `DEADBEEF`; `phi_plus` is the configured
scale and `phi_minus` is its two's-complement negative
(`:20-38`). On each enabled generation, each consuming lane emits `+scale` for
state LSB 1 and `-scale` for state LSB 0, then advances the shared state
(`:40-55,57-71`). The exact condition is `!advance_masked_lanes ||
lane_valid[i]`: with the mask control clear, every lane consumes a state
regardless of `lane_valid`; with the mask control set, only valid lanes consume
a state and invalid lanes emit zero without advancing (`:47-53`).
Despite the signal name, the set value therefore gates advancement with
`lane_valid`; the predicate above is the implementation authority.

The v2 top-level explicitly states that dense M*N Phi is regenerated from the
LFSR stream and never stored as a dense matrix (`rtl/v2/top/cgra_top.v:71-85`).
The top wires the generator to the PE array as an 8-lane, `DATA_W`-bit bus and
passes seed/scale/reseed/lane-valid controls (`rtl/v2/top/cgra_top.v:360-376`),
then selects that stream for ordinary PE execution (`:612-625`).

For correlation/transpose-like access, the v2 controller contains explicit
LFSR jump helpers. `lfsr_advance` is bounded to at most `COLS` compile-time
steps and warns against runtime-variable or large offsets
(`rtl/v2/control/sparse_loop_controller.v:193-210`). `lfsr_advance32` uses an
8-step jump matrix plus a short remainder (`:212-235`). The controller's
correlation state keeps current row/column states and a second 16-column
super-block lane (`:1071-1103,1139-1147`). In `S_CORR_SCAN` and `S_CORR_ACC`, it
forms `corr_phi_lane` and `corr_phi2_lane` from row state and fixed jumps over
N (`:3194-3228,3246-3277`). This supports the signed-off scan schedule and
pair-mode correlation, but the source does not expose a generic random indexed
Phi function equivalent to v3's `phi_sign(seed,row,column)`.

The v2 matrix service is for the regularized Cholesky/LDLT factor, not a
resident measurement matrix (`rtl/v2/solver/ls_matrix_service.v:1-8`). The
generated Phi remains in the stream; A/AT semantics are obtained by distinct
controller schedules and scan state. Exact support-list arbitrary-column
replay is not present in the inspected v2 generator interface.

## Phi versus Phi/Psi and host transforms

No `psi` source file exists under the repository. v3's paper and hardware model
consume an already supplied `Phi[M,N]`: `models/v3/paper.py:87-98` checks the
shape as Phi and `models/v3/hardware.py:275-316` quantizes/uses that matrix for
correlation and matvec. The generated-Phi integration test constructs
`phi_generator.matrix(...)` and passes it directly to the hardware model
(`verification/v3/test_phi_generator.py:61-71`). There is no evidence that v3
forms `A=Phi@Psi` on fabric or in its v3 host model.

The v4 matrix image does support a different host path. `compose_operator()` is
explicitly host real arithmetic `A = Phi @ Psi` before quantization
(`compiler/v4/matrix_image.py:105-117`), and `build_composed_matrix_image()`
quantizes that complete product once (`:512-518`). The v4 matrix contract says
the host computes the full product, does not quantize Phi/Psi independently,
and then creates both resident orientations (`docs/v4/architecture/MATRIX.md:13-25,55-83`).
Therefore replacing stored A with generated v3/v2 Phi would silently change
the physical operator whenever Psi is non-identity; the existing source does
not provide a Phi/Psi factorized fabric path.

## Configuration, latency, and resource evidence

The compiler scaling constants are architectural contract values, not synthesis
results. `compiler/v3/architecture_scaling.py:23-25` records one generator,
64-bit output, II=2, target latency 21; `:124-160` labels cycle values as
architectural lower bounds and names the generator
`threefry2x32_20_counter_addressed`. The v3 architecture configuration marks
`PHI_SIGN_WORD` as implemented, latency 21, II=2, measured through the
`phi_symbol_generator` report (`compiler/v3/architecture_configuration.json:730-738`),
and allocates one stream generator with one request producing two cluster words
(`:818-828`).

The actual v3 M7 test checks the KAT sign/mask/coordinate payload and asserts
the first response latency is 21 cycles; with no stalls it checks one output
word per cycle (`verification/v3/m7/tb_m7_phi_generator.sv:127-142,228-230`).
This is generator/gearbox behavior. It is not a guarantee that every v4
forward or transpose schedule sustains a useful 32 coefficients per cycle:
the consumer must exploit both words from each request and align its row/column
tiling. The v3 provider can also be intentionally configured for subsets,
repeat, or cache replay.

Available Vivado post-synthesis reports are included as point-in-time evidence,
so no LUT estimate is made here. Their synthesis input/source revision is not
captured well enough to assert that they synthesize the current dirty-tree
hashes below. For the xczu7ev target at 6.667 ns, the report for
`phi_symbol_generator` gives 2,106 CLB LUTs, 1,887 CLB registers, zero BRAM and
zero DSP, with WNS 2.811 ns (`reports/v3/m7_vivado/phi_symbol_generator/utilization.rpt:34-39,76-89`; `summary.txt:1-8`).
The provider report gives 2,617 LUTs, 1,998 registers, zero BRAM/DSP, WNS 2.585
ns (`reports/v3/m7_vivado/phi_stream_provider/utilization.rpt:34-39,76-89`; `summary.txt:1-8`).
The support cache report gives 2,622 LUTs, 1,238 registers, one RAMB36, zero
DSP, WNS 4.469 ns (`reports/v3/m7_vivado/support_phi_symbol_cache/utilization.rpt:34-39,76-90`; `summary.txt:1-8`).
These are module OOC reports from that point in time, not an estimate for a
future generated-A backend and not proof of current-hash synthesis.

## Reusable ideas and unresolved gates

Reusable source-backed ideas are: counter-addressed deterministic signs; an
explicit scale and raw numeric format; lane masks for M tails; valid/ready
backpressure with stable payload; a small support sign-word cache; and separate
forward/transpose schedules that call the same coefficient function.

The following remain unknown or unproven for a generated-A decision:

1. v3 tests establish Threefry KATs, order independence, exact amplitude, and
   one integration replay, but do not establish RIP, mutual coherence,
   recovery quality over the v4 application set, or per-seed statistical
   qualification. `test_materialized_golden_has_exact_bernoulli_amplitude`
   checks only two amplitudes and equal column energy for one case
   (`verification/v3/test_phi_generator.py:49-52`).
2. The v3 dense Rademacher path has equal column norms by construction when all
   M rows are valid, but tails and any future sparse/fixed-weight mode require
   their own norm and quality checks. The run configuration currently accepts
   only `DENSE_RADEMACHER`, requires `phi_column_weight == M`, and rejects the
   other encoded kind (`compiler/v3/run_configuration.py:22-29,103-113`).
3. A generator for arbitrary v4 A must prove identical coefficients for A*x,
   A^T*r, and arbitrary support access. v2's mutable stream and v3's provider
   schedule do not by themselves satisfy that full indexed interface.
4. No source-backed LUT/FF/BRAM/DSP cost exists for a compact full sign cache or
   generated general A. The only resource claims in this audit are the cited
   Vivado module reports.
5. Periodicity or exploitable correlation beyond the documented finite word and
   counter widths was not inferred from source and was not statistically tested
   in this audit.

## Evidence hashes

SHA-256 hashes below identify the exact files inspected:

| File | SHA-256 |
|---|---|
| `models/v3/phi_generator.py` | `971b09dbe918656e33cdfabd2a95f8644fb8d0e888373a09961a2a89989fc408` |
| `rtl/v3/phi/threefry2x32_folded_pipeline.v` | `de74ff769a8ac1380cf9845f1ed94128b14926d5cb2ecb40c3c8f750b8775e6d` |
| `rtl/v3/phi/phi_symbol_generator.v` | `9c5432c5732bf17ef57b5ccd3dd84e4b1d8982d7a9fc53685b7ddcbd0457544f` |
| `rtl/v3/phi/phi_symbol_builder.v` | `ee7ab917cf079d4fbfae02eca4c7e597451897d4458acb93f1cfc31348bd289b` |
| `rtl/v3/phi/phi_stream_provider.v` | `ff7089af544f0d4af8a2a7ec005a69218138acf85052a757653c1349c353b07f` |
| `rtl/v3/phi/support_phi_symbol_cache.v` | `19e5218666fcf759896e7a70e5d8a076bac2d4017fef9766cc00dfa65a1ca32e` |
| `rtl/v3/include/architecture_parameters.vh` | `4c20108b2f1f6d2255309d3abd0edbe7697f45c41b115c88a4afab5a1dd96066` |
| `compiler/v3/architecture_scaling.py` | `bbb2c8861557e2941d823e0ed0087a9fb7108f041443e3dc020a886f1c97aacb` |
| `compiler/v3/run_configuration.py` | `1fff19da4f54ae528c0f2dff4a286d627bc1d45a3ac9ec25ffe3c3b6d34050b2` |
| `compiler/v3/architecture_configuration.json` | `5928b2bc0fc487e25ca477ce3ce4df543e3f39d882323ca8afcea61b4ad4bcd0` |
| `compiler/v3/reconstruction_graphs.py` | `3b3cf7123ffbb53441fae4d491d58d5d0d8620465e692699d39b6a254573081a` |
| `verification/v3/test_phi_generator.py` | `048739e7e6cd88be83f00f811b4b503db5dfc24aa2cdf7ea878a2058ad3e6cee` |
| `verification/v3/m7/tb_m7_phi_generator.sv` | `64a1e21ac5e15e8f08cba3c9aef1442d89cdad6331857d1bd5d2e89bd60ca020` |
| `rtl/v2/datapath/lfsr_phi.v` | `fe6793b59189b2219320a8f66f954dd0347b21e64d60e804b4006287eac66298` |
| `rtl/v2/control/sparse_loop_controller.v` | `1908db66c9836703aa55f84719f2915ee92b831a65bf83d82553e279502b1809` |
| `rtl/v2/top/cgra_top.v` | `6d66114488039187291270eebf5d8e4df529ce60e4c3c98fbfaa934e302921f2` |
| `config/rtl-v2.json` | `23e1ba01356a4c8ff608af4a2d85bee617b6fb2b59db70dba522fc6773d143b9` |
| `config/rtl-v3.json` | `f24a2e4ed0550869236227fbece7a9f36104525c2ee7d6efe8ebf66c08b2c29a` |
| `reports/v3/m7_vivado/phi_symbol_generator/summary.txt` | `cd703077f7e0b6b1d1e63c5d32bea807124e8a0beb97a56d15d0b8c7bd19b7d5` |
| `reports/v3/m7_vivado/phi_symbol_generator/utilization.rpt` | `73ddabee78250cf7755f17e8a2a27439b2174766af7794a73ecaeb8aaec97957` |
| `reports/v3/m7_vivado/phi_stream_provider/summary.txt` | `dd9a9eb089408a9cc3055c2b8b4b53712393eac07988ca648a58ac2f21d5595f` |
| `reports/v3/m7_vivado/support_phi_symbol_cache/summary.txt` | `6ff2702a86c2af6164fa1982e5aef11e53f0741bcde8a7effdee6c7e361f9f7c` |
| `reports/v3/m7_vivado/support_phi_symbol_cache/utilization.rpt` | `87cfd13e26548355e88bb12b87dad05466818b0490111f0f5a337ac640ec8308` |

The selected test was rerun with `D:\Holography\pybuild\python.exe` (the
NumPy-capable environment): `python -m unittest verification.v3.test_phi_generator`
ran 7 tests and returned `OK`. An earlier system-Python attempt failed only
because that interpreter lacked NumPy; no source was modified to work around
the environment gap.
