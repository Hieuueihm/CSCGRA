# RTL v2 processing elements

This folder owns arithmetic cells, physical row/column composition, registered
wavefront transport, and streaming top-K.

| File | Responsibility |
|---|---|
| `pe_core.v` | Arithmetic operations, accumulator, multiplier output, saturation, and local RF. |
| `pe_tile.v` | Operand selection, timing-isolating input registers, and one PE wrapper. |
| `pe_cluster_4x4.v` | Four-row registered PE0 ingress pipelines and per-row token ownership. |
| `pearray.v` | Two 4x4 clusters combined into the 4x8 array and result aggregation. |
| `pe_column_connection.v` | Registered/structured connection between the two column clusters. |
| `pe_stream_topk_serial_service.v` | Exact top-K stream controller and narrow support-append handshake. |

Large operations must give all four rows a defined role. Controller-originated
stream tokens enter PE0 and lower rows consume registered south-link data and
tags. Do not reconnect lower-row arithmetic directly to controller payloads.
