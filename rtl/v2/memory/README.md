# RTL v2 memory

- `spm_cluster.v`: banked scratchpad used by DMA, PE execution, and LS access.
- `global_scalar_rf.v`: shared scalar register file.

Generated initialization, Vivado IP, and implementation products do not belong
here. LS factor storage is separately owned by `solver/ls_matrix_service.v`.
