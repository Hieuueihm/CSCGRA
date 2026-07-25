# Factor-reuse checkpoint correctness report

## Verified source

- RTL checkpoint: `96305d1265a23859630093698bd99af9db2c8080`
- Commit subject: `Reuse Cholesky factors with verified border updates`
- Verification date: 2026-07-25
- Simulator: Vivado XSIM 2018.1
- Timing target: `xczu7ev-ffvc1156-2-e`, 100 MHz OOC

Only this report is added after the checkpoint. The RTL under
`CSCGRA.srcs/sources_1/new/` remains byte-for-byte identical to commit
`96305d1`.

## Correctness results

### Representative M=64, N=256, K=8

All eight algorithms and all strict final-golden checks pass.

| Algorithm | Iterations | Cycles | Result |
|---|---:|---:|---|
| OMP | 8 | 44,751 | PASS |
| CoSaMP | 8 | 129,395 | PASS |
| IHT | 16 | 92,285 | PASS |
| HTP | 32 | 236,277 | PASS |
| SP | 8 | 135,093 | PASS |
| GP | 16 | 93,186 | PASS |
| GOMP | 4 | 25,103 | PASS |
| MP | 32 | 118,465 | PASS |
| **Total** | | **874,555** | **8/8 PASS; 16 checks PASS, 0 FAIL** |

### Full K-sweep

The sweep covers:

- `(M,N,K) = (64,256,16), (64,256,8), (64,256,4)`
- `(32,128,8), (32,128,4), (32,128,2)`
- `(16,64,4), (16,64,2)`

Result: **348 PASS, 0 FAIL**. The existing CoSaMP/SP K=16 skip rule remains
unchanged because those configurations require 2K candidate support.

Cycle counts are reported separately for every algorithm:

| M | N | K | OMP | CoSaMP | IHT | HTP | SP | GP | GOMP | MP |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 64 | 256 | 16 | 110,785 | skip | 105,466 | 173,848 | skip | 106,282 | 60,894 | 60,145 |
| 64 | 256 | 8 | 44,751 | 155,245 | 47,107 | 61,807 | 135,110 | 47,515 | 25,102 | 30,985 |
| 64 | 256 | 4 | 21,573 | 54,193 | 23,350 | 28,600 | 40,349 | 23,554 | 12,507 | 16,405 |
| 32 | 128 | 8 | 17,999 | 102,846 | 19,665 | 28,499 | 86,241 | 19,945 | 10,699 | 10,633 |
| 32 | 128 | 4 | 8,133 | 30,259 | 9,469 | 11,958 | 19,220 | 9,609 | 5,053 | 5,781 |
| 32 | 128 | 2 | 4,403 | 9,003 | 5,001 | 6,182 | 7,325 | 5,071 | 2,913 | 3,355 |
| 16 | 64 | 4 | 3,717 | 21,191 | 4,453 | 5,949 | 11,736 | 4,561 | 2,479 | 2,389 |
| 16 | 64 | 2 | 1,971 | 4,911 | 2,299 | 2,936 | 3,665 | 2,353 | 1,402 | 1,435 |

### Dedicated M=64, N=256, K=16 rerun

The existing current K-sweep testbench was rerun with only `CASE=0` selected.
This independently reproduced the K=16 sweep row with **33 PASS, 0 FAIL**:

| Algorithm | Iterations | Cycles | Status | Nonzeros |
|---|---:|---:|---:|---:|
| OMP | 16 | 110,785 | `00000000` | 16 |
| CoSaMP | — | skip: requires 2K candidate support | — | — |
| IHT | 16 | 105,466 | `00000000` | 16 |
| HTP | 16 | 173,848 | `00000000` | 16 |
| SP | — | skip: requires 2K candidate support | — | — |
| GP | 16 | 106,282 | `00000000` | 16 |
| GOMP | 8 | 60,894 | `00000000` | 16 |
| MP | 16 | 60,145 | `00000000` | 15 |

### Large M=128, N=256, K=8

Result: **45 PASS, 0 FAIL**.

| Algorithm | Cycles |
|---|---:|
| OMP | 82,639 |
| CoSaMP | 229,871 |
| IHT | 74,257 |
| HTP | 96,627 |
| SP | 182,152 |
| GP | 74,665 |
| GOMP | 44,051 |
| MP | 58,121 |

No `X_MISM`, timeout, IRQ, context, program-counter, completion, or nonzero
error pattern was found in any of the four sign-off regression logs.

## Timing and resources

The retained OOC synthesis report for this exact checkpoint has zero failing
setup endpoints:

| Metric | Result |
|---|---:|
| WNS | +3.001 ns |
| TNS | 0.000 ns |
| Worst data-path delay | 6.989 ns |
| Total LUT | 96,755 |
| Logic LUT | 95,219 |
| LUTRAM | 1,536 |
| FF | 32,558 |
| BRAM36 | 24 |
| DSP48 | 71 |

## Local log provenance

Large simulator logs remain ignored under `runs/` and are not committed. Their
SHA-256 checksums are recorded here:

- K=8 all algorithms:
  `03826DF5BF5C122E6470E29451138BAB52DFB417499FF72AFFD4F4E3C02B45FD`
- Full K-sweep:
  `CA23789497ED0C62CEF0D3975F68035BD2718DB3159CEE4FDA98ECDE44611DD2`
- Dedicated M64/N256/K16:
  `B4B1E26D49A22FB3D131BF227994D1EE67EDBAF09E43C1704DC5FE0335AA0EAE`
- M128/N256/K8:
  `749015FE2A6F16505E50DE22C4584A5A28A5DC86CA427F61CE419CD55D294C49`

## Architecture scope

This checkpoint predates commit `5469d79`, which introduced the stricter
provenance rule and assertions requiring every controller/SPM operand to enter
at physical PE row 0 before advancing through PE1, PE2, and PE3. Functional
correctness and timing pass here, but strict PE0-only ingress must be audited or
ported separately if that later architecture rule remains mandatory.
