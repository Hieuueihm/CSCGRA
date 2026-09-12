# v4 context image proposal (ISA revision 1)

**Clarification 2026-09-09:** this is the historical tile64/control256 image
reference. The integrated LSQR path instead loads a service128 program and
currently generates its PE words in kernel RTL. See
[CONTEXT_EXECUTION.md](CONTEXT_EXECUTION.md) for the actual boundary and the
proposed two-level loadable program plus kernel-context architecture.

This document defines the bounded compiler and loader artifact for the v4
candidate. The packed layout is unchanged. A [tile64 RTL decoder and scalar
execution subset](CONTEXT_RTL_CONTRACT.md), routed arrays and a
[control256/image execution subset](CONTROL_RTL_CONTRACT.md) now exist.
New bounded scalar/route images execute on RTL; the original GEMV
demonstrator templates remain marked
`NOT_EXECUTED` and `NOT_PROVEN`; scalar execution tests do not qualify those programs.

## From algorithm graph to a loadable image

The compiler flow is deliberately layered:

```text
algorithm graphs → kernels → RF/register and route allocation
                 → schedule → dimension-free loop templates
                 → context images → loader → PE arrays
```

Algorithm identity is selected by the graph and kernel compiler. It is not
encoded as a special control opcode. A kernel describes generic operations,
operands, predicates, address descriptors, and loop control. The loader
replaces one idle image at a time; this proposal does not claim that all eleven
programs are resident simultaneously.

## Physical budget

There is one active image with 256 issue words. Every issue word has 32
distinct PE slots, each 64 bits, plus a separate 256-bit control word:

| payload | calculation | bytes |
|---|---:|---:|
| tile slots | 256 × 32 × 64 bits | 65,536 |
| control | 256 × 256 bits | 8,192 |
| total | 256 issue words | **73,728 (72 KiB)** |

The image is emitted as `tile_00.hex` through `tile_31.hex` and
`control.hex`. `manifest.json` records revision, dimensions, SHA-256 hashes,
metadata, and a compact disassembly. Hash verification occurs before the
loader accepts a payload. A corrupted or stale tile/control file is therefore
a load failure, rather than an execution-time surprise.

## Tile word, revision 1

The 64-bit word is packed least-significant field first. The widths are exactly

```text
opcode6 srcA_kind4 srcB_kind4 srcA_reg3 srcB_reg3 dst_reg3
rf_write1 acc_write1 predicate3 format3
routeN3 routeE3 routeS3 routeW3 immediate16 reserved5
```

The sum is 64 bits. Unknown enum values, negative values, values outside their
field width, and nonzero reserved bits are rejected. `NOP` has no payload.
ALU opcodes (`CLEAR`, `READ`, `MAC`, `ADD`, `SUB`, `MUL`, `MOV`, `STORE`,
`CMP`, `SELECT`) and the registered router are separate fields, so an ALU
operation may issue with route sideband traffic in the same issue word.
`ROUTE` is also available when no ALU operation is needed and must name at
least one direction. Route direction is checked against the
4×4 coordinates within the PE's own cluster: north/east/south/west at an
outer edge is rejected. PE 0–15 and PE 16–31 are separate clusters, so an
image cannot create an inter-cluster edge through this format.

When an operand kind is `LINK`, its 3-bit register selector is an incoming
direction selector: `src*_reg=0` reads north, `1` east, `2` south, and `3`
west. Selectors 4–7 are rejected, as are reads from an absent edge. Route
fields name outgoing directions and carry one of the `VALUE`, `ACC`, or
`RESULT` payload selectors.

## Control word, revision 1 proposal

Control fields are generic descriptors rather than algorithm tags:

```text
kind4 flags4 repeat8 count16 loop_target8 branch_target8 predicate3
address_mode3 immediate_address24 stride16 immediate32 reserved130
```

This is 256 bits. `LOOP_BEGIN` requires a nonzero count and a target within
the 256-word image; `LOOP_END` and `BRANCH` have the same target bound. The
address fields describe matrix/vector/result/scratch streams and are proposals
for the loader/feeder interface. Their presence does not imply that the RAM,
branch timing, or backpressure behavior has been implemented.

## GEMV demonstrator templates

`build_gemv_template(R)` emits a bounded template for R1 or R4 using the phase
order already present in `compiler/v4/mapping.py`:

- R1: clear (with first-read/prefetch descriptor), read, MAC loop, store.
- R4: clear, read/MAC loop, pair route, pair add, cross route 1, cross route 2,
  final add, store.

The read issue and following MAC issue make the one-cycle synchronous matrix
read latency explicit; the loop's last read is consequently before its last
MAC. This conservative serialized template has `template_initiation_interval:
UNKNOWN`; the existing mapping model's II=1 read/MAC overlap remains a
reference contract to be implemented and checked, not a property of this
image. R4 routes are west-only reductions within each 4-PE group, matching the
existing legal-neighbor schedule and preserving the one-cycle registered-link
contract. The templates use loop descriptors instead of expanding all cycles.

For the configured 128×1024 GEMV, the existing analytic schedule is thousands
of cycles (R1 is 4×(1024+2), R4 is 16×(256+7)); that does not mean the compact
template itself exceeds the 256-word context. Conversely, fitting the template
is not proof that its expansion, stalls, or every complete recovery program
fits. Binary round-trip and image validation are separate from execution and
RTL equivalence proofs. No synthesis, timing, or full eleven-program capacity
claim follows from this artifact.

The R4 inner loop counts reduction blocks, `ceil(reduction_count/4)`, and its
address descriptor advances by four. If the reduction length is not divisible
by four, the final block needs feeder-side invalid-lane predicates; the image
records this as `UNRESOLVED_FEEDER_PREDICATE_FOR_FINAL_PARTIAL_BLOCK` and does
not claim correct tail execution.

The v4 count is 32 true PE slots with one global issue controller. A v3
broadcast/snapshot representation with 16 logical slots is not interchangeable
with this image format.

For a quick export, run `python -m compiler.v4.context_image
--reduction-lanes 1 --output <directory>` (use `4` for the R4 template). The
CLI writes all payloads and prints used issue/tile/control word counts and the
SHA-256 map; `load_image` performs the same structural and hash checks.
