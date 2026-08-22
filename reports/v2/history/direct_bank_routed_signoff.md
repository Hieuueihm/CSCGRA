# Per-row direct-bank wide LS operands: first routed 100 MHz closure

This checkpoint replaces the single four-row-wide `ls_wide_a/b_bus` operand
crossbars with eight per-row banks (`ls_wide_{a,b}_row0..3_bus`). Each PE
cluster now receives its own eight-column slice directly; the payload is
bit-identical to the previous encoding and only the physical routing
boundary changes. A registered `ls_wide_operand_valid` token (issue token /
border boundary / batch4 idle) replaces the implicit decode at the array
boundary. The goal was to remove the high-fanout controller-to-array net
that dominated the previously failing routed timing
(state -> residual stage-2 with PE accumulator endpoints).

## Results

Functional and cycle behavior are unchanged; timing and resources improve.

| Metric | Previous routed baseline | Direct-bank checkpoint |
|---|---:|---:|
| Full K-sweep | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL |
| Full-sweep cycles (OMP K16 case0) | 99,404 | 99,404 |
| Full-sweep cycles (OMP K8 case1) | 40,644 | 40,644 |
| OOC WNS / TNS | +0.374 ns / n/a | +2.087 ns / 0.000 |
| Routed WNS / TNS | -0.356 ns / -210.368 ns | +0.032 ns / 0.000 |
| Routed WHS / THS | +0.034 ns / n/a | +0.047 ns / 0.000 |
| Routed failing setup endpoints | 1,768 | 0 |
| Routed LUT / FF | 122,321 / 53,641 | 121,763 / 51,975 |
| RAMB36 / DSP | 24 / 77 | 24 / 77 |

Vivado reports "All user specified timing constraints are met" with
163,636/163,636 nets fully routed. The K16 skips remain the two intentional
`requires_2K_candidate_support` exclusions (CoSaMP, SP); GP runs normally at
K16.

## Routed critical path

```
u_sparse_kernel_service_engine/u_sparse_loop_controller/state_reg[3]_rep__16
  -> ls_wide_{a,b}_r{0..3} operand cone (ls_batch4_active, fo=483 nets)
  -> u_pearray/u_pe_cluster1_4x4/.../u_core/prod_full__0/DSP_OUTPUT_INST/ALU_OUT[41]
```

29 logic levels, routing-dominated (net delays about 63% of the path). The
operand cone between the controller state registers and the PE DSP inputs is
still the structural limiter, but the former single cross-fabric fanout is
gone.

## Caveat: thin margin

Routed WNS is +0.032 ns (3.2 ps). This meets the 100 MHz constraint
(positive WNS, zero TNS, hold clean) but does **not** meet the +0.2 ns
project guard band. A different P&R seed, tool update, or small RTL change
could flip it negative. Treat this as "timing met at 100 MHz, thin margin",
not a robust sign-off; future RTL work must keep OOC WNS >= +0.2 ns and
re-route before claiming closure.

## Reproducibility

- Simulation: `logs/sim/v2/direct_bank_full_sweep` (8 case logs, summary).
- OOC synthesis: `logs/synth/v2/direct_bank_synth/cgra_top_timing.rpt`.
- Implementation: `logs/impl/v2/direct_bank_impl/` (timing, route status,
  utilization).

Primary RTL: `rtl/v2/control/sparse_loop_controller.v`,
`rtl/v2/solver/sparse_kernel_service_engine.v`, `rtl/v2/pe/pearray.v`,
`rtl/v2/pe/pe_cluster_4x4.v`, `rtl/v2/top/cgra_top.v`.
