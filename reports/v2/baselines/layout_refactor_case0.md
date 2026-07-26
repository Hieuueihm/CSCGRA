# RTL v2 layout-refactor smoke baseline

Configuration: M=64, N=256, K=16, XSim 2018.1.

| Algorithm | Result | Cycles | Nonzero |
| --- | --- | ---: | ---: |
| OMP | PASS | 110785 | 16 |
| CoSaMP | SKIP: requires 2K candidate support | - | - |
| IHT | PASS | 105466 | 16 |
| HTP | PASS | 173848 | 16 |
| SP | SKIP: requires 2K candidate support | - | - |
| GP | PASS | 106282 | 16 |
| GOMP | PASS | 60894 | 16 |
| MP | PASS | 60145 | 15 |

Testbench summary: 33 PASS, 0 FAIL.

The cycles and behavior match the pre-layout-refactor factor-reuse baseline.
Raw log SHA256:
`3A05D6B9EF7ECB214C6F4428680DB0500EB573ADE072655E3ECEA7FFC8C9F047`.
