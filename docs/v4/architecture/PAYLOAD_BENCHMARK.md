# Matched payload transport measurement

The runner is `python -m scripts.v4.benchmark_payload`. It uses XSim only,
the real `csr_top`, independent AXI-Lite/AXI4 memory BFMs and the immutable
fixed-eight images from `reports/v4/outer_fusion_20260911/m32_candidate` and
`m64_candidate`. It does not change algorithms, compiler defaults or RTL.
There are ten algorithms, K=8, M32/N64 and M64/N256, each with PIO and DMA
payload transport: 40 simulations. A subset is selectable with `--rows` and
`--algorithms`; it must not be reported as the full suite.

## Boundaries

All clocks use the same single 10 ns simulated clock; cycle counts, not GHz or
hardware throughput, are the measurement. The disjoint buckets are:

| Bucket | Start and end |
|---|---|
| setup | After reset, through program/context load, Phi configuration/fill and START descriptor staging |
| load | Measurement payload transfer through PIO or DMA, including descriptor/control/response acknowledgements |
| compute | Enabling core IRQ and issuing START through observing DONE via AXI-Lite polling |
| writeback | Reading completion metadata/counters/support, ACK DONE, extracting all N result elements, and final response/DMA ACK |
| total | setup + load + compute + writeback; checked exactly by the parser |

Native START-to-DONE cycles are separately read from the coherent DONE snapshot.
They are a subset of host-observed compute, not an extra additive bucket. Actual
outer iterations are asserted equal to 8 in the RTL DONE register. Native counts
must match within each PIO/DMA pair; historical native counts are retained for
inspection. Only exact geometry, image, input, policy and output-matched pairs
are used for transport comparisons, not cross-algorithm rankings or V2 speedups.

DMA active/stall/read/write-beat counters are sampled at each sticky completion
and accumulated over upload and download. Upload counters are also retained
separately. DMA stalls are an overlapping subset of transfer cycles; they must
not be added again to total. This does not measure every internal core stall.

## Verification and exclusions

The input comes from hash-validated archived integer-model/VM-qualified fixtures;
the conversion checks D18-to-S27 measurement values, contiguous blocks and raw Y
hash. X, residual and support match the same pinned oracle, with no regeneration
of hardware golden files. Residual inspection is through PIO after the timed
interval and is not included in writeback. X/support checks consume no simulation
clocks after extraction. The timing flow does not run fault/cancel/retry tests.

DDR buffers are preinitialized by the TB; host allocation, CPU cache maintenance,
CPU instruction execution and DDR-controller/physical-memory timing are excluded.
AXI4 readiness includes deterministic modulo-clock delays inherited from the
tested memory BFM. AXI-Lite AW/W skew and held responses remain exercised, but
these are specified driver/BFM costs, not an optimized Linux/bare-metal driver.
Both variants load identical program/context/Phi data through PIO. DMA output is
available in the model DDR buffer; subsequent CPU copying/consumption is excluded.

Quality metrics from the pinned fixture are retained unchanged and are not a new
application-accuracy qualification. Source hashes are checked before/after; logs,
traces, converted fixtures and source snapshots are retained without Vivado
simulation executables in the report archive.

## Physical metrics

Fmax, LUT/FF/BRAM/DSP require a separate source-matched physical run. The existing
`scripts/v4/run_synth_impl.tcl` uses Vivado default directives, ZCU106 device
`xczu7ev-ffvc1156-2-e` and a 10 ns OOC clock. Its interface timing is not
constrained; even a routed PASS would only qualify internal-clock OOC timing,
not board timing or DDR throughput. Missing/failed stages remain explicit rather
than being filled from historical reports. A single achieved target is not a
searched maximum frequency.
