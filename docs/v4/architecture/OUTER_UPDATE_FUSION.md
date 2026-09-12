# Limited outer-update fusion

The compiler has one opt-in fusion candidate: HTP's outer update
`X + round22(alpha*G)`, where alpha is held in scalar register R18.
`--outer-fusion` lowers it to the existing rounded-affine
kernel, whose multiply is rounded once at the established S27 boundary before
the ADD. The separate SCALE and ADD program is the default and remains the
compatibility baseline.

Only the HTP outer update is selected. QR factor construction, solve, stored-X
certificate and support publication remain separate commands. Other QR
algorithms retain their image even when the flag is set. The compiler raises the
required kernel revision to at least 8 and adds `ROUNDED_AFFINE`; target revision
validation is fail-closed.

Acceptance requires paired XSim runs at M32/N64/K8 and M64/N256/K8 with actual
eight outer iterations. The pair must use identical raw inputs, policy, source
closure and QR physical work. Raw X/residual/support/status, numerical events,
replay artifacts and service profiles are compared. A candidate is accepted only
when HTP has a positive net START-to-DONE reduction and every other active
algorithm is unchanged.

Current measured result is archived in
`reports/v4/outer_fusion_20260911/`. It is a cycle result, not a timing or PPA
result. RTL remains unchanged; no DMA, reconfigurable interconnect or mesh is
part of this step.
