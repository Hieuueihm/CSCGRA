# RTL v2: active optimized architecture

This directory is the synthesizable source of truth for the current design.
Use `files.f` for compile order. Current sign-off is checkpoint `88f9411`:
348 PASS / 0 FAIL, 1,313,368 full-sweep cycles, and +0.850 ns OOC WNS.

## Directory ownership

| Directory | Responsibility |
|---|---|
| `control/` | CSR/DMA/config/sequencer and the sparse algorithm/LS controller. |
| `datapath/` | LFSR Phi generation and generic reduction. |
| `interconnect/` | CGRA switchbox. |
| `memory/` | Scratchpad banks and global scalar register file. |
| `pe/` | PE core/tile/array, registered PE0 wavefronts, and streaming top-K. |
| `solver/` | LS matrix storage, support-set service, and sparse service integration. |
| `top/` | `cgra_top` and SoC wrapper. |

## Main retained features

- strict registered PE0 -> PE1 -> PE2 -> PE3 transaction flow;
- distinct work on all four PE rows for correlation, RHS, Gram, LDLT, residual,
  prune, and top-K;
- regularized LDLT with exact/prefix factor reuse;
- READ4/WRITE4, streamed LDLT border, phase overlap, and compact LUTRAM
  scoreboard;
- streamed residual/prune/correlation/update/top-K paths;
- one-entry ACC4 queue and overlapped Gram drain;
- timing-isolated support, mesh, RHS, and wide arithmetic boundaries;
- chained narrow top-K support append acknowledgements.

See `docs/PROJECT_STATUS.md` for the complete inventory and rejected trials.
