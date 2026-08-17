# Top-K append ACK-chain sign-off

Date: 2026-08-17

Branch: `codex/strict-pe0-timing`

Baseline: checkpoint `2243ad2`, whose RTL is the signed-off LDLT border
phase-overlap implementation.

## Change

The non-sorted top-K result append path previously inserted an empty issue
clock after every registered `append_done` acknowledgement.  The support-set
service had already returned to IDLE on that edge, while the next index and
path were already held in local registers.

`pe_stream_topk_serial_service` now presents the next registered index on the
ACK edge.  The final ACK transitions directly to DONE.  The interface remains
one index per accepted support write; no memory port is widened and no LS
request, READ4 completion path, divider, or wide arithmetic is changed.

Top-K ranking still enters at PE0 and traverses PE0 -> PE1 -> PE2 -> PE3.
The patch changes only the narrow post-ranking payload: a 10-bit index and a
3-bit path selector.

## Correctness and cycles

- K8: 45 PASS / 0 FAIL.
- Full K-sweep: 348 PASS / 0 FAIL, 62 measured records.
- The two K16 SP/CoSaMP cases remain expected capacity skips.
- K8 total: 375,362 -> 374,962 (-400; -0.107%).
- Full total: 1,315,336 -> 1,313,368 (-1,968; -0.150%).

K8 cycle comparison:

| Algorithm | Baseline | New | Saved |
|---|---:|---:|---:|
| OMP | 33,920 | 33,912 | 8 |
| CoSaMP | 105,504 | 105,376 | 128 |
| IHT | 28,633 | 28,569 | 64 |
| HTP | 39,453 | 39,389 | 64 |
| SP | 94,251 | 94,187 | 64 |
| GP | 28,633 | 28,569 | 64 |
| GOMP | 19,295 | 19,287 | 8 |
| MP | 25,673 | 25,673 | 0 |

Full-sweep reductions by algorithm:

| Algorithm | Baseline | New | Saved |
|---|---:|---:|---:|
| OMP | 163,124 | 163,076 | 48 |
| CoSaMP | 267,729 | 267,361 | 368 |
| IHT | 125,244 | 124,804 | 440 |
| HTP | 208,952 | 208,512 | 440 |
| SP | 222,222 | 222,038 | 184 |
| GP | 125,244 | 124,804 | 440 |
| GOMP | 93,561 | 93,513 | 48 |
| MP | 109,260 | 109,260 | 0 |

The reduction exactly equals the number of non-sorted result indices appended,
and no controller or support-service work moved to another state.  The full
matrix is in
`reports/releases/topk_append_ack_chain_k_sweep_20260817.csv`.

## Timing and resources

Out-of-context synthesis at 100 MHz:

| Metric | Baseline | New | Delta |
|---|---:|---:|---:|
| WNS | +0.850 ns | +0.850 ns | 0 |
| Total LUT | 121,302 | 121,359 | +57 (+0.047%) |
| Logic LUT | 119,152 | 119,209 | +57 |
| LUTRAM | 2,144 | 2,144 | 0 |
| SRL | 6 | 6 | 0 |
| FF | 53,281 | 53,281 | 0 |
| RAMB36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |

TNS is zero.  LUT growth is lower than both K8 and full-sweep cycle-reduction
percentages; timing margin and every other resource count are unchanged.  The
candidate therefore meets the retention criteria.

## Reproduction logs

- Profile baseline: `logs/sim/v2/wide_internal_baseline_k8_20260817`
- K8: `logs/sim/v2/topk_append_ack_chain_k8_20260817`
- Full sweep: `logs/sim/v2/topk_append_ack_chain_full_20260817`
- OOC: `logs/synth/v2/topk_append_ack_chain_ooc_20260817`

Raw logs remain ignored; RTL, the cycle matrix, verification profiler, and
this sign-off report are versioned.

## Next direction

Profile the sorted append path separately.  Its K8 `S_SORT_WAIT` residency is
256 clocks.  A controlled next trial may consume scan position zero on the
registered append ACK edge, using the existing result list and used mask.  It
must not add a wide selection mux or reduce WNS below +0.2 ns, and should be
rejected if LUT growth exceeds its smaller cycle benefit.
