# RTL v2 control

This folder owns command sequencing and the main sparse/LS schedule.

| File | Responsibility |
|---|---|
| `sparse_loop_controller.v` | Correlation, residual, update, Gram/RHS, LDLT, solve, factor reuse, and LS command scheduling. |
| `sparse_loop_lfsr_jump.vh` | Generated LFSR jump data included by the sparse controller. |
| `sequencer.v` | Context fetch/decode/issue/retire sequencing with synchronous context-memory latency. |
| `configmem.v` | BRAM-backed context storage. |
| `csr_regs.v` | AXI-Lite control/status registers. |
| `dma_ctrl.v` | AXI DMA movement between external memory and SPM. |
| `ctx_decoder.v` | Context-word field decode. |
| `addrgen.v` | Address generation for CGRA execution. |

Most cycle optimization work is in `sparse_loop_controller.v`: factor reuse,
four-row Gram/RHS, residual chaining, Phi scan scheduling, LDLT border
streaming/phase overlap, safe LS handshake chaining, and timing isolation.
Rejected controller trials are not left behind as disabled production logic;
their evidence lives in `reports/releases`.
