CSCGRA_opt SDK 2018 bare-metal golden OMP app

Use with the Vivado 2018.1 exported HDF/bitstream generated from the matching
CSCGRA_opt BD. The older full synth/impl artifact is currently at:
  D:\vivado_pj\CSCGRA_opt\runs\bd_zcu106_soc_opt_current\artifacts\cscgra_zcu106_soc_opt.hdf

If you use the newer BD-only project with UART0/1 enabled, synth/impl/export HDF
again before creating the SDK hardware platform.

SDK steps:
1. File -> New -> Application Project.
2. Create/select hardware platform from the HDF above.
3. Select standalone BSP for psu_cortexa53_0.
4. Create an Empty Application. For polling, copy src/main.c and src/omp_golden.h
   into the app src folder. For interrupt mode, copy src/main_irq.c and
   src/omp_golden.h, then either rename main_irq.c to main.c in SDK or exclude
   the polling main.c from build.
5. Program FPGA with cscgra_zcu106_soc_opt.bit.
6. Run the app on psu_cortexa53_0 and watch the UART/SDK console.

Notes:
- This app first verifies DMA DDR->SPM(R)->DDR loopback, then runs the OMP
  context program with the M=64, N=256, K=16 golden vector from omp_golden.h.
- The app compares all 256 output x entries against omp_gold_x_final with a
  24-bit signed tolerance of OMP_GOLD_TOL and prints OMP GOLDEN PASS on success.
- If xparameters.h uses a different CGRA base macro, add it near the top of
  main.c or replace CGRA_BASE manually.


Interrupt app:
- src/main_irq.c uses the CGRA interrupt connected to PS pl_ps_irq0 through the GIC.
- It waits for the ISR flag instead of polling STATUS_DONE continuously.
- If xparameters.h does not expose a CGRA interrupt macro, it falls back to interrupt ID 121 for PL-PS IRQ0.

Multi-algorithm IRQ app:
- src/main_multi_irq.c runs 8 algorithm profiles with IRQ completion.
- src/multi_golden.h contains 8 algorithms x 3 iteration-count cases: 4, 8, and 16.
- Copy src/main_multi_irq.c and src/multi_golden.h into the SDK app. Keep only one file with main() in the build.
- Each run prints algorithm name, case index, iteration count, rc, IRQ status, CGRA cycles, PS timer time_us, program length, nonzero count, mismatch count, and PASS/FAIL.
- OMP and MP follow the RTL-verified testbench schedules. The other profiles map directly to the sparse-loop RTL operations and should be treated as board validation candidates until their PASS logs are collected.

Multi-algorithm polling app:
- src/main_multi.c runs the same 8 algorithm profiles x 3 cases as src/main_multi_irq.c, but waits by polling REG_STATUS.
- Copy src/main_multi.c and src/multi_golden.h into the SDK app. Keep only one file with main() in the build.


Refactored multi-file app:
- Common library: src/cscgra_test.h, src/cscgra_test.c.
- IRQ support library: src/cscgra_irq.c.
- Algorithm schedules: src/alg_omp.c, src/alg_cosamp.c, src/alg_iht.c, src/alg_htp.c, src/alg_sp.c, src/alg_alg5.c, src/alg_alg6.c, src/alg_mp.c, src/alg_table.c.
- Polling runner: src/main_multi_refactored.c.
- IRQ runner: src/main_multi_irq_refactored.c.
- Golden data: src/multi_golden.h.
- In SDK, include exactly one runner file with main(): either main_multi_refactored.c or main_multi_irq_refactored.c.
- Exclude old monolithic files from build when using the refactored app: main.c, main_irq.c, main_multi.c, main_multi_irq.c.


Single-file multi-algorithm app (recommended now):
- Use only src/cscgra_multi_test.c and src/cscgra_multi_golden.h for the compact polling test.
- Exclude every other C file from the SDK build to avoid multiple main() definitions.
- Algorithm order is fixed as: OMP, GOMP, CoSaMP, SP, IHT, HTP, GP, MP.
- GOMP is Generalized OMP / multi-index OMP-style selection.
- GP is Gradient Pursuit.
