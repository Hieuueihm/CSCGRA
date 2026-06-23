# CSCGRA ZCU106 SoC Bare-Metal App

This folder is intentionally outside the Vivado run tree. It contains a small standalone C application for the current CSCGRA SoC hardware platform.

Validated hardware baseline:

- XSA: `D:/vivado_pj/CSCGRA/runs/bd_zcu106_soc_clean_50152b7_20260623_102206/artifacts/cscgra_zcu106_soc_opt.xsa`
- RTL commit: `50152b7 Hide unused SoC IRQ detail ports`
- AXI-Lite control base from BD address map: `0xA0000000`
- CGRA DDR master visible range: low DDR `0x00000000..0x7fffffff`

## Files

- `src/main.c`: thin wrapper kept for Vitis app entry compatibility.
- `src/main_8alg.c`: standalone bare-metal SoC runner with UART output through `xil_printf`.

## What The App Does

This app now follows the 8-algorithm regression flows under `D:/vivado_pj/analysis/m64n256k16` and runs these SoC-visible algorithms:

- OMP
- OMP direct-phi variant
- gOMP
- CoSaMP
- SP
- IHT
- HTP
- GP
- MP

For each algorithm the app:

1. Soft-resets the CGRA.
2. Reprograms the CSR case parameters (`M`, `N`, `K`, `seed`, `phi_scale`, `flags`).
3. DMA-clears SPM working vectors from a zeroed DDR buffer:
   - `vec0` / `x`
   - `vec1` / `r`
   - `vec3` / `score`
4. DMA-loads golden `y[64]` into `vec2` and seeds residual `vec1` from the same DDR source.
5. Runs the algorithm-specific context program(s) derived from the regression testbench.
6. DMA-stores SPM `vec0` back to DDR as `x[256]`.
7. Prints UART status and verifies the final `x[256]` against the matching golden fixed-point vector.

There are two execution styles in the current RTL/testbench set:

- Single full-program launch: OMP, OMP direct-phi, gOMP, MP.
- Per-iteration relaunch: CoSaMP, SP, IHT, HTP, GP.

The app prints each launch status, cycle counter, PC debug value, non-zero output samples, per-iteration launch markers where applicable, and a final `VERIFY <ALG> x_final PASS/FAIL` line over UART.

## Host-Side Golden Compare

The C app has an internal fixed-vector check, but there is also an independent host-side checker that compares captured UART dumps against `golden_model/golden_cases_array.vh`.

To generate a full `x[256]` dump over UART, build the app with:

```c
#define CGRA_DUMP_FULL_X 1
```

or pass it as a compiler define in Vitis:

```text
-DCGRA_DUMP_FULL_X=1
```

When enabled, each algorithm prints lines like:

```text
X_DUMP OMP alg_idx=0 idx=38 value=0xfee6ea
```

After capturing UART output to a text file, run:

```powershell
python D:\vivado_pj\cscgra_soc_app\tools\compare_uart_to_golden.py `
  --log D:\path\to\uart.log `
  --golden D:\vivado_pj\golden_model\golden_cases_array.vh
```

The checker requires all 256 entries for each dumped algorithm and reports missing indices, mismatches, and signed 24-bit differences. It uses the same default tolerance as the RTL/C checks: `512`.

## Use In Vitis

1. Create a platform from the XSA above.
2. Create a standalone application for the APU, normally `psu_cortexa53_0`.
3. Add `src/main.c` to the application sources. It includes `src/main_8alg.c` internally.
4. Build and run on hardware.
5. Open the ZCU106 UART terminal at the baud rate configured by the BSP, commonly `115200 8N1`.

By default the app runs every supported algorithm in sequence. To restrict the run list at compile time, override:

- `CGRA_RUN_ALG_MASK`

To emit a full host-comparable `x[256]` dump, override:

- `CGRA_DUMP_FULL_X`

Bit order is:

- bit 0: OMP
- bit 1: OMP direct-phi
- bit 2: gOMP
- bit 3: CoSaMP
- bit 4: SP
- bit 5: IHT
- bit 6: HTP
- bit 7: GP
- bit 8: MP

Example: only OMP + MP

```c
#define CGRA_RUN_ALG_MASK ((1U << 0) | (1U << 8))
```

The code uses only standard Xilinx standalone BSP headers:

- `xil_io.h`
- `xil_cache.h`
- `xil_printf.h`
- `platform.h`

## Notes

- The app passes 32-bit low-DDR addresses to the CGRA because the RTL `m_axi_gmem` address width is 32-bit.
- Buffers are aligned to 64 bytes and cache ranges are flushed/invalidated around CGRA DMA accesses.
- If your linker places buffers above `0x7fffffff`, move the application/data section to low DDR in the linker script.
- The app intentionally clears SPM state by DMA before every algorithm run because the current SPM RAMs do not have a global clear-on-reset path.
- `src/main.c` now includes `src/main_8alg.c` so an existing Vitis app that only references `main.c` still builds the new multi-algorithm runner. If `main_8alg.c` is accidentally compiled as a separate translation unit by a source-folder auto-add flow, it emits only a harmless dummy symbol and avoids a duplicate `main`.
- Keep `CGRA_DUMP_FULL_X=0` for normal UART runs. Enable it only when you want the host-side golden compare, because dumping 256 lines per algorithm is intentionally verbose.
