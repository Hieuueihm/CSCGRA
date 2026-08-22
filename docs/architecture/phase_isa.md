# Unified sparse execution ISA

One fabric, eight algorithms, zero reconfiguration.  The ISA layer is the
paper's tooling contribution; this note is the architecture reference.

## Layers

| Layer | Artifact | Role |
|---|---|---|
| Algorithm spec | `models/reference/canonical.py` | float source of the 8 algorithms |
| Phase compiler | `sw/v2/tools/phase_compiler.py` | emits 64-bit context-word programs |
| Equivalence gate | `scripts/maintenance/check_phase_compiler.py` | proves compiler output byte-identical to the canonical TB builder (62 program images) |
| Sequencer | `rtl/v2/control/sequencer.v` | linear PC + one CF_LOOP iteration edge |
| Phase decode | `rtl/v2/control/phase_isa_decoder.v` | ctx word -> phase / engine / owner / dependency mask |
| Phase scheduler | `rtl/v2/control/phase_token_scheduler.v` | versioned tokens; owns the three cross-service fusions |
| Phase transport | `rtl/v2/control/phase_packet_pipe.v` | narrow control packets down the PE0->PE3 south link |

## Word formats

Class field `ctx[59:56]`: 4 reduce, 5 select/top-K, 6 candidate/support
service, 7 DMA, 8 sparse op, 9 control flow.  Constructors are shared by
the compiler, the canonical testbench, and the SoC C runner; encoders in
`phase_compiler.py` are the single Python reference.

## Phase graph per algorithm (loop body)

| Algorithm | Body phases |
|---|---|
| OMP | select-append, CORR, REFINE_SPARSE |
| GOMP | top-2 select, CORR, REFINE |
| CoSaMP | meta, top-2K, CORR, select/merge, REFINE, refine-top-K, copy-p0, REFINE |
| SP | as CoSaMP with top-K |
| IHT | meta, post-update-top-K, CORR_UPDATE, copy-p0, PRUNE_X, RESID |
| HTP | as IHT but REFINE instead of RESID |
| GP | select, CORR, GP_PROJECT, GP_UPDATE, RESID |
| MP | CORR, argmax, append, MP_UPDATE |

Dependency masks (`phase_isa_decoder.v`) make the data edges explicit:
e.g. select depends on correlation data (mask bit 0); support mutations
create a new support version; vector writes create vector versions.

## Invariants (verified by the 348-check sweep)

- One active LS request at a time (`ls_issue_engine` accept gate).
- Streaming transactions ingress at PE0 and traverse registered
  PE0->PE3 links; packets carry metadata only, payloads stay on the
  registered data paths.
- Batch replay (`BATCH_REPLAY=1`) extends the same ISA: one program
  solves B signals by replaying REFINE on the retained exact factor.

## Cycle attribution

Per-phase cycle counters (CSRs 0x074-0x088) attribute every program to
correlation / top-K / support / solve / residual / vector phases; the
compiler plus these counters give the paper's phase-level cost model
directly from hardware.
