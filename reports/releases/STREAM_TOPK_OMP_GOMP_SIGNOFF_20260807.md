# Streaming exact top-K activation for OMP/GOMP

Date: 2026-08-07

Baseline: support/mesh timing-isolation checkpoint `c9f3a34`, documented in
`SUPPORT_MESH_TIMING_ISOLATION_SIGNOFF_20260807.md`.

## Outcome

The existing four-row PE streaming exact top-K path is now used by OMP and
GOMP.  The controller no longer performs a separate full-vector reduce scan
and candidate append after each correlation for these two algorithms.

- OMP programs `stream top-1 excluding support -> correlation -> refine`.
- GOMP programs `stream top-2 excluding support -> correlation -> refine`.
- The correlation completion remains deferred until the PE top-K result has
  been committed to support memory.
- The canonical K-sweep testbench and both v2 bare-metal program emitters use
  the same context encoding.

No v2 RTL changed relative to `c9f3a34`; this release activates hardware that
was already present and signed off.  Timing and resource results are therefore
the byte-identical RTL results from that checkpoint.

## Four-row PE and ingress invariant

The activated path preserves strict PE0 ingress:

1. Each eight-lane correlation block is captured and serialized only at PE0.
2. Candidate ownership is split by `index mod 4`, assigning one ownership
   class to each PE row.
3. Candidate tokens and the end tag travel through the registered
   PE0 -> PE1 -> PE2 -> PE3 wavefront.
4. Each row maintains its exact local top-K contribution.
5. PE3 commits the global exact top-K list; no lower row accepts an independent
   controller ingress.

The existing vertical-provenance assertions remain active in simulation.

## Profile-driven selection

The pre-change full-sweep state profile contained 1,650,508 cycles:

- factor-check: 2,778 cycles (0.168%);
- non-idle support service: 35,771 cycles (2.167%);
- repeated reduce uop: 93,376 cycles (5.657%);
- streaming top-K: 0 cycles, because no production program activated it.

Factor-check was therefore rejected as the next cycle target.  The final
profile records 74,608 active top-K-service cycles for OMP and 37,376 for
GOMP, proving that the four-row streaming hardware is used by the production
programs.

## Correctness and cycle sign-off

Final run: `logs/sim/v2/stream-topk-omp-gomp-final-nortl`

- 348 PASS / 0 FAIL;
- 62 valid cycle records;
- 2 expected K16 skips for algorithms requiring 2K candidate capacity;
- all eight K-sweep cases exercised, through K=16.

| Algorithm | Baseline cycles | Final cycles | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| OMP | 200,088 | 199,256 | -832 | -0.416% |
| CoSaMP | 345,649 | 345,626 | -23 | -0.007% |
| IHT | 163,278 | 163,278 | 0 | 0% |
| HTP | 264,491 | 264,491 | 0 | 0% |
| SP | 276,931 | 276,931 | 0 | 0% |
| GP | 165,358 | 165,358 | 0 | 0% |
| GOMP | 113,805 | 111,932 | -1,873 | -1.646% |
| MP | 120,908 | 120,908 | 0 | 0% |
| **Total** | **1,650,508** | **1,647,780** | **-2,728** | **-0.165%** |

The small CoSaMP delta is an inter-workload cache/order side effect in the
sequential all-algorithm sweep; CoSaMP's own program was not optimized.

### OMP/GOMP delta by K-sweep case

| Case | M/N/K | OMP delta | GOMP delta |
| ---: | --- | ---: | ---: |
| 0 | 64/256/16 | -400 | -829 |
| 1 | 64/256/8 | -200 | -367 |
| 2 | 64/256/4 | -100 | -170 |
| 3 | 32/128/8 | -72 | -236 |
| 4 | 32/128/4 | -36 | -108 |
| 5 | 32/128/2 | -18 | -50 |
| 6 | 16/64/4 | -4 | -78 |
| 7 | 16/64/2 | -2 | -35 |

## Timing and resources

Because `git diff -- rtl/v2` is empty, the signed-off hardware result remains:

| Metric | Result |
| --- | ---: |
| WNS at 100 MHz | +0.325 ns |
| TNS / failing endpoints | 0 / 0 |
| Total LUT | 112,516 |
| FF | 51,122 |
| RAMB36 | 24 |
| DSP48 | 71 |

This preserves the required positive-WNS gate and the preferred margin above
+0.2 ns.

## Rejected activation trials

Two broader streaming trials were deliberately not retained:

- CoSaMP streaming passed standalone but contaminated the following IHT in a
  sequential workload (`case7`: three golden mismatches).
- SP streaming passed K=2/K=8 smoke tests but failed exact golden at
  M32/N128/K4 and contaminated a following GP case.

Both programs were restored to their proven reduce/append sequences before
the final 348/348 sign-off.  These failures indicate a program/service state
or ordering issue that must be solved explicitly; they must not be re-enabled
based only on standalone smoke results.

## Tooling added

- `-ProfileStates` enables controller, top-K, support-service, and uop
  residency counters without affecting synthesizable RTL.
- Per-algorithm runner selection now uses one packed `RUN_CASE_ALG` plusarg,
  avoiding the Vivado 2018.1 behavior where the last of multiple
  `-testplusarg` options hides the earlier selector.

## Recommended next work

1. Add an explicit ready/valid contract between correlation block production
   and the serial top-K consumer, then reproduce and fix SP/CoSaMP ordering in
   sequential workloads.
2. For IHT/HTP/GP, stream the post-update `x` blocks into the four PE rows;
   correlation streaming is not semantically equivalent for these algorithms.
3. Keep factor-check unchanged unless a new profile shows materially more than
   its current 0.168% share.
4. Continue LS optimization on the LDLT border/cache-to-RHS path only with
   WNS >= +0.2 ns and full K-sweep as release gates.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId stream-topk-omp-gomp-final-nortl

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -ProfileStates -RunId stream-topk-profile
```

Raw simulation and synthesis artifacts remain under ignored `logs/` and
`work/` directories.
