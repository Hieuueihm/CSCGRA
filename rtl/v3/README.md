# CSCGRA RTL v3

v3 is a clean implementation tree. It does not instantiate any `rtl/v2`
module.

The current hierarchy, naming and register audit is recorded in
[`reports/v3/RTL_CLEANUP_STATUS.md`](../../reports/v3/RTL_CLEANUP_STATUS.md).

The implemented boundaries are the AXI4-Lite reconstruction control interface,
the M2 AXI4 DMA/run-configuration ingress, the M3 context/control execution
spine, M4 scratchpad/stream transport, M4.1 DMA preload/residency seam, M5
shared arithmetic resources, M6 homogeneous CGRA, M7 generated Phi and the
M8-M10 integration/refinement path. The active build uses run-configuration
revision 4/context revision 8:

| Source folder | Single ownership rule |
| --- | --- |
| `host_interface` | AXI4-Lite transport and software-visible CSR only |
| `reconstruction_control` | reconstruction configuration lifetime and phase CFG |
| `context_control` | context/configuration storage, certification and array PC only |
| `data_movement` | AXI DMA, preload, scratchpad and vector streams only |
| `arithmetic` | compiler-scheduled reduction, scalar and vector functional units |
| `cgra` | stream routing and homogeneous PE/switchbox/cluster fabric |
| `phi` | coordinate-addressed symbol generation, stream modes, cache and runtime scale |
| `top` | integration only; no algorithm or datapath logic |

Folder names describe physical RTL ownership. The paper still presents six
logical macroblocks; that presentation does not force ambiguous source folders.

Signal names follow one compact RTL vocabulary. Module names keep the full
hardware function, while ports and local signals remove words already supplied
by that module's scope: `cfg`, `ctx`, `img`, `req`, `resp`, `rd`, `wr`, `addr`,
`count` and `valid` are the standard abbreviations. Algorithm terms such as
`support`, `residual`, `solver` and `refinement` remain explicit. Generated
`RECON_*` architecture/ISA constants are not abbreviated because they form the
compiler-to-RTL contract.

- `include/reconstruction_control_defs.vh`: locked build/numeric constants and
  CSR offsets;
- `host_interface/axi4lite_slave.v`: AXI4-Lite transport with independent
  AW/W capture;
- `host_interface/reconstruction_csr.v`: compact 14-word CSR decode,
  one run-configuration address, sticky terminal events and IRQ ownership;
- `top/top.v`: top-level AXI4-Lite control integration.

Run parameters, generated-Phi seed and DMA addresses live in one aligned
64-byte run-configuration block fetched after START. AXI4-Lite stores only its
address, so there is no duplicated shadow bank for each algorithm parameter or
second active-address register. Address writes are rejected while busy; the
run-configuration fetcher captures the address together with the START pulse.
There is no external matrix source/base/stride register. M7 adds only the
bounded active/candidate sign cache; no full sensing matrix is stored.

M2 adds `reconstruction_configuration_unit`, a fixed-priority four-client
`memory_dma_engine`, read/write burst engines and `dma_element_normalizer`. The DMA
master is 128 bit, one transaction owner at a time and one legal burst up to
4096 bytes. The 4096-byte case is explicitly tested because it is exactly one
dense N=1024 vector.

M3 adds the two-bank atomic `context_image_store`, four-read-port synchronous
`memory_configuration_store`, generated `context_write_certifier`,
FORMAL/test-only full-bundle `context_reservation_guard`,
`array_context_sequencer` and `reconstruction_phase_controller`. The compiler-generated test
image is used only to verify control execution; it is not a placeholder for the
eight real algorithm programs.

The normative module order is
[`docs/v3/13_MODULE_IMPLEMENTATION_PLAN.md`](../../docs/v3/13_MODULE_IMPLEMENTATION_PLAN.md).
The standalone M9a `topk_selection_unit` is implemented and measured. No proxy
candidate collector, support-state owner or restricted-refinement RTL exists yet.
Capability status prevents remaining unowned opcodes from entering a certified
image; the M5 resource router still faults opcodes outside its arithmetic ownership. The current `top` deliberately remains the M1 temporary
control seam until M8 integration and the M11 resident image exist; M4 does not add fake compute
owners merely to expose a final-looking wrapper.

M1 control-only evidence (2026-08-24): Vivado 2018.1 `xvlog/xelab/xsim` PASS,
FORMAL-guarded property elaboration PASS, and ZCU106 OOC synthesis PASS with
240 LUT/225 FF/0 BRAM/0 DSP and post-synthesis WNS `+4.530 ns` at 150 MHz.
This is not datapath or full-design sign-off.

M2 evidence (2026-08-24): two Vivado/XSim testbenches PASS, assertions enabled
in XSim PASS, property elaboration PASS, and all three OOC tops meet 150 MHz.
The cleaned run-configuration path uses 416 LUT/1,137 FF; removing reset from
the fully overwritten 512-bit fetch buffer saved 125 LUT without changing cycle
behavior or WNS.
See `reports/v3/M2_DMA_AND_RUN_CONFIGURATION_STATUS.md`.

