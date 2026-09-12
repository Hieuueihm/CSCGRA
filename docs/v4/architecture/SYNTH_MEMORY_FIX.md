# Synthesis memory/cache correction

## RTL changes

`factor_store` retains one factor image, the same 32 logical bank indices,
384 valid addresses per bank, fill ordering, masked read/write semantics,
publication, cancellation and two response credits. The old 16 arrays each
contained two disjoint 512-word halves. The correction makes these halves
32 independent 512x27 RAM declarations and selects fill/request address and
data before one write statement per RAM. The read remains synchronous,
without another pipeline stage. The factor-store OOC probe confirms 32
RAMB18E2 cells and no Synth 8-4767 warning. This is not an extra factor copy.

`factor_panel_service` previously expanded each 32-lane cache update into
multiple writes to dynamically selected destinations. The correction
enumerates each fixed cache destination and tests its membership in the
current input/output block, selecting the corresponding source lane.
For example, a project result offset d writes cache word c exactly when
0 <= c-d < width, taking lane c-d. A range source with row offset r and
source bundle b writes word c exactly when 32*b <= c+r < 32*(b+1), taking
lane (c+r) mod 32 under the original source mask.

The original state-machine branches, metadata/fault priority, handshakes,
nonblocking assignment clock edges, arithmetic, rounding, PE count and
R1/R4 scheduling are unchanged. Unused cache words retain their old value;
no new reset, initialization, interconnect or mesh is introduced.

The final candidate additionally assembles all 32 response lanes before one
nonblocking slot write, and forms requests by selecting the source lane for
each fixed logical bank rather than assigning variable slices of a wide bus.
The latter is the inverse of the same bank=(row+column) mod32 mapping,
including narrow R4 DOT, narrow RANK, wide panels and row/column ranges.
These are combinational rewrites, not a programmable interconnect or a new
transaction schedule. The final candidate has a separate source-bound replay
under `final_candidate/replay/`; earlier root-level evidence is an intermediate
candidate and must not qualify the later source by itself.

## Evidence

See `reports/v4/synth_memory_fix_20260911/` for the before sources, exact
patches, source-bound focused gates, calibration and immutable full-program
replay. Thirty XSim unittest cases and eighteen compiler/parser tests pass.
Forty complete PIO/DMA traces match the pre-fix benchmark byte-for-byte
for ten algorithms, two geometries, K8 and actual eight iterations. All
recorded cycle buckets match, not only final result vectors.

The compiler calibration is remeasured with both mappings before rebinding
the two changed RTL hashes; all sixteen shape cycle entries remain equal.
The older slice-only replay guard and original benchmark guard are not
weakened. `scripts/v4/replay_synth_memory_fix.py` allows only the two declared
RTL files to differ from its immutable baseline.

Full-top synthesis is a separate gate. Read the final physical report rather
than inferring completion from per-module elaboration or from an OOC probe.
A 10 ns OOC clock and Vivado default directives do not establish interface
timing, placed/routed timing, maximum frequency, or board validation.

## Run-history correction

The early attempts after the RAM fix synthesized standalone modules, not
`csr_top`. The queued full-top launcher failed its evidence read before
Vivado started. An operator-created `synth_memory_fix_full.log` is therefore
not a full-top synthesis log. The first actual full-top run of this final
candidate starts at 17:13:58 +07:00 on September 11, 2026, using
`work/synth_memory_fix_top_1713.log` and
`work/v4_impl_synth_memory_fix_20260911/`. Its result must be read separately.
