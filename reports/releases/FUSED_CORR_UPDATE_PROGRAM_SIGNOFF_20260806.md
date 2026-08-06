# Fused correlation-update program sign-off

Date: 2026-08-06

Baseline: stable LS command-chain checkpoint `cf949d6` with the program data
recorded in `stable_ls_command_chain_k_sweep_20260805.csv`.

## Change

The canonical v2 K-sweep microprogram and its bare-metal C emitter now use the
existing `SOP_CORR_UPDATE` (`0x88`) operation for IHT, HTP, and GP.

- IHT and HTP replace consecutive `SOP_CORR` and `SOP_IHT_UPDATE` contexts
  with one `SOP_CORR_UPDATE` context.
- GP replaces `SOP_CORR` followed by `SOP_GRAD_STEP` with
  `SOP_CORR_UPDATE`; the same exact reduce/argmax and append contexts still
  follow the fused operation.
- Support selection, pruning, residual generation, LS refinement, fixed-point
  arithmetic, and exact tie-breaking are unchanged.

No RTL file changed.  The fused datapath was already present in the signed-off
hardware: correlation values and eight-lane x-update blocks enter PE0 and
advance through the registered PE0 -> PE1 -> PE2 -> PE3 wavefront.  Exactly
one controller ingress remains active, and all four physical PE rows
participate before PE3 commits the vector block.

## Sign-off result

| Metric | Stable program | Fused program | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1,774,300 | 1,682,044 | -92,256 (-5.20%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| Valid cycle records | 62 | 62 | unchanged |
| Expected K16 skips | 2 | 2 | unchanged |
| WNS | +0.309 ns | +0.309 ns | RTL unchanged |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | RTL unchanged |
| Total LUT / FF | 113,628 / 50,762 | 113,628 / 50,762 | RTL unchanged |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | RTL unchanged |

The OOC timing and utilization values are inherited exactly from the stable LS
checkpoint because `rtl/v2` is byte-identical and has no Git diff.  This
checkpoint changes only the program contexts that exercise hardware already
included in that synthesized netlist.

## Per-algorithm aggregate cycles

| Algorithm | Stable program | Fused program | Delta |
| --- | ---: | ---: | ---: |
| OMP | 200,088 | 200,088 | 0 |
| CoSaMP | 345,649 | 345,649 | 0 |
| IHT | 204,542 | 173,790 | -30,752 (-15.04%) |
| HTP | 305,755 | 275,003 | -30,752 (-10.06%) |
| SP | 276,931 | 276,931 | 0 |
| GP | 206,622 | 175,870 | -30,752 (-14.88%) |
| GOMP | 113,805 | 113,805 | 0 |
| MP | 120,908 | 120,908 | 0 |

OMP, CoSaMP, SP, GOMP, and MP match the prior cycle matrix exactly in every
case.  The complete new matrix is in
`fused_corr_update_program_k_sweep_20260806.csv`.

At M=64, N=256, K=16, the measured changes are:

| Algorithm | Stable | Fused | Delta |
| --- | ---: | ---: | ---: |
| IHT | 98,938 | 85,498 | -13,440 (-13.58%) |
| HTP | 165,070 | 151,630 | -13,440 (-8.14%) |
| GP | 99,754 | 86,314 | -13,440 (-13.47%) |

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(0,1,2,3,4,5,6,7) -RunId 'fused-corr-update-full' }"
```

Raw generated artifacts remain under ignored `logs/` and `work/`
directories.  The next low-risk target is the existing but currently disabled
strict-PE0 block-8 prune path; streaming exact top-K program activation should
be evaluated separately because it changes candidate-path scheduling.