M3 evidence (2026-08-25): generated 13-event trace, fault/abort scenarios and
embedded assertions PASS in Vivado/XSim; property elaboration PASS; all M3 OOC
tops meet 150 MHz. Write-time field certification plus explicit CFG-closure
finalization removes both the 684-bit legality guard and the per-cycle image
bounds comparator from execution while preserving II=1 and the exact
9-commit/4-stall trace. The integrated context-store/sequencer path has
post-synthesis WNS `+2.976 ns` and uses
567 LUT/380 FF/9 RAMB36/1 RAMB18/0 DSP. See
`reports/v3/M3_CONTEXT_CONTROL_STATUS.md`.

M3.5 added physical-resource/DFG/MMG collateral. M3.6 closes typed SSA, local RF
lifetime, concrete bank allocation and context emission. After M9a capability
closure, 20 contexts for all four kernels are packed into ten physical `.mem`
planes without allocating `proxy[N]`; correlation streams normalized candidates
to `TOPK_PUSH`. M3.5/M3.6 remain compiler gates. See
`reports/v3/M36_TYPED_CONTEXT_STATUS.md`.

M4 adds `vector_scratchpad`, `vector_stream_engine`,
`scratchpad_word_codec` and `stream_context_router`. Vivado/XSim directed
and 2000-cycle randomized backpressure tests, assertion execution, property
elaboration and ZCU106 OOC synthesis PASS. The integrated transport uses 16
RAMB36, 0 DSP and has post-synthesis WNS `+3.200 ns` at 150 MHz. RTL minor 22
reuses the stable BRAM output as the held-response payload, reducing the
integrated boundary to 703 LUT / 172 FF without adding a cycle. See
`reports/v3/M4_STREAM_TRANSPORT_STATUS.md`. DMA-to-scratchpad integration is
closed at M4.1 by `scratchpad_preload_engine` and
`scratchpad_residency_tracker`; see
`reports/v3/M41_DMA_SCRATCHPAD_STATUS.md`. Result drain remains M12.

M5 adds two `cluster_reduction_unit` instances, `global_reduction_merge`, a
two-entry A62 `scalar_register_file`, exact 15-cycle `scalar_function_unit`,
16-lane `shared_vector_arithmetic_unit` and `array_resource_router`. Golden
XSim covers exact latency/II, multi-beat accumulation, reserved-operation fault,
commit gating and deterministic/random backpressure. All OOC tops meet 150 MHz;
the M5 harness uses 22,420 LUT, 8,496 FF, 16 DSP, 0 BRAM and has post-synthesis
WNS `+2.009 ns`. See `reports/v3/M5_ARITHMETIC_RESOURCES_STATUS.md`.

M6 adds `pe_alu`, `pe_local_register_file`, `registered_switchbox`, `pe_tile`,
`cgra_row`, `cgra_cluster` and `cgra_cluster_pair`. The two 4x4 clusters consume
one shared spatial context, have no local PC/FSM and use registered
nearest-neighbor links. Vivado/XSim bit-exact and assertion-enabled tests plus
property elaboration PASS. OOC at 150 MHz reports `pe_tile` 1,465 LUT/194 FF,
WNS `+2.122 ns`; the pair uses 48,487 LUT/6,208 FF, 0 DSP/0 BRAM and WNS
`+2.126 ns`. See `reports/v3/M6_CGRA_ARRAY_STATUS.md`.

M7 adds `phi_request_queue`, folded Threefry2x32-20, symbol builder, response
gearbox, `phi_symbol_generator`, support/candidate sign cache, four-mode stream
provider and A62-to-S27 runtime normalizer. XSim/assertion/property gates PASS.
All five OOC scopes meet 150 MHz; the cache maps to one RAMB36, generator and
provider use zero DSP, and the II=1 normalizer uses four DSP. See
`reports/v3/M7_GENERATED_PHI_STATUS.md`.

The first real cross-milestone connection is implemented separately as
`verification/v3/integration/m1_m4_integration_harness.sv`. It connects M1 CSR
START through M2 run-configuration DMA, M3 phase/array execution and M4
preload/residency/vector readback while keeping future PE/Phi/resource ports
explicit. It is intentionally not named or used as the production top. Vivado
XSim and assertion-enabled XSim pass; ZCU106 OOC synthesis reports 3,729 LUT,
1,912 FF, 29 RAMB36, 2 RAMB18, 0 DSP and WNS `+0.851 ns` at 150 MHz. See
`reports/v3/M1_M4_INTEGRATION_HARNESS_STATUS.md`.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/sim/run_axilite_control.ps1
powershell -ExecutionPolicy Bypass -File scripts/formal/check_axilite_control_properties.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m2.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/formal/check_m2_properties.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m2.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m3.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/formal/check_m3_properties.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m3.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m4.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/formal/check_m4_properties.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m4.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m1_m4_integration.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m1_m4_integration.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m5.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/formal/check_m5_properties.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m5.ps1
powershell -ExecutionPolicy Bypass -File scripts/sim/run_m6.ps1 -EnableProperties
powershell -ExecutionPolicy Bypass -File scripts/formal/check_m6_properties.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m6.ps1
```
