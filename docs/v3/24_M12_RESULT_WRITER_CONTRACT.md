# M12 Result Writer Contract

Date: **2026-08-29**  
Status: **leaf implementation in progress**.

## Ownership

- Software package IDs remain outside RTL. The result writer receives only the
  finalized sparse state and active run configuration.
- `reconstruction_result_writer` owns dense expansion, sparse serialization,
  result-header commit, DMA write errors and abort drain.
- Active Vivado flows use no synthesis or implementation directives.

## Memory Format

Every selected destination reserves 16 bytes at its base. Payload begins at
`base + 16`.

- Dense payload: `N` sign-extended S27 coefficients as little-endian 32-bit
  words, padded with zeros to a 128-bit beat.
- Sparse payload: `support_count` 64-bit records. Bits `[31:0]` are the
  sign-extended S27 coefficient; bits `[63:32]` are the zero-extended index.
- Dense and sparse packers build one element/record per cycle into a 128-bit
  beat. This time-multiplexes support lookup instead of replicating comparator
  and selector farms.
- The single authoritative 128-bit success header is written last. Dense mode
  places it at the dense base. Sparse and both modes place it at the sparse
  base. In both mode, the dense base reserves its first 16 bytes but carries no
  independent success header.

Header layout:

```text
[31:0]    magic = 0x43535233
[63:32]   user_tag
[74:64]   signal_length
[81:75]   support_count
[85:82]   stop_reason
[87:86]   result_mode
[95:88]   format_revision = 1
[108:96]  dense payload bytes
[119:109] sparse payload bytes
[120]     success = 1
[127:121] reserved = 0
```

## Transaction Semantics

- Bodies are written before the authoritative header. Completion is emitted
  only after every selected body and the header return a clean DMA completion.
- A DMA error emits an error terminal, emits no success completion and starts
  no later transaction.
- Abort before request acceptance emits an aborted completion immediately.
  Abort after acceptance drains that DMA transaction, emits an aborted
  completion and does not write later bodies or the success header.
- Requests are split at 4 KiB boundaries and never exceed 4096 bytes.
- Request and write payloads remain stable under backpressure.

## Gate Order

1. Leaf dense/sparse/both golden and random backpressure.
2. Abort and AXI error drain.
3. Property compile/elaboration.
4. OOC WNS `>= +1.0 ns` with default Vivado flow.
5. DMA arbiter, active configuration, support state and CSR lifecycle
   integration.
