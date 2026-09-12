# AXI-Lite host register map

The wrapper also exposes the bounded payload DMA register window at
`0x300..0x33c`; see `PAYLOAD_DMA.md`. It is an AXI4 master data plane and does
not replace the legacy AXI4-Lite mailbox commands.

This document defines the `csr_top` control ABI: a 32-bit AXI4-Lite slave with
a 12-bit byte address and a 4 KiB aperture, without control-bus bursts. The
separate 128-bit AXI4 master handles bounded payload DMA as specified in
`PAYLOAD_DMA.md`. `s_axi_aclk` is the only clock.
`s_axi_awprot` and `s_axi_arprot` are standard AXI protection inputs;
this wrapper does not apply privilege or security filtering. `s_axi_aresetn`
is sampled by a two-flop synchronizer; the native core sees a synchronous
active-high reset after synchronized release.

All addresses below are byte offsets. Only addresses with `addr[1:0] == 0`
are legal. The complete 12-bit address is compared; offsets are not masked or
aliased. An address outside the listed windows, including an address in the
unused part of the 4 KiB aperture, returns `SLVERR` (`2'b10`). There are no
registers above `12'hfff` because the AXI address port is exactly 12 bits.

## Access and transaction rules

| Item | Rule |
|---|---|
| AXI writes | AW and W are independent one-entry buffers. A single write is issued only after both are captured. One B response is held until `BREADY`. |
| AXI reads | One AR is accepted while no R response is held. R data and response remain stable until `RREADY`. |
| WSTRB | Each enabled byte updates only that byte. A zero strobe is a successful no-op for ordinary RW registers. Reserved bytes/bits read zero and are ignored on staging writes. |
| Invalid write | Bad alignment, unknown offset, RO offset, malformed command, unsafe mutation, or a command that cannot be accepted returns `SLVERR` and has no side effect. |
| Command | `COMMAND` is write-one and must contain exactly one enabled command bit after WSTRB masking. `CANCEL` is independently recoverable while another native command is pending. |
| Command pending | A successful AXI write means the wrapper accepted the command request. `STATUS.COMMAND_PENDING` remains set until the native operation is accepted or its response is captured. Software must not infer completion from the B response. |
| Mailboxes | DONE, result response, host response and load status are single-entry sticky mailboxes. `ACK` is W1C; an unread mailbox blocks new commands. A new event has priority over same-cycle W1C clearing and replaces the just-cleared slot. |
| Cancel | While DMA owns the native ports, CANCEL only cancels and drains DMA; poll DMA.STATUS.DONE, not legacy CANCEL_SEEN. Otherwise CANCEL flushes native command/response ownership and wrapper mailboxes, preserving the loaded image and committed result bank; native Phi follows its invalidate contract. AXI-Lite B/R and partial AW/W buffers are preserved. |
| Native payloads | Every valid payload is registered and held until its native ready handshake. A command snapshots all staging fields at command acceptance; later staging writes are rejected while pending. |
| Reset | Reset clears AW/W buffers, AXI B/R responses, command state, wrapper mailboxes, error/event state and Phi epoch. Native image/Phi/committed memories follow their native reset contracts. |

`SLVERR` is used for protocol/register access errors; the wrapper does not
generate `DECERR`. A native engine fault is returned in the relevant captured
mailbox and in the DONE/status fields, not converted into an AXI transport
error after the command was accepted.

