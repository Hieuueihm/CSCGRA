# Factor-panel packed output indexing

The September 11, 2026 Vivado 2018.1 OOC attempt failed with Synth 8-524:
`factor_panel_service.sv` selected output bits [890:864] outside the
32-lane S27 bus [863:0]. A procedural `lane < dot_width` test does not
provide a structural bound to every R4 `lane*4` part-select during synthesis.
The same pattern appeared in the nonzero detector, project DOT cache fill and
MATVEC candidate capture.

The correction uses a 32-lane combinational `dot_result_data` bus with
generate-time lane mapping:

- In R1, logical lane c is physical lane c for all c=0..31.
- In R4, logical lanes c=0..7 read physical lanes 4*c=0,4,...,28.
- Logical lanes c=8..31 are zero in R4 and are already excluded by dot_width<=8.

Only generate branches with c<8 contain a stride-four part-select. No wider
bus, truncated/wrapped index, inserted register, changed arithmetic, changed
rounding, clock, protocol, bank or PE count is introduced. The three consumers
use the same statically bounded mapping. This is a synthesizability correction,
not a cycle optimization.

## Regression contract

`verification.v4.test_factor_panel_slice_guard_rtl` exhaustively checks all
32 physical input lanes, all R1 widths1..32, R4 widths1..8, the nonzero detector,
non-MATVEC state and all-zero output: 3841 assertions in XSim. It forces only
mode/width controls to isolate combinational mapping; this alone is not full
service qualification.

Existing service/fabric/project gates additionally cover real handshakes,
tail mapping, rounded arithmetic, response identity, stalls, injected faults,
cancellation and recovery. Full-program replay uses immutable fixtures from
`reports/v4/payload_benchmark_20260911` with ten algorithms, two geometries,
eight actual iterations and both PIO/DMA transports. The candidate must match
each prior trace byte-for-byte, including X/residual/support and every recorded
cycle bucket. Only the one declared RTL file may differ from the original
source-bound baseline; golden files and baseline guards are not relaxed.

The replay runner is `python -m scripts.v4.replay_factor_panel_fix`. Its
forty runs and the focused XSim gates must pass before the full physical flow
is retried. Read the final physical log and reports separately: fixing this
elaboration error does not itself qualify RAM inference, resource fit, timing,
implementation, board behavior or maximum frequency.

## Verified candidate

Evidence is archived in `reports/v4/factor_panel_slice_fix_20260911`.
The factor-panel SHA256 changes from
`b67649423d3c18bbe6e4772d85d0fdb5057c8336a0878d782a19398b4ed825e8` to
`87f1b4c91837b0e6bbe0b72157d09bc8d232bb233a523bfa35bb9c7e9cd39eda`.

- Eight focused XSim tests pass: seven existing service/fabric/project tests
  and the new 3841-check combinational slice test.
- Forty full-program replays pass: ten algorithms, M32/N64 and M64/N256, K8,
  eight actual iterations, PIO and DMA. Every trace is byte-identical to the
  immutable pre-fix trace, including all recorded cycle buckets.
- Two XSim GEMV calibration tests pass after remeasurement; all sixteen
  R1/R4 shape measurements retain their previous cycle values.
- Eighteen compiler mapping and benchmark-parser tests pass, including the
  stale-calibration rejection and archived measurement integrity checks.

The calibration profile points to the newly measured qualification artifact,
not a hash-only bypass. Its other source hashes and all cycle entries remain
unchanged. The calibration runner records 32 measured-source hashes; the
profile additionally tracks 15 unchanged dependencies. The whole-program
replay records the current RTL/header snapshot and verifies no source drift
throughout its forty runs.

This is bit-exact acceptance for the recorded fixtures and focused gates,
not a proof for every possible input or a new quality/PPA result. Read the
physical outcome in the evidence report separately.
