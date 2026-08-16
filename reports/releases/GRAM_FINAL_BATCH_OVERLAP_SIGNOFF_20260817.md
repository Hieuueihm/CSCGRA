# Gram final-batch overlap sign-off

Date: 2026-08-17

Baseline: forward-solve shared tail-completion checkpoint `d487050`, with the
subsequent documentation-only rejected-trial commits through `1bd2eea`.

## Selected optimization

The Gram controller previously kept one guard clock after every registered
`ACC4` command.  Removing that guard globally was unsafe: a new transaction
could be produced every three clocks while the matrix service drains one in
four clocks, eventually overrunning its one-entry pending queue.

The accepted implementation overlaps only the final `ACC4` batch of each
measurement row.  It detects that both the current four-column block and the
current four-row block are final and sets the existing drain guard to zero.
All consecutive Gram batches retain guard one.  The following direct-Phi scan
and RHS accumulation interval is longer than the remaining service drain, so
the pending entry is retired before the next Gram command.

This is a bounded scheduling change, not a wider ACC4 FIFO.  It adds no payload
registers, no DSP, and no BRAM.  The service interface remains registered.

## Architectural invariants

- Sparse input still enters at PE0 and propagates PE0 -> PE1 -> PE2 -> PE3.
- Every four-row Gram operation keeps the fixed row ownership already present;
  inactive tail rows remain masked.
- `S_ACC_GRAM` remains the only ACC4 launch state and uses the registered
  `ls_start_q` command path.
- Exactly one LS solve request remains active.  Factor reuse, LDLT arithmetic,
  pivot order, support, top-K, residual scheduling, and iteration counts are
  unchanged.
- Only a final transaction can overlap the previous drain; sustained traffic
  cannot run at the unsafe three-clock request rate.

## Correctness

K8 profile run:
`logs/sim/v2/gram_last_guard0_k8_20260817`

- 45 PASS / 0 FAIL across all eight algorithms;
- total K8 cycles: 379,662 -> 376,764 (-2,898; -0.763%);
- controller state 100 falls from 1,536 to 1,024 clocks for OMP K8;
- IHT, GP, and MP are cycle-identical because they do not use Gram/LDLT.

Final unified run:
`logs/sim/v2/gram_last_guard0_full_20260817`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16 and M=16/32/64;
- 2 expected K16 SP/CoSaMP skips from the existing 2K candidate-capacity
  limit;
- no mismatch, timeout, or simulation error lines.

The complete cycle matrix is in
`gram_final_batch_overlap_k_sweep_20260817.csv`.

## Cycle results

Total cycles fall from 1,328,836 to 1,319,534: 9,302 cycles saved (0.700%).

| Algorithm | Runs | Baseline | Final | Saved | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 165,788 | 163,500 | 2,288 | -1.380% |
| CoSaMP | 7 | 272,157 | 269,597 | 2,560 | -0.941% |
| IHT | 8 | 125,244 | 125,244 | 0 | 0.000% |
| HTP | 8 | 210,098 | 209,348 | 750 | -0.357% |
| SP | 7 | 226,126 | 223,566 | 2,560 | -1.132% |
| GP | 8 | 125,244 | 125,244 | 0 | 0.000% |
| GOMP | 8 | 94,919 | 93,775 | 1,144 | -1.205% |
| MP | 8 | 109,260 | 109,260 | 0 | 0.000% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Saved |
| --- | ---: | ---: | ---: |
| OMP | 34,470 | 33,966 | 504 |
| CoSaMP | 107,216 | 106,208 | 1,008 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,611 | 39,485 | 126 |
| SP | 95,851 | 94,843 | 1,008 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,575 | 19,323 | 252 |
| MP | 25,673 | 25,673 | 0 |

OMP K16 falls from 84,014 to 83,006 cycles, while retaining 16 recovered
nonzero coefficients and clean status.

## Timing and resources

OOC run: `logs/synth/v2/gram_last_guard0_ooc_20260817`

| Metric | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| WNS at 100 MHz | +0.605 ns | +0.658 ns | +0.053 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 123,551 | 124,019 | +468 (+0.379%) |
| Logic LUT | 121,387 | 121,871 | +484 (+0.399%) |
| FF | 53,423 | 53,506 | +83 (+0.155%) |
| RAMB36 | 24 | 24 | 0 |
| DSP48 | 71 | 71 | 0 |

The cycle reduction (0.700% full sweep, 0.763% K8) is materially larger than
the total-LUT increase (0.379%).  Timing improves and remains comfortably above
the preferred +0.2 ns margin.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -Cases 1 -ProfileStates `
  -RunId gram_last_guard0_k8_20260817

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId gram_last_guard0_full_20260817

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top `
  -RunId gram_last_guard0_ooc_20260817
```

Raw simulation and synthesis artifacts remain under ignored `logs/` and
`work/` directories.
