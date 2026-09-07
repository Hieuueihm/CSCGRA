# CSCGRA project status

Updated: 2026-08-23

The active checkout is **UNVALIDATED**. The single authoritative live status is
[reports/v2/CURRENT_STATUS.md](../reports/v2/CURRENT_STATUS.md). Dated reports
and `CONTINUATION.md` are historical evidence only.

## Active ownership

| Item | Authority |
| --- | --- |
| Project selection and release gates | `config/project.json` |
| RTL tool configuration | `config/rtl-v2.json` |
| Synthesizable source and compile order | `rtl/v2/files.f` |
| Mathematical reference | `models/reference/canonical.py` |
| Fixed-point hardware reference/golden generator | `models/reference/hardware.py` |
| Canonical RTL regression | `verification/v2/run1/tb_run1_k_sweep.v` |
| Formal safety properties | `rtl/v2` under `FORMAL` |
| Formal harnesses/tasks | `verification/formal` |
| Current validation state | `reports/v2/CURRENT_STATUS.md` |

`archive/v1`, `scripts/legacy`, `verification/research`, dated reports, and
chronological notes are non-authoritative for the active build.

## Active architecture

The retained v2 architecture uses four PE rows and eight columns, 24-bit Q16
data, a 16-entry support/least-squares capacity, strict registered PE0 ingress,
streamed correlation/residual/prune/top-K paths, and a regularized LDLT solver
with factor reuse. CoSaMP/SP at K16 remain explicit 2K-capacity exclusions.

The controller may have at most one active LS request. Payload, mode, owner,
tag and valid must cross each registered PE boundary together. Golden values
must never be changed to make an RTL candidate pass.

## Required gates

1. `scripts/run.ps1 -Flow check` passes.
2. Focused tests pass before the full regression.
3. Full supported sweep is exactly 348 PASS / 0 FAIL with documented skips.
4. All formal tasks prove against the same RTL SHA-256.
5. OOC and routed timing are from that same RTL SHA-256, with WNS >= +0.2 ns,
   TNS 0, and zero routing errors.
6. Cycles, LUT/FF, BRAM and DSP are reported together from matching provenance.

Until every gate is recorded in the current status file, the checkout remains
`UNVALIDATED` regardless of results retained from an older checkpoint.
