# v3 assertion/formal status

Formal-intent properties are embedded under `FORMAL` in:

- `axilite_slave.v`: independent-channel capture, response conservation,
  response stability and transaction holding;
- `reconstruction_csr.v`: command-to-pulse conservation, configuration alignment
  and busy stability, event-over-clear, first-error ownership, IRQ equation and
  decode alignment.

The project validation tool is Vivado 2018.1. The script
`scripts/formal/check_axilite_control_properties.ps1` compiles and elaborates those
properties with Vivado so stale/unsupported assertions fail the build.

Vivado 2018.1 is not a formal proof engine. Therefore this gate is reported as
**property elaboration**, never as a mathematical proof. A bounded/unbounded
proof result may only be claimed after an approved formal tool runs the same
properties with a documented harness and assumptions.

Context format revision 8 is current. M1-M10 FORMAL-guarded properties compile
and elaborate with the milestone scripts and execute in directed XSim where
enabled. These checks remain assertion/property elaboration, not mathematical
formal proof. M11+ properties remain specifications in
`docs/v3/10_DETAILED_IMPLEMENTATION_BLUEPRINT.md`.

## M7 assertion contract

M7 properties cover request/response conservation, stable backpressure,
Threefry folded-pass state, two-word gearbox ordering, cache prepare/fill and
capture/promote/replay state, provider STOP flush, and normalizer output
stability. Run `scripts/formal/check_m7_properties.ps1` for compile/elaboration
and `scripts/sim/run_m7.ps1 -EnableProperties` for directed execution.
## M2 assertion contract

M2 embeds synthesizable/procedural assertions under `FORMAL` in every DMA and
run-configuration module. The checked invariants include:

- AXI address/completion payload stability under backpressure;
- one DMA owner and one routed completion at a time;
- generated `WLAST` and legal one-burst request bounds;
- exactly one of configuration commit or terminal error;
- no commit after an invalid/faulted fetch;
- active parameter stability until terminal release;
- packer output stability and first-invalid-lane attribution.

Run `scripts/formal/check_m2_properties.ps1` for property compile/elaboration,
then `scripts/sim/run_m2.ps1 -EnableProperties` to execute those assertions in
the complete directed/backpressured XSim scenario. This is assertion-based
verification, not an unbounded mathematical proof; Vivado 2018.1 has no proof
engine.

## M3 assertion contract

M3 properties cover the five state-owning modules:

- no active-bank programming and atomic context validity;
- synchronous memory-configuration output stability and programmed-address use;
- no context commit before reservation legality succeeds;
- PC, loop counter, stall and safe-abort conservation;
- one phase/run terminal outcome and stable active-run ownership.

Run `scripts/formal/check_m3_properties.ps1` for compile/elaboration and
`scripts/sim/run_m3.ps1 -EnableProperties` to execute the assertions through
the generated control trace and directed fault paths. As with M1/M2, this is
assertion-based verification and not bounded or unbounded proof.
