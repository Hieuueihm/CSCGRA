# RTL v2 solver services

| File | Responsibility |
|---|---|
| `ls_matrix_service.v` | Eight-bank LDLT matrix/RHS storage, READ2/READ4/WRITE4, and queued ACC4 drain. |
| `support_set_service.vh` | Support paths, append/copy/merge operations, and support masks. Included by the sparse service. |
| `sparse_kernel_service_engine.v` | Integrates sparse controller, support service, top-K service, and completion handling. |

The active least-squares algorithm is regularized LDLT, not QR. The LS service
allows one active request; retained chaining either uses registered completion
or the existing ACC4 queue without widening inferred memory write ports.