## Core control and status

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x000` | RO/`0x00010000` | IP identity/version (`CSR_HOST_VERSION`). |
| `0x004` | RO/0 | `STATUS`: bit0 busy; bit1 image valid; bit2 image loading; bit3 Phi valid; bit4 Phi loading; bit5 command pending; bit6 any mailbox valid; bit7 DONE mailbox; bit8 host response mailbox; bit9 result response mailbox; bit10 load-status mailbox; bit11 command ready; bit12 committed valid; bit13 cancel seen; bit14 error valid; bit15 AXI transport ready. |
| `0x008` | RW/0 | `IRQ`: bit0 enable; bit1 pending (RO). Byte 0 only; any masked bit above bit0 returns `SLVERR` and has no side effect. IRQ is optional sticky notification for DONE, native response, load status or wrapper error. `ACK.IRQ` clears pending. |
| `0x00c` | WO/W1C/0 | `ACK`: bit0 DONE mailbox; bit1 result mailbox; bit2 host mailbox; bit3 load status; bit4 wrapper error; bit5 IRQ. Only bits `[5:0]` may be strobed nonzero; reserved bits return `SLVERR`. New events win over same-cycle clearing. |
| `0x010` | WO/W1/0 | `COMMAND`: bit0 START; bit1 CANCEL; bit2 LOAD_BEGIN; bit3 LOAD_ITEM; bit4 PHI_BEGIN; bit5 HOST_READ; bit6 HOST_WRITE; bit7 RESULT_READ. Exactly one bit is required after WSTRB masking, and masked reserved bits `[31:8]` must be zero. |
| `0x014` | RO/0 | Last wrapper error: bits `[3:0]` class, `[7:4]` detail, `[15:8]` offending low address byte, `[27:16]` offending 12-bit offset. Sticky until `ACK.ERROR` or reset. |
| `0x018` | RO/0 | Last event: bits `[3:0]` event code, `[7:4]` active command, `[23:8]` event sequence. |

## START staging

All START fields reset to zero. Writes are RW only while no command is pending,
no mailbox is unread and no native operation is active. The command snapshots
every field.
DMA ownership also blocks START/staging; a failed or cancelled upload blocks
START until a complete same-block/count upload retry succeeds or global reset.

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x020` | RW/0 | Rows in bits `[7:0]`; other bits reserved. |
| `0x024` | RW/0 | Columns in bits `[10:0]`. |
| `0x028` | RW/0 | Positive C18 scale in bits `[17:0]`. |
| `0x02c` | RW/0 | Phi generation in bits `[31:0]`. |
| `0x030` | RW/0 | Job `[15:0]`, start tag `[31:16]`. |
| `0x034`-`0x040` | RW/0 | 128-bit key, little-endian 32-bit words: key word 0 is at `0x034`. |
| `0x044` | RW/0 | Format `[7:0]`; this integration requires format `1`. |
| `0x048` | RW/0 | Storage mode `[1:0]` (`1` X24F20, `2` D18F14); signed exponent `[14:8]`; active-support flag bit16. |
| `0x04c` | RW/0 | Positive instruction watchdog limit `[31:0]`. |

## Program/image loading

The loader counts are native image counts. `LOAD_BEGIN` snapshots them and
the revision/attestation fields; `verified` is a host attestation and does
not claim RTL hashing. The native loader expects program kind `0`, template
kind `1`, vector kind `2`, and constant kind `3` in `LOAD_ITEM`.

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x050` | RW/0 | Program count `[10:0]`. |
| `0x054` | RW/0 | Constant count `[10:0]`. |
| `0x058` | RW/0 | Revision `[7:0]`; template count `[12:8]` (1..16); vector count `[18:13]` (1..32); host verified attestation bit19. |
| `0x05c` | RW/0 | Item kind `[2:0]`; item index `[18:3]`; item last bit19. |
| `0x060`-`0x06c` | RW/0 | 128-bit item data, little-endian 32-bit words. The native `LOAD_ITEM` payload is held until `load_ready`. |
| `0x2c0` | RO/0 | Image state: bit0 image valid; bit1 loader status mailbox valid; bits `[7:4]` load fault; bit8 accepted image load is still owned by the wrapper. |

The native limits are program count `1..1024`, template count `1..16`,
vector count `1..32`, constant count `0..1024`. `LOAD_BEGIN` or an item that
the native loader rejects is reported through the sticky load-status mailbox.

## Phi staging and status

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x070` | RW/0 | Phi seed `[31:0]`. |
| `0x074` | RW/0 | Rows `[7:0]`, columns `[26:16]`. |
| `0x078`-`0x084` | RW/0 | Phi key, little-endian 32-bit words. |
| `0x088` | RW/0 | Phi generation `[31:0]`. |
| `0x08c` | RW/0 | Phi job `[15:0]`, tag `[31:16]`. |
| `0x090` | RW/0 | Phi format `[7:0]`. |
| `0x2c4` | RO/0 | Phi state: bit0 valid for the last accepted fill; bit1 accepted fill pending or native loading; bits `[7:4]` last accepted-fill fault. |
| `0x2c8` | RO/0 | Last accepted Phi descriptor identity snapshot: job `[15:0]`, format `[23:16]`. It is not mutable staging and is captured when native `p_begin` is accepted. |
| `0x2cc` | RO/0 | Last accepted Phi generation snapshot. |
| `0x2d0` | RO/0 | Last accepted Phi seed snapshot. |
| `0x2d4` | RO/0 | Phi begin acceptance epoch, incremented only when a new Phi begin is accepted. |

`p_valid` may continue to describe the old published image while a newly
accepted fill is loading. The wrapper therefore tracks accepted-fill ownership:
it waits for loading to be observed and then for loading to clear (or a native
fault) before updating `PHI_STATUS.valid` and the last-fill fault. Software
must use the accepted epoch and wait for `PHI_STATUS.pending == 0`; the old
native `p_valid` is never used as new-fill completion.

## Host block staging and response

