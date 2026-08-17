# LDLT READ4 chain trial report

Date: 2026-08-17

Baseline: checkpoint `3152554`, whose RTL is identical to the signed-off LDLT
border phase-overlap checkpoint `0ae1557`.

## Profile and objective

At K8, `S_LDL_ROW_A_WAIT` and `S_LDL_ROW_P_WAIT` occupy 1,992 and 9,126
controller clocks respectively. Each READ4 is already a useful four-row banked
read, but the registered command interface leaves one idle service clock
between chained requests.

Two completion-edge variants were tested. Neither changed matrix contents,
ACC4, DSP/BRAM use, factor-reuse order, or the four-row PE arithmetic path.
Only one LS request remained active: request p+1 could be accepted only after
request p asserted registered `done` and the service had returned to IDLE.

## Trial A: direct address fast-start

The first implementation decoded `S_LDL_ROW_INIT` and chained
`S_LDL_ROW_P_WAIT` directly at the LS service boundary. The READ4 address mux
selected registered LDLT counters and p+1 on the same edge as start.

K8 passed at 45 PASS / 0 FAIL:

| Algorithm | Baseline | Trial A | Delta |
|---|---:|---:|---:|
| OMP | 33,920 | 33,878 | -42 |
| CoSaMP | 105,504 | 104,076 | -1,428 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,453 | 39,407 | -46 |
| SP | 94,251 | 93,036 | -1,215 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,295 | 19,266 | -29 |
| MP | 25,673 | 25,673 | 0 |
| **K8 total** | **375,362** | **372,602** | **-2,760 (-0.735%)** |

The state reduction was exact: `S_LDL_ROW_A_WAIT` fell by 295 clocks and
`S_LDL_ROW_P_WAIT` by 2,465 clocks.

OOC result:

| Metric | Baseline | Trial A | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.394 ns | -0.456 ns |
| Total LUT | 121,302 | 127,673 | +6,371 (+5.25%) |
| Logic LUT | 119,152 | 125,523 | +6,371 |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 6 | 6 | 0 |
| FF | 53,281 | 53,605 | +324 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

The address mux reached every distributed matrix bank and cost over seven
times the K8 cycle-reduction percentage. Trial A was rejected.

## Trial B: pre-registered p+1 address

The second implementation removed the direct address mux and the row-A fast
start. While READ4 p was in flight, it staged p+1 into the existing LS command
registers. The completion edge then controlled only the narrow start signal.

K8 again passed at 45 PASS / 0 FAIL:

| Algorithm | Baseline | Trial B | Delta |
|---|---:|---:|---:|
| OMP | 33,920 | 33,885 | -35 |
| CoSaMP | 105,504 | 104,224 | -1,280 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,453 | 39,421 | -32 |
| SP | 94,251 | 93,155 | -1,096 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,295 | 19,273 | -22 |
| MP | 25,673 | 25,673 | 0 |
| **K8 total** | **375,362** | **372,897** | **-2,465 (-0.657%)** |

`S_LDL_ROW_A_WAIT` returned to its 1,992-clock baseline, while
`S_LDL_ROW_P_WAIT` fell from 9,126 to 6,661 clocks. No other controller work
was removed.

OOC result:

| Metric | Baseline | Trial B | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.603 ns | -0.247 ns |
| Total LUT | 121,302 | 123,077 | +1,775 (+1.46%) |
| Logic LUT | 119,152 | 120,931 | +1,779 |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 6 | 2 | -4 |
| FF | 53,281 | 53,381 | +100 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

This form passed timing and greatly reduced Trial A's cost, but LUT growth was
still 2.23 times the cycle reduction percentage. The run also reported one
LUTNM shape critical warning during post-synthesis netlist transformation.
Trial B was rejected.

Raw artifacts:

- `logs/sim/v2/ldlt_read4_chain_k8_20260817`
- `logs/synth/v2/ldlt_read4_chain_ooc_20260817`
- `logs/sim/v2/ldlt_read4_preregister_k8_20260817`
- `logs/synth/v2/ldlt_read4_preregister_ooc_20260817`

## Decision

Both variants were removed. A full K-sweep was intentionally not run because
each candidate failed the agreed resource-versus-cycle gate after passing K8
correctness and OOC timing. RTL is restored exactly to checkpoint `3152554`.

Do not add another completion-feedback fast start to LDLT READ4. Even with
pre-registered addresses, feeding service completion back into request start
changes enough control sharing to exceed the cycle benefit. The next study
should profile a registered stage inside the wide-multiply or divider
controller rather than another matrix-memory handshake or write port.
