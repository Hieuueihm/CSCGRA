# Payload benchmark: September 11, 2026

## Qualified result

40 XSim simulations PASS: ten algorithms, two sizes, PIO and DMA, K=8 and actual eight outer iterations.
Raw X/residual/support/status/inner+outer counters match the immutable qualified oracle; native compute cycles match both transport modes and the prior qualified native run.

| M/N | Algorithm | Native cycles | PIO total | DMA total | Reduction |
|---|---|---:|---:|---:|---:|
| 32/64 | MP | 5,485 | 23,646 | 21,611 | 8.61% |
| 32/64 | GP | 6,266 | 26,100 | 24,065 | 7.80% |
| 32/64 | IHT | 6,502 | 25,940 | 23,905 | 7.85% |
| 32/64 | OMP | 20,375 | 62,212 | 60,173 | 3.28% |
| 32/64 | GOMP | 40,406 | 82,248 | 80,209 | 2.48% |
| 32/64 | CoSaMP | 132,429 | 167,222 | 165,187 | 1.22% |
| 32/64 | SP | 44,897 | 80,132 | 78,093 | 2.54% |
| 32/64 | HTP | 11,746 | 47,024 | 44,989 | 4.33% |
| 32/64 | FISTA | 4,022 | 24,504 | 22,469 | 8.30% |
| 32/64 | PDHG | 4,398 | 24,836 | 22,797 | 8.21% |
| 64/256 | MP | 13,308 | 38,367 | 30,415 | 20.73% |
| 64/256 | GP | 14,699 | 41,433 | 33,481 | 19.19% |
| 64/256 | IHT | 14,993 | 41,329 | 33,381 | 19.23% |
| 64/256 | OMP | 30,692 | 79,425 | 71,481 | 10.00% |
| 64/256 | GOMP | 55,475 | 104,217 | 96,269 | 7.63% |
| 64/256 | CoSaMP | 157,106 | 198,795 | 190,843 | 4.00% |
| 64/256 | SP | 63,556 | 105,689 | 97,741 | 7.52% |
| 64/256 | HTP | 21,179 | 63,357 | 55,405 | 12.55% |
| 64/256 | FISTA | 17,037 | 44,417 | 36,465 | 17.90% |
| 64/256 | PDHG | 17,296 | 44,633 | 36,685 | 17.81% |

## Measurement limits

See docs/v4/architecture/PAYLOAD_BENCHMARK.md for precise boundaries. setup includes program/context and Phi; load is payload; compute is host-observed START/DONE; writeback includes all result elements and support/metadata. total is their exact sum.
DMA active/stall counters overlap those buckets and are not additive. Internal compute-stall attribution is unavailable; the recorded DMA stall counter is not a whole-core stall metric.
This is a specified AXI BFM latency comparison, not PS software, physical DDR throughput, CPU cache maintenance or board qualification. DDR initialization/CPU result consumption are excluded; post-timing residual validation is excluded.
SNR/NMSE diagnostics are inherited from the unchanged qualified inputs/outputs. Fixtures below the quality target remain below it; faster transport does not improve algorithm quality.
Physical measurements are a separate source-matched run. The simulator evidence retains physical fields as NOT_RUN; any later actual synthesis/route outcome is recorded in physical/ rather than rewriting simulator provenance.

## Reproduce

python -m scripts.v4.benchmark_payload

python -m unittest verification.v4.test_payload_benchmark -v

No RTL, golden images, compiler defaults, PE count, interconnect or mesh changed for these measurements.
The report archive omits XSim executables and preserves source snapshots, input fixtures, logs, traces and SHA256 metadata.

## Physical gate

The requested OOC synth/impl flow was attempted with Vivado 2018.1, default
directives, `xczu7ev-ffvc1156-2-e` and a 10.0 ns clock. It failed during RTL
elaboration before implementation at `rtl/v4/dataflow/factor_panel_service.sv:340`: part-select `[890:864]` exceeds `fabric_out_data`. RAM inference warnings (`Synth 8-4767`) are retained. No physical metrics are reported; see `physical/README.md` and `physical/impl.log`.
