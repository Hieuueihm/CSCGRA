# M13 software loader aperture

Date: 2026-08-31

The loader is a second AXI4-Lite slave. It is not an alias or extension of the
fixed lifecycle CSR block at offsets `0x000` through `0x034`.

## Transaction model

- Software writes staging registers, then writes one command code.
- The command snapshots all staging fields.
- One backend transaction may be in flight.
- A command write returns `SLVERR` while the loader or lifecycle engine is busy.
- Loader busy suppresses context-image readiness at the lifecycle boundary, so
  the two AXI slaves cannot launch compute and mutate resident state together.
- Software polls `STATUS.pending`, checks `STATUS.error/code/detail`, then
  clears completion by writing bit 1 to `STATUS`.
- Hardware does not decode an algorithm ID. Software-selected context and
  memory images remain the algorithm authority.

## Common registers

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x000` | `IDENTIFICATION` | RO | `0x4c445233` (`LDR3`) |
| `0x004` | `VERSION` | RO | loader interface revision |
| `0x008` | `COMMAND` | WO | command code in bits `[2:0]` |
| `0x00c` | `STATUS` | RW1C | busy `[0]`, pending `[1]`, error `[2]`, completed command `[5:3]`, code `[13:6]`, preload ID `[19:14]` |
| `0x010` | `DETAIL` | RO | backend response detail |

## Staging registers

| Offset | Name | Fields |
|---:|---|---|
| `0x020` | `IMAGE_META` | bank `[0]`, plane `[7:4]`, address `[15:8]` |
| `0x024` | `IMAGE_DATA_LO` | context bits `[31:0]` |
| `0x028` | `IMAGE_DATA_MID` | context bits `[63:32]` |
| `0x02c` | `IMAGE_DATA_HI` | context bits `[71:64]` |
| `0x030` | `MEMORY_META` | bank `[0]`, configuration ID `[13:8]` |
| `0x034` | `MEMORY_DATA_LO` | configuration bits `[31:0]` |
| `0x038` | `MEMORY_DATA_HI` | configuration bits `[63:32]` |
| `0x040` | `SCALAR_META` | scalar address `[0]` |
| `0x044` | `SCALAR_DATA_LO` | scalar bits `[31:0]` |
| `0x048` | `SCALAR_DATA_HI` | scalar bits `[61:32]` |
| `0x050` | `SCRATCH_META` | bank `[2:0]`, address `[17:9]` |
| `0x054` | `SCRATCH_DATA_LO` | scratch word bits `[31:0]` |
| `0x058` | `SCRATCH_DATA_MID` | scratch word bits `[63:32]` |
| `0x05c` | `SCRATCH_DATA_HI` | scratch word bits `[71:64]` |
| `0x060` | `PRELOAD_SRC_LO` | DDR source address `[31:0]` |
| `0x064` | `PRELOAD_SRC_HI` | DDR source address `[63:32]` |
| `0x068` | `PRELOAD_META` | memory-configuration ID `[5:0]` |
| `0x06c` | `PRELOAD_CFG_LO` | preload configuration `[31:0]` |
| `0x070` | `PRELOAD_CFG_HI` | preload configuration `[63:32]` |

## Commands

| Code | Operation |
|---:|---|
| `1` | context image word write |
| `2` | context image finalize |
| `3` | memory-configuration write |
| `4` | scalar preload |
| `5` | scalar state clear |
| `6` | direct scratchpad word write |
| `7` | scratchpad DMA preload |

All synthesis, optimization, placement and routing flows remain directive-free.
