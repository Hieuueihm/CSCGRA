# Panel mux optimization — accepted candidate 2

Completed September 12, 2026. The installed RTL is candidate 2, SHA-256
`0f86b866d33d21fe8e711b0d555d877b082e66ca2e89d65e296e1258c9c73df7`.
This is a bit-exact and standalone **factor_panel_service OOC** result,
not a full `csr_top`, implementation, routed timing or board result.

## Measured result

Both completed runs use Vivado 2018.1 build 2188600, part
`xczu7ev-ffvc1156-2-e`, a 10 ns internal clock and default directives.
The source snapshot changes only `factor_panel_service.sv` relative to
the completed baseline OOC. No PE, arithmetic, rounding, protocol or
pipeline change is introduced.

| Metric | Completed baseline | Accepted candidate 2 | Change |
| --- | ---: | ---: | ---: |
| Total LUTs | 474,749 | 63,880 | -86.54% |
| FFs | 17,023 | 17,078 | +55 |
| RAMB36 / RAMB18 / DSP | 0 / 0 / 0 | 0 / 0 / 0 | unchanged |
| synth_design elapsed | 01:34:05 | 00:22:41 | -75.89%, 4.15x faster |
| synth_design CPU | 01:31:35 | 00:21:31 | reduced |
| synth_design peak memory, MB | 11,996.828 | 3,685.430 | reduced |
| OOC internal WNS, ns | +2.443 | +2.767 | +0.324 |
| OOC internal TNS, ns | 0 | 0 | unchanged |
| OOC internal WHS, ns | +0.067 | +0.067 | unchanged |

Runtime is measured once per completed revision on this host, not a
statistical benchmark. The memory row is the peak reported by
`synth_design`; the final candidate's subsequent timing report raises the
whole-process reported peak to 4,340.621 MB. Mapped FF counts may differ
after optimization; there is no added RTL pipeline register or clock edge.

Synthesis reports zero synthesis errors and zero synthesis critical
warnings, with ordinary warnings retained in the log. Startup separately
reports Common 17-741 about the local Tcl store. Timing reports warn that
`HD.CLK_SRC` is unspecified. External input/output delays are not
constrained; positive internal WNS does not establish Fmax or board timing.

## What changed

Repeated variable 27-bit part-selects of wide bundles are replaced with
shared, five-stage combinational word rotations and fixed permutations:

- Bank response to lane order, including R4 DOT and narrow RANK.
- Selected result slot to bank write order.
- Range source bundle to the 128 fixed A-cache destinations.
- DOT/SCALE results to the 96 fixed B-cache destinations, sharing one
  rotation after selecting the existing result source.

The existing masks, span checks, bank addresses and write enables remain
in place. Only combinational data selection changes. The mapping proof
and scope are in `docs/v4/architecture/PANEL_LANE_ROTATION.md`.

## Verification

- 17 distinct focused/calibration XSim unittest cases PASS for the final
  source, including 65,536 whole-bundle rotation comparisons.
- Coverage includes wide/narrow panel operation, M128 rectangles, negative
  fractional inputs, tails, deterministic stalls, second-DOT cancellation,
  fabric faults, range/energy publication faults and recovery.
- 40/40 immutable full-program traces match byte-for-byte: ten algorithms,
  M32/N64 and M64/N256, K8, eight actual outer iterations, PIO and DMA.
- All recorded cycle buckets, raw X/residual outputs and trace contents
  remain identical. `summary.json` retains each case profile and digest.
- 16 measured compiler mapping shapes keep exactly the same R1/R4 cycles.
  The profile is rebound only after remeasurement of the accepted source.
- 18 compiler/parser tests PASS after the final calibration update.
- All 79 watched replay inputs and the 76 RTL/header files in the final
  synthesis snapshot are hash-checked. Gate source copies are also checked
  against their recorded digests.

No golden vector or historical qualification archive is modified. The
original replay driver and its declared-drift guard remain unchanged.

## Evidence layout and run history

- `baseline/`: completed pre-change OOC reports and original panel source.
- `final_candidate/`: **the accepted candidate 2** gates, replay, source
  snapshots, compiler tests, calibration and completed OOC reports.
- `summary.json`: machine-readable comparison, per-case cycles and DCP hash.
- `SHA256SUMS.json`: archive integrity manifest, excluding itself.
- Root-level `gates/`, `replay/`, `calibration/` and test logs belong to the
  **intermediate candidate 1**, not the final installed source.
- `candidate1_ooc/`: candidate 1 passed bit-exact tests but its OOC was
  stopped by the operator after about 58 minutes without a final report.
  It is **ABORTED**, not a measured resource/timing failure. Its final LUT,
  WNS and completed runtime are unknown. Candidate 2 additionally removes
  the remaining dynamic cache-write data selectors.

The completed candidate-2 run ends at **11:02:08 +07:00** on September 12,
2026. Its checkpoint remains outside this source/report archive:

`D:/vivado_pj/work/v4_ooc_panel_mux2_20260912_1038/post_synth.dcp`

The old full-top run has no final checkpoint/report available in its
output directory. No new full-top run is launched as part of this panel
optimization. Full-top synthesis, then implementation, remain separate
gates before any whole-IP resource or timing claim.
