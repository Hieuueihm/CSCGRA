# B-cache read-window follow-up

Completed September 12, 2026 at 15:02:04 +07:00. Installed panel RTL SHA-256:
`f6d1194196817c263541edb438e60aacedc63e4c9fafdb56a35d0922d3e6c236`.

**Trade-off:** this candidate reduces standalone panel LUTs by 10.03%, with
unchanged program cycles. It does not improve every metric: OOC internal
WNS drops by 0.763 ns (remaining positive), and this synthesis run takes
55.47% longer. The previous 63,880-LUT source is retained in `baseline/`.
The candidate is retained for the requested area reduction, not claimed
as a synthesis-speed or timing improvement.

## Completed OOC comparison

Same Vivado 2018.1 build 2188600, `xczu7ev-ffvc1156-2-e`, 10 ns internal
clock, default directives and flow script. Only the panel RTL differs
between the two synthesis snapshots.

| Metric | Accepted baseline | B-cache candidate | Change |
| --- | ---: | ---: | ---: |
| LUT | 63,880 | 57,470 | -6,410 / -10.03% |
| FF | 17,078 | 17,091 | +13 |
| RAMB36 / RAMB18 / DSP | 0 / 0 / 0 | 0 / 0 / 0 | unchanged |
| synth_design elapsed | 00:22:41 | 00:35:16 | +55.47% |
| synth_design CPU | 00:21:31 | 00:32:26 | increased |
| synth_design peak memory, MB | 3,685.430 | 3,362.031 | reduced |
| Internal OOC WNS, ns | +2.767 | +2.004 | -0.763 |
| Internal OOC TNS, ns | 0 | 0 | unchanged |
| Internal OOC WHS, ns | +0.067 | +0.067 | unchanged |

Runtime is one observed run per revision, not a statistical benchmark.
The memory row is the peak during `synth_design`; the subsequent timing
report raises the candidate's reported process peak to 4,395.715 MB.
Mapped FF count differences do not represent a new RTL pipeline stage.

## Implementation

The B cache still holds the same 96 words with the same writes. Its read
path selects one word from each fixed group of three, then rotates a
shared 32-word window. Wide RANK and SCALE use window lane `lane`; narrow
RANK uses window lane `lane/2`. Original masks, state transitions, PE
arithmetic, rounding, protocol and bank-address generation are untouched.

For `delta = col_position - col_start`, fixed bank `bank` selects block
`floor(delta/32) + (bank < delta mod 32)`. The final rotation yields word
`b_cache[delta + lane]`. Signed intermediate widths preserve the old
out-of-range simulation behavior, rather than aliasing invalid addresses.
All generated rotation slices are compile-time constants.

## Verification

- 18 focused/calibration XSim unittest cases PASS (five focused and thirteen
  real-fabric/PROJECT/range/energy/calibration cases).
- New B-cache test: 524,160 word comparisons across all 4,095 signed
  counter differences and four data patterns, plus 4,732 legal feed
  window/width/mode combinations. The existing 65,536-comparison rotation
  test is rerun unchanged.
- 40/40 full-program PIO/DMA replay traces match the accepted baseline
  byte-for-byte: ten algorithms, M32/N64 and M64/N256, K8, eight actual
  outer iterations. All cycle buckets and raw trace contents are unchanged.
- Sixteen compiler mapping shapes are remeasured with identical R1/R4
  cycles before updating the calibration source binding.
- Eighteen compiler/parser tests PASS after rebinding.
- All 79 watched replay inputs, 76 synthesis RTL/header snapshots and
  recorded gate sources are hash-verified.

Golden fixtures and earlier qualification archives are not modified.
The existing replay driver's source-drift guard is unchanged.

## Evidence and limits

- `baseline/`: previous accepted source, calibration, completed OOC reports.
- `gates/`, `gate_source_snapshot/`: source-bound focused/regression evidence.
- `replay/`: final complete replay and immutable input/source snapshots.
- `calibration/`: actual XSim mapping measurement.
- `ooc/`: final synthesis log, reports, constraints, config and source manifest.
- `summary.json`, `SHA256SUMS.json`: comparison and archive integrity.

Checkpoint: `D:/vivado_pj/work/v4_ooc_panel_bcache_20260912_1425/post_synth.dcp`.
It remains outside the source/report archive; its SHA-256 is in the summary.

This is **factor_panel_service OOC**, not `csr_top` utilization. No new
full-top synthesis or implementation is run. External I/O delays and
`HD.CLK_SRC` are unspecified, so positive internal WNS is not routed timing,
Fmax or board sign-off. Startup Common 17-741 and the OOC timing warning
are retained, not suppressed. Full-top synthesis and implementation must
assess whether the area/timing trade-off benefits the integrated design.
