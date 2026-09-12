# V4 CSR IP packaging

The packaged `csr_top` exposes both `S_AXI` AXI4-Lite control and `M_AXI` AXI4
payload DMA (128-bit data, 64-bit address, maximum eight-beat bursts). Both
interfaces share the wrapper clock/reset; packaging does not imply synthesis or
implementation sign-off.

`scripts/v4/package_csr_ip.tcl` packages `csr_top` as a reusable Vivado IP
component for Vivado 2018.1. The script is deliberately limited to project
creation, source import, compile-order maintenance, IP-XACT metadata, and
integrity checking. It does not run synthesis or implementation.

## Component

- VLNV: `user.org:ip:csr_top:1.0`
- Top module: `csr_top`
- Default output: a new `work/v4_ip_YYYYMMDD_HHMMSS/` directory
- Optional device selection: `-part xczu7ev-ffvc1156-2-e`
- Existing output directories are rejected; the script never overwrites a package.

The package imports every SystemVerilog source in `rtl/v4/files.f`, explicitly
appends `rtl/v4/host/host_command_bridge.sv` and `rtl/v4/top/csr_top.sv`, and resolves
the transitive quoted-header closure. Included headers are added to the project
and `-import_files` copies the source/header closure into the package root.
Missing file-list entries, appended sources, include directories, or headers
fail before a project or output directory is created.

## External interface

`csr_top` exposes only the following top-level interfaces:

| Interface | Ports | Widths |
|---|---|---|
| `S_AXI` | `s_axi_awaddr`, `s_axi_awprot`, `s_axi_awvalid`, `s_axi_awready`, `s_axi_wdata`, `s_axi_wstrb`, `s_axi_wvalid`, `s_axi_wready`, `s_axi_bresp`, `s_axi_bvalid`, `s_axi_bready`, `s_axi_araddr`, `s_axi_arprot`, `s_axi_arvalid`, `s_axi_arready`, `s_axi_rdata`, `s_axi_rresp`, `s_axi_rvalid`, `s_axi_rready` | address 12, data 32, protection 3, strobes 4, responses 2, handshake signals 1 |
| `S_AXI_ACLK` | `s_axi_aclk` | 1 |
| `M_AXI` | `m_axi_*` AW/W/B/AR/R channels, INCR and fixed non-cacheable sidebands | address 64, data 128, strobes 16, LEN 8, no IDs, max eight beats and one outstanding burst |
| `S_AXI_ARESETN` | `s_axi_aresetn` | 1, `ACTIVE_LOW` |
| `INTERRUPT` | `irq` | 1, `LEVEL_HIGH` |

The AXI slave memory map is named `S_AXI` and contains address block `Reg` at
base `0x00000000`, range `0x00001000` (4 KiB), width 32, and IP-XACT access
`read-write`. Register offsets and software semantics remain the responsibility
of the RTL contract.

`S_AXI` and `M_AXI` are associated with `S_AXI_ACLK` and `s_axi_aresetn`.
The DMA master has a 64-bit address space; the platform must map only valid
memory regions and connect an appropriate interconnect/controller. The standalone
level-high `irq` combines independently acknowledged legacy and DMA sources.
This is not a dedicated PS HP port or a coherent memory interface.

## Invocation

Run only after the parent wrapper and all sources referenced by `rtl/v4/files.f`
are present:

```text
C:\Xilinx\Vivado\2018.1\bin\vivado.bat -mode batch -source scripts/v4/package_csr_ip.tcl -tclargs -out_dir work/v4_ip_20260910_191500
```

The output name must match `work/v4_ip_*`; choose a unique suffix. The script
also accepts an optional `-part PART`. It checks the exact AXI port names and
widths before `create_project`, then asserts the packaged IP-XACT ports,
interfaces, associations, 4 KiB map, imported file names, and
`ipx::check_integrity` result.

The 2018.1 flow is intended to package the SystemVerilog top directly. If a
future top uses syntax that this installed Vivado release cannot parse, stop at
the reported source/elaboration error and coordinate a boundary shim with the
parent; this script does not alter RTL, `rtl/v4/files.f`, or the catalog.

## Validation status

Vivado 2018.1 packaging and IP-XACT integrity passed on September 11, 2026 in
`work/v4_ip_20260911_092201/`: 58 sources, 18 headers, exact five interfaces
including M_AXI. The initial sandbox run failed creating Vivado profile state;
the approved retry completed. The log retains SystemVerilog/parser and
unreferenced historical-source warnings; this is not a warning-free build.
See `reports/v4/payload_dma_20260911/README.md` for source-bound evidence.
Synthesis, implementation, timing, resources, block-design/board qualification
and bitstream generation were not run.
