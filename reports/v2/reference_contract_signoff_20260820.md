# Canonical-to-RTL contract validation

Date: 2026-08-20  
Branch: `codex/strict-pe0-timing`  
Base commit: `5734bda`

## Scope

This checkpoint establishes one forward-only correctness chain:

```text
canonical.py -> hardware.py -> generated hardware golden -> RTL v2
             -> cycle/resource/timing optimization
```

- `models/reference/canonical.py` owns the floating-point algorithm.
- `models/reference/hardware.py` owns the reviewed Q16, bounded-storage and
  LDLT realization. It is the only active golden generator.
- RTL and C software must match the generated hardware golden. A failing RTL
  trial must not be repaired by changing the golden to resemble RTL.
- Timing/cycle/area work starts only after exact functional regression.

The GP path was migrated from the former IHT-like update to a restricted
gradient projection with projected signed-Q16 line search. The same operation
sequence is used by the hardware Python model, Verilog test program and C test
program.

## Correctness result

| Check | Result |
| --- | ---: |
| Reference-contract static guard | PASS |
| Generated Verilog/C golden freshness | PASS |
| SDK/TB opcode/program sync | PASS |
| GP canonical-to-Q16 conversion | exact, 8/8 cases |
| GP RTL sweep | 48 PASS / 0 FAIL |
| Full RTL K-sweep | 348 PASS / 0 FAIL |
| Measured algorithm/case rows | 62 |
| Expected capacity skips | CoSaMP K16, SP K16 |

All RTL comparisons use the hardware golden with zero tolerance. CoSaMP/SP
K16 remain explicit 16-entry candidate/LS-capacity exclusions; they are not
silently replaced by a different expected result.

## Cycle result

| Algorithm | Cases | Total cycles | K8 cycles |
| --- | ---: | ---: | ---: |
| OMP | 8 | 163,388 | 48,580 |
| CoSaMP | 7 | 268,921 | 180,768 |
| IHT | 8 | 124,804 | 39,186 |
| HTP | 8 | 208,856 | 57,882 |
| SP | 7 | 223,174 | 159,420 |
| GP | 8 | 167,964 | 53,858 |
| gOMP | 8 | 93,685 | 28,014 |
| MP | 8 | 109,260 | 34,674 |
| **Total** | **62** | **1,360,052** | **602,382** |

The canonical GP sequence is intentionally more expensive than the earlier
IHT-like substitute. For example, case 1 (64x256, K8) is 38,369 cycles instead
of 28,569. This is an accepted correctness-first change; subsequent cycle
optimization must preserve the new hardware model.

## Synthesis and routed implementation

Target: `xczu7ev-ffvc1156-2-e`, 100 MHz.

| Metric | OOC synthesis | Routed implementation |
| --- | ---: | ---: |
| WNS | +0.374 ns | **-0.356 ns** |
| TNS | 0 ns | -210.368 ns |
| Setup failing endpoints | 0 | 1,768 |
| Hold WNS | n/a | +0.034 ns |
| LUT | 129,509 | 122,321 |
| LUTRAM | 2,144 | 1,696 |
| FF | 53,936 | 53,641 |
| RAMB36 | 24 | 24 |
| DSP48 | 77 | 77 |
| Routing errors | n/a | 0 |

The narrow RHS input register is retained as a useful timing isolation step:
relative to the immediately preceding routed baseline of WNS -0.478 ns and
TNS -405.890 ns, it improves WNS by 0.122 ns and TNS by 195.522 ns without a
cycle, DSP or BRAM increase. It does **not** meet the project timing gate of
WNS >= +0.2 ns, so this is implementation-clean but not timing-signed-off.

The new worst path starts at a replicated sparse-controller state bit and ends
at `residual_pipe_sum_r2_q`; nearby failing paths also end at PE accumulator
registers. The 10.346 ns data path has 34 logic levels and is 57.6% routing
delay. The next timing pass should therefore isolate/register this
controller-to-residual/PE boundary and reduce state fanout/congestion while
leaving canonical/hardware/golden files frozen.

## Reproduction evidence

- Simulation: `logs/sim/v2/ref_contract_full`
- GP-only simulation: `logs/sim/v2/ref_contract_gp_full`
- OOC synthesis: `logs/synth/v2/ref_contract_synth`
- Routed implementation: `logs/impl/v2/ref_contract_impl`

`work/` and `logs/` are intentionally ignored. This reviewed report is the
tracked summary; rerun the named flows when raw evidence is required.
