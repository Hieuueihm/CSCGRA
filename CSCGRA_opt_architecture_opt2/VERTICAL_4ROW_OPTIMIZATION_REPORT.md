# Four-row PE optimization report

## Architectural invariant

All controller, SPM, and external operands enter the PE array at physical row 0.
Rows 1, 2, and 3 may consume a token only after it has advanced through the
registered vertical links PE0 -> PE1 -> PE2 -> PE3, one row per clock.  A
logical mapping such as `rank mod 4` selects the owner row; it never creates a
direct lower-row input.  Results from distributed operations are committed only
after the corresponding tag reaches PE3.

Simulation assertions check row-to-row valid, payload, score, index, factor tag,
and wide-LDLT tag provenance.  The max-iteration eight-algorithm regression
completed with 8/8 golden checks passing and no provenance assertion failures.

## Implemented optimizations

- Correlation is striped over all four rows.  Each row owns one sample phase
  modulo four and accumulates a full-precision partial sum.
- Residual block-8 multiplication is striped by support rank modulo four.  The
  real opcode-3 path now remains visible from the controller to the PE array;
  residual operands and valid advance only through the registered vertical
  chain.
- Streaming top-K enters row 0 as serialized score tokens.  Each row maintains
  an exact local candidate set for its owned indices; PE3 performs the final
  merge and is the only result-commit point.
- Factor-cache comparison is a tagged vertical pipeline.  Rows compare the
  cache ranks they own and PE3 returns the accumulated match mask.
- LDLT border update uses the four physical rows for four simultaneous signed
  64-bit products.  Four 16-bit limbs are mapped to the existing PE multipliers;
  the border-update request and row tag enter at PE0 and drain at PE3.
- LDLT factors are reused when the support signature matches.  HTP at 32
  iterations pays 870 LDLT-border cycles total rather than repeating the
  factorization every iteration.

Two residual integration defects found by enabling the real opcode were fixed:

1. `S_RESID_PE_WAIT3` now keeps the residual token and coefficient active while
   PE3 consumes the third registered hop.
2. Residual explicitly selects the propagated scalar operand instead of the
   column bus, and standalone `OP_RESID` is included in the PE issue enable.

## Final cycle report

The following numbers are from
`runs/opt2/vertical_profile_max_all8_xsim.log`.  Each wave entry is
`fill / steady / drain` cycles at the algorithm's configured maximum iteration.

| Algorithm | Iterations | Total cycles | Residual | Correlation | Top-K | Factor check | LDLT border |
|---|---:|---:|---:|---:|---:|---:|---:|
| OMP | 8 | 42,451 | 1,536 / 512 / 1,536 | 768 / 15,616 / 768 | 0 / 0 / 0 | 21 / 15 / 24 | 420 / 420 / 420 |
| CoSaMP | 8 | 132,322 | 3,072 / 2,816 / 3,072 | 768 / 15,616 / 768 | 768 / 1,280 / 768 | 48 / 136 / 48 | 8,658 / 8,658 / 8,658 |
| IHT | 16 | 73,341 | 3,072 / 1,024 / 3,072 | 1,536 / 31,232 / 1,536 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| HTP | 32 | 226,034 | 6,144 / 2,048 / 6,144 | 3,072 / 62,464 / 3,072 | 0 / 0 / 0 | 96 / 160 / 96 | 870 / 870 / 870 |
| SP | 8 | 137,483 | 3,072 / 2,816 / 3,072 | 768 / 15,616 / 768 | 0 / 0 / 0 | 48 / 136 / 48 | 8,658 / 8,658 / 8,658 |
| GP | 16 | 74,242 | 3,072 / 1,024 / 3,072 | 1,536 / 31,232 / 1,536 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| GOMP | 4 | 23,937 | 768 / 256 / 768 | 384 / 7,808 / 384 | 0 / 0 / 0 | 11 / 9 / 12 | 252 / 252 / 252 |
| MP | 32 | 107,457 | 6,144 / 2,048 / 6,144 | 3,072 / 62,464 / 3,072 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

The eight-algorithm total is 817,267 cycles, down 33,480 cycles (3.94%) from
the original 850,747-cycle baseline.

## Correctness regression

- Max-iteration noisy M=64/N=256/K=8 profile: 8 PASS, 0 FAIL.
- K-sweep over eight M/N/K cases from K=2 through K=16: 348 PASS, 0 FAIL.
- Large-measurement M=128/N=256/K=8 regression: 45 PASS, 0 FAIL.
- Direct post-fix OMP, IHT, and CoSaMP checks retained their expected cycle
  counts (42,451; 73,341; and 132,322 respectively).
- No PE vertical provenance assertion fired in these regressions.

## Synthesis result

Out-of-context synthesis for `xczu7ev-ffvc1156-2-e` completed with zero errors
and zero critical warnings:

- 108,803 LUTs, including 1,536 LUTRAMs
- 36,928 flip-flops
- 24 RAMB36
- 71 DSP48 blocks
- 100 MHz OOC target: WNS = -2.458 ns; worst data path = 12.448 ns

The current critical path ends at a `wide_mul_result_q` register in the LDLT
wide multiplier.  A combinational balanced-adder-tree experiment improved WNS
by only 0.063 ns while adding 5,053 LUTs and 6,946 flip-flops, so that experiment
was rejected and is not present in the source.

## Recommended next optimizations

1. **Stream multiple LDLT border products before draining.** Add an in-order
   transaction tag and small per-row partial-sum queue, issue the next PE0 limb
   token while the previous product advances through PE1-PE3, and drain only at
   the end of a product group.  This directly attacks the 8,658/8,658 fill/drain
   overhead in CoSaMP and SP without creating lower-row ingress.
2. **Pipeline the LDLT wide-result capture.** Register row0 issue control and/or
   the partial sum before sign correction and result capture.  This costs a
   controlled pipeline stage, but is more promising for 100 MHz than duplicating
   a combinational tree.  Tags must advance through the same new stage.
3. **Chain residual blocks.** Allow a new tagged block-8 residual token to enter
   PE0 every cycle and keep separate accumulators for blocks in flight.  PE3
   retires blocks in order.  This amortizes the residual fill/drain overhead,
   which is three times the steady count in IHT, HTP, GP, GOMP, and MP.
4. **Reduce top-K comparator cost conditionally.** Keep exact per-row capacity
   when exact global top-K is required, but serialize/reuse each row's insertion
   comparator or add a safe global threshold broadcast from PE3.  Do not reduce
   every local list to `K/4`; all global winners can legally belong to one row.
5. **Add a factor-signature precheck.** Compare a compact ordered support
   signature at PE0 before launching the full vertical cache scan; on signature
   mismatch, proceed with the existing exact tagged scan.  This saves common
   misses without weakening correctness.

Replacing the LS solver with QR is not the preferred cycle optimization here.
Incremental QR can improve numerical robustness for ill-conditioned support
matrices, but it requires rotations, square-root/reciprocal work, and more state.
The measured LDLT factor reuse is already effective.  QR is better kept as an
optional robustness mode or evaluated only after the LDLT streaming and timing
pipeline work above.
