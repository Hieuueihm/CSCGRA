# Phase-level abstract RTL model

`abstract_rtl.py` is the intermediate executable specification between the
frozen fixed-point canonical reference and the real Verilog RTL:

```text
canonical_fixed.py  ->  abstract_rtl.py  ->  phase trace manifest  ->  RTL
      (frozen)          (controller model)       (audit checkpoint)
```

The model uses the same signed-24-bit Q16 primitives as the canonical source,
but exposes controller-visible phase boundaries rather than RTL signals. The
phase sequence is explicit: `CORRELATION`, support selection or merge/prune,
`LS_SOLVE` where required, `PROJECT`/`LINE_SEARCH` for GP, `UPDATE_X`, and
`RESIDUAL`. Every phase records its iteration, active support, and payload
values in Python; the manifest stores deterministic SHA-256 digests so a
hardware phase can be checked without committing a large dump.

Run or verify the compact all-case/all-algorithm manifest with:

```powershell
python models/golden/run_abstract_rtl.py
python models/golden/run_abstract_rtl.py --check
```

For bring-up/debugging, `--dump-values` emits complete phase payloads. The
model calls `canonical_fixed.run_all` at completion and asserts exact equality
of `x`, residual, and support. A mismatch is therefore a real RTL migration
issue; the fixed canonical golden must not be regenerated to make it disappear.

Current status:

- The abstract model covers all eight algorithms and all eight configured
  cases.
- The generated manifest reports exact final-state agreement for every entry.
- Real RTL has only the canonical GP path migrated so far. CoSaMP remains a
  known hardware-capacity variant; its RTL must be changed phase by phase before
  it can claim canonical sign-off.
