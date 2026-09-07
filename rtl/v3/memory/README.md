# V3 Reusable Memory Primitives

These modules provide explicit synchronous memory contracts without using
`ram_style` or synthesis-strategy directives.

- `recon_sdp_ram`: one write port and one synchronous read port.
- `recon_1w2r_ram`: one write port and two coherent synchronous read ports,
  implemented by replicating the storage.
- `recon_epoch_slot_map`: two-query index-to-slot map with constant-time clear
  through an epoch change.
- `support_coefficient_stripe_store`: 16-bank coefficient store with one
  RTL-arbitrated synchronous read service. A request returns either one scalar
  coefficient or one full 16-lane stripe; the architecture serializes those
  request classes, so each lane needs one `recon_sdp_ram` instead of a
  replicated `recon_1w2r_ram` pair. The default `96x27x2` workspace maps to
  16 RAMB18 primitives in Vivado 2018.1.

Synthesis uses the structural `xpm_memory_sdpram` block-memory implementation.
Non-synthesis simulation uses the behavioral model in `recon_sdp_ram`, so the
same RTL can be tested with Icarus Verilog and XSim. A read/write collision to
the same address returns the newly written data through a wrapper bypass.

The memory contents are not reset through fabric logic. `read_valid` defines
when read data is meaningful. `recon_epoch_slot_map` initializes its backing
store to zero and starts at epoch one, so unwritten entries are misses.

Vivado in-memory synthesis flows must source
`scripts/synth/load_v3_xpm_memory.tcl` before reading the V3 RTL.
