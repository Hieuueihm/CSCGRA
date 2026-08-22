# sparse_loop_controller structure map

Maintainer's map of `rtl/v2/control/sparse_loop_controller.v`.  Line
references drift; register names and state names are the stable anchors.
State encodings live in `rtl/v2/control/controller_states.vh` and are a
frozen verification contract (`check_controller_state_encodings.py`).

The controller is a **single FSM**: one `always` block, sequential state
transitions, and therefore no concurrent access to any shared array.  Every
extraction or optimization must preserve the state sequence cycle-for-cycle
(the regression gate is a byte-identical 62-record cycle sum).

## Submodules already instantiated

| Instance | Module | Role |
|---|---|---|
| `u_ls_matrix_service` | `solver/ls_issue_engine.v` | one-active command boundary to the Gram/L/D/RHS storage service |
| `u_support_relation_unit` | `control/support_relation_unit.v` | combinational reuse-mode encoder (exact/prefix/truncate/swap-last) |

## Functional regions

### REGION factor-check (reuse qualification)

States `S_FACTOR_CHECK_INIT/SCAN/DONE`.  Streams the request support tuple
by tuple through the PE-row factor pipe (`factor_pipe_*`), accumulates
`factor_check_seen_mask_q` / fingerprint / unmatched bookkeeping, then
resolves the reuse mode via the hit predicates (`factor_exact_hit_w`...)
and normalizes `support_cache[]`.  Factor descriptors
(`factor_valid_q`, `factor_k_q`, config regs) are written by
`S_LDL_INV_DONE` and read here.

### REGION phi-scan (deterministic Phi regeneration)

States `S_SCAN_DIRECT`, `S_SCAN_DIRECT_STEP` plus the LFSR jump-window
helpers (`galois_step`, `lfsr_advance*`, `sparse_loop_lfsr_jump.vh`,
`phi_from_lfsr_state`).  Fills `phi_cache[0:MAX_K-1]` for the active
support.  `phi_cache` is read by the wide-operand mux (RHS/Gram batches),
the residual preloads, and `S_WR`.

### REGION wide-mul (64x64 limb multiplier sequencer)

The `wide_mul_state_q` FSM (`WIDE_MUL_IDLE..FINISH`) with operand regs
`wide_mul_a_q/b_q` and per-row `abs/neg/acc/partial/result` arrays.  Started
by the LDLT diagonal/border states and the forward/backward solve states.
The operand *selection* mux (which source feeds A/B) and the batch4
Gram/RHS product capture stay in the controller; only the sequencer is
region-scoped.  `wide_product_q` capture is shared with the batch4 paths.

### REGION writeback (sparse x scatter)

States `S_WX_COMMIT` / `S_WX_CLEAR` (plus comb-only decode for `S_WX`).
Maintains the coherent sparse view of the dense SPM x bank
(`x_support_cache[]`, `x_support_k_q`): COMMIT rewrites every current
support tuple unconditionally; CLEAR zeroes only true drops
(`support_cached_has_idx` gate in the row3 write-enable path).  Also emits
the corr support-token stream during commit.

### REGION residual (block-8 PE stream)

States `S_WR_ACC_INIT` / `S_RESID_PE_WAIT` / `S_WR` / `S_WR_MESH_WAIT` /
`S_WR_MESH_COMMIT` plus the `residual_pipe_*` r1..r5 tagged pipeline that
runs outside the main case, gated on `S_RESID_PE_WAIT`.  Computes
`r = y - Phi_S x` in block-8 transactions through the four PE rows and
commits the residual vector to the SPM R bank.

### Solver core (not yet a region)

Gram accumulation (`S_ACC*`/`S_GRAM*`), LDLT factorization
(`S_LDL_*`, ~25 states), forward solve (`S_ELIM_*`), diagonal solve
(`S_BACK_ACC*`), backward solve (`S_BACK_*`), the shared radix-4 divider
(`S_DIV_*`), and the algorithm-specific score/update states
(`S_IHT_*`, `S_MP_*`, `S_GP_*`, `S_CORR_*`, `S_PRUNE_*`).

## Shared resources and their sequencing

| Resource | Written by | Read by |
|---|---|---|
| `support_cache[]` | S_IDLE snapshot, factor-check normalize | phi-scan, writeback (`support_cached_at/has_idx`), coeff lookup |
| `phi_cache[]` | S_PRIME, phi-scan, several drain states | wide-operand mux, residual preloads, S_WR |
| `wide_product_q` | wide-mul FSM, batch4 capture | LDLT/solve consumers |
| `write_idx/write_limit/write_value` | writeback, PRIME/ACC/WR/MESH/MP/PRUNE states | row3 write path, loop exits |
| `rhs_block_base` | ACC/Gram region, residual region | both regions (sequentially) |
| `phase_residual` | PRIME, writeback phase flip | scan exit mux, `pe_sparse_op`, TBs |

Because access is strictly sequential, ownership may move between regions
as long as handshakes keep the cycle order unchanged.