The staging host block uses one native 32-lane block. Every lane register is
32 bits wide but only bits `[26:0]` are meaningful raw signed-27 data; reads
return zero in bits `[31:27]`, and writes ignore those five bits.

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x0a0` | RW/0 | Block `[8:0]`; write direction bit16. |
| `0x0a4` | RW/0 | Lane mask `[31:0]`. |
| `0x0a8` | RW/0 | Native request tag `[15:0]`. |
| `0x0ac`-`0x128` | RW/0 | Lane 0..31 raw S27 staging, one lane per word. |
| `0x160` | RO/0 | Captured response block `[8:0]`, write bit16, mailbox valid bit24. |
| `0x164` | RO/0 | Captured response lane mask `[31:0]`. |
| `0x168` | RO/0 | Captured response tag `[15:0]`, fault `[19:16]`. |
| `0x16c`-`0x1e8` | RO/0 | Captured response lane 0..31 raw S27, high five bits zero. |

`HOST_READ` and `HOST_WRITE` are MMIO commands, not DMA descriptors. A
request remains valid until native `host_ready`; its response is captured
and held until `ACK.HOST`. A host response cannot be overwritten.

## Result reads

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x140` | RW/0 | Result index `[9:0]`, request tag `[31:16]`. |
| `0x148` | RO/0 | Captured raw signed-27 result `[26:0]`, fault `[31:28]`. |
| `0x14c` | RO/0 | Returned index `[9:0]`, request tag `[31:16]`. |
| `0x150` | RO/0 | Storage mode `[1:0]`, signed exponent `[8:2]`, committed length `[19:9]`. |
| `0x154` | RO/0 | Committed job `[15:0]`, returned response tag `[31:16]`. |
| `0x158` | RO/0 | Format `[7:0]`; mailbox valid bit16. |
| `0x15c` | RO/0 | Result response fault `[3:0]`; mailbox valid bit8. |

`RESULT_READ` snapshots index and tag at command acceptance, holds the native
request until `read_ready`, then captures the entire response identity and
raw S27 payload. It is acknowledged with `ACK.RESULT`.

## DONE and committed metadata

| Offset | Access/reset | Field definition |
|---|---|---|
| `0x200` | RO/0 | DONE fault `[3:0]`, detail `[7:4]`, status `[15:8]`, committed bit16, mailbox valid bit17. |
| `0x204` | RO/0 | Outer iterations `[15:0]`, inner iterations `[31:16]`. |
| `0x208` | RO/0 | Support count `[6:0]`, format `[15:8]`, job `[31:16]`. |
| `0x20c` | RO/0 | DONE tag `[15:0]`. |
| `0x210`/`0x214` | RO/0 | Coherent 64-bit job-cycle count, low/high words. This is captured with DONE and does not change while the mailbox is held. |
| `0x220` | RO/0 | Committed valid bit0; active-support bit1; rows `[9:2]`; mode `[11:10]`; signed exponent `[18:12]`; committed status `[26:19]`. |
| `0x224` | RO/0 | Committed length `[10:0]`, support count `[18:12]`. |
| `0x228` | RO/0 | Committed outer `[15:0]`, inner `[31:16]`. |
| `0x22c` | RO/0 | Committed job `[15:0]`, tag `[31:16]`. |
| `0x230` | RO/0 | Committed format `[7:0]`. |
| `0x234`-`0x240` | RO/0 | Committed key, little-endian 32-bit words. |
| `0x244` | RO/0 | Committed Phi/operator generation. |
| `0x248`-`0x2bc` | RO/0 | Thirty 32-bit words containing the native 960-bit ordered support list, little-endian. Unused high bits in the final word read zero. |

The DONE mailbox is a captured completion and is not produced by CANCEL.
Failed or canceled candidates preserve the prior committed bank according to
the native recovery contract.

The `COMMITTED_*` registers expose native live committed metadata, not a
wrapper-captured multiword snapshot. Software must read them only while no
`START` command is pending or running, and before acknowledging `DONE` or
starting the next job. Individual words are stable per native contract, but
the register block is not atomic across multiple reads.

## Software sequencing

1. Write staging fields with ordinary AXI writes and wait for each B response.
2. Write one `COMMAND` bit. A successful B means accepted by the wrapper;
   poll `STATUS.COMMAND_PENDING` and the applicable mailbox/state.
3. For load items, issue the next item only after the previous command B
   response; acknowledge a final load-status mailbox before starting a job.
4. For START, wait for DONE mailbox valid, read all DONE fields, then use
   `ACK.DONE`. Read committed X through repeated RESULT_READ commands and
   acknowledge each result response.
5. If a command remains pending, issue a one-hot CANCEL. CANCEL has no DONE
   response; software observes `STATUS.CANCEL_SEEN` and the cleared pending
   state, while any already accepted AXI B/R response remains available.
