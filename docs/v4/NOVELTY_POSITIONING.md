# v4 novelty positioning: support-dependent mapping and memory

**Update 2026-09-09:** [PPA_OPTIMIZATION.md](architecture/PPA_OPTIMIZATION.md)
extends the proposal to shared full-N operator/vector/reduction kernels across
all eleven algorithms, with recent Plaid/STRELA/Lake references and explicit
cycle/timing/resource tradeoffs. The support-LS-centered study below is retained
as prior analysis; its historical two-orientation layout is not the current
one-copy B proposal. Neither document establishes publication novelty or PPA.

Status: **candidate architecture hypothesis, 2026-09-08**. This is a bounded
primary-source sanity check, not an exhaustive prior-art search or a claim of
publication novelty. No v4 RTL/PPA benefit is established here.

## 1. Decision before implementation

The generic ideas are already established: programmable CS recovery, shared
arithmetic kernels, switching between independent MACs and parallel reductions,
CGRA resource partitioning, bank-aware scheduling, and decoupled address engines.
The defensible v4 hypothesis is narrower:

> Exploit the changing support size and repeated restricted least-squares
> accesses of several CS algorithms to choose output-versus-reduction
> parallelism on two fixed 4x4 arrays, using a compatible bank layout and a
> support-packing policy that accounts for its own traffic and reuse lifetime.

This remains a hypothesis until the **combination** beats strong static and
orientation-driven baselines at equal numerical quality, including transpose
storage, gather, packing, reduction, routing and reconfiguration costs.
The number eight is coverage evidence, not an architectural invention.

The local CSR manuscript already describes common kernels, a PE array, banked
scratchpad, generated sensing matrix and programmable sequencing. Its filename is
`CSR__A_Reconfigurable_Architecture_for_Multi_Algorithm_Compressive_Sensing_Recovery__Copy_ (6).pdf`,
while its current title is *A Unified Architecture for Multiple Compressive
Sensing Recovery Algorithms*. It is a project draft; its results are not new v4
measurements or independently revalidated evidence. v4 needs a concrete mechanism
and evaluation beyond implementing the draft more cleanly.

## 2. Closest sources and what they rule out

| Primary work | Relevant existing mechanism | Consequence for v4 |
| --- | --- | --- |
| Bai, Maechler, Muehlberghuber & Kaeslin, *High-Speed Compressed Sensing Reconstruction on FPGA Using OMP and AMP*, ICECS 2012, [DOI](https://doi.org/10.1109/ICECS.2012.6463559), [author PDF URL](https://linbaiwpi.github.io/docs/icecs_2012.pdf) | VMU operation modes distinguish parallel products plus an adder tree from independent serial MAC accumulations, addressing matrix/transpose access from the stored matrix. OMP and AMP implementations are described. | This is particularly close: do not claim that switching output and reduction parallelism, or accommodating A and A^T, is new. Compare against an orientation-driven dual-mode implementation. The paper describes implementations of two algorithms; do not equate that with proof of a single runtime-switchable shared accelerator. |
| Ren, Dorrance, Xu & Markovic, *A Single-Precision Compressive Sensing Signal Reconstruction Engine on FPGAs*, FPL 2013, [author publication record](https://rdorrance.com/wp-bibtex-custom/ren2013fpl/), [DOI](https://doi.org/10.1109/FPL.2013.6645574) | Configurable PEs share computation between different OMP tasks in a parallel FPGA reconstruction engine. | Shared PEs across correlation, LS and update are prior art. Fewer PEs or eight schedules alone are not the contribution. |
| Safarpour, Hautala & Silven, *An Embedded Programmable Processor for Compressive Sensing Applications*, NORCAS 2018, [Oulu primary PDF](https://oulurepo.oulu.fi/bitstream/handle/10024/25305/nbnfi-fe201901021154.pdf?sequence=1) | Programmable TTA optimized around common macro-operations, demonstrated with OMP, AMP and normalized IHT. It also includes a random-generator functional unit. | Runtime/software algorithm flexibility and common-kernel extraction cannot be presented as new. Distinguish a routed 32-PE spatial schedule and its measured execution cost from general programmability. |
| *FPGA Implementation of Real-Time Compressive Sensing with Partial Fourier Dictionary*, 2016, [publisher](https://onlinelibrary.wiley.com/doi/10.1155/2016/1671687) | OMP-oriented FPGA design uses FFT correlation and iterative conjugate-gradient LS machinery for a partial-Fourier application. | Replacing factorization with iterative CG-family computation is not sufficient novelty. Its dictionary and algorithm assumptions also differ; do not compare bare cycle counts without operator/quality alignment. |
| Kim, Lee, Shrivastava & Paek, *Operation and Data Mapping for CGRAs with Multi-Bank Memory*, LCTES 2010, [author university record](https://asu.elsevierpure.com/en/publications/operation-and-data-mapping-for-cgras-with-multi-bank-memory/), [primary paper URL](https://www.public.asu.edu/~ashriva6/cml/publications/papers/cgra3.pdf) | Joint placement of operations and data into PEs and banks avoids simultaneous bank conflicts. | Co-designing mapping and bank placement is established. Prove the particular pattern family v4 supports, its routing implementation, and its benefit on changing support workloads. |
| Yin et al., *Conflict-Free Loop Mapping for Coarse-Grained Reconfigurable Architecture with Multi-Bank Memory*, TPDS 2017, [publisher](https://ieeexplore.ieee.org/document/7879331/), [DOI](https://doi.org/10.1109/TPDS.2017.2682241) | Joint memory partitioning and modulo/operator scheduling produces conflict-free data placement and loop mapping. | A modular bank formula and a conflict checker are foundations, not sufficient novelty by themselves. |
| Wijerathne et al., *CASCADE: High Throughput Data Streaming via Decoupled Access/Execute CGRA*, TECS 2019, [author university record](https://staff.fnwi.uva.nl/a.pathania/publication/tecs-19/) | Programmable address hardware is decoupled from compute; the compiler synchronizes movement from multibank memory to the array. | Moving address generation to a side unit and claiming improved PE utilization is prior art. v4 must expose the exact gather/pack behavior and evaluate the cost of that unit. |
| Tan et al., *DRIPS: Dynamic Rebalancing of Pipelined Streaming Applications on CGRAs*, HPCA 2022, [PNNL primary record](https://www.pnnl.gov/publications/drips-dynamic-rebalancing-pipelined-streaming-applications-cgras), [DOI](https://doi.org/10.1109/HPCA53966.2022.00030) | Reallocates CGRA resources for input-dependent streaming kernels, with compiler support and explicit hardware overhead. | Adapting array resources to runtime work is established. v4's distinction must be the support-dependent reduction/group layout, not the word adaptive. |
| Park et al., *Modulo Graph Embedding: Mapping Applications onto Coarse-Grained Reconfigurable Architectures*, CASES 2006, [author PDF](https://cccp.eecs.umich.edu/papers/parkhc-cases06.pdf) | Joint mapping/routing and dynamic clustering during compilation. | Scheduling useful arithmetic on the physical mesh is necessary CGRA engineering. The compiler's dynamic clustering is not the same as runtime support adaptation, so retain that distinction. |

Evidence access note: the Oulu full PDF was readable; several other sources were
available through publisher/author metadata or indexed primary-PDF passages.
The Bai author URL currently returned HTTP 404 in a direct retrieval, although
the indexed primary excerpt exposed its VMU modes. Reacquire a stable publisher
or author copy before a submission-level figure/table comparison. Unread full
texts must not be marked as lacking a feature merely because their abstracts
omit it. This document deliberately avoids transferring their published speedup
numbers to v4.

## 3. Concrete candidate contract

Let `O` be output count and `D` reduction length for a dense or packed GEMV.
Use `D`, not `K`, in address equations: sparsity K and the reduction dimension
are different for forward and transpose products.

```text
R1: 32 independent output accumulators, one on each PE.
    All 32 lanes use the same reduction coordinate per MAC step.

R4: 8 outputs, each distributed across one physical row of 4 PEs.
    Each row accumulates four interleaved reduction subsequences,
    then reduces its four partial sums through horizontal mesh routes.
    Two 4x4 arrays provide eight such rows.

bank(o,r) = (o + 8*r) mod 32
addr(o,r) = matrix_base + floor(o/32)*D + r
```

The array keeps its physical topology. R1/R4 are scheduled operating modes,
not additional PEs, arbitrary repartitioning hardware, or independent algorithm
engines. Two orientation-specific copies may store `A` and `A^T`; their base
regions, shape metadata, storage overhead, preload/copy traffic and coherency
must be explicit. Packing A_S adds working storage rather than creating a free
view of arbitrary columns.

### What this bank formula establishes

- For 32 consecutive `o` and fixed `r`, all 32 banks are distinct: R1 reads are
  conflict-free under one read per bank per cycle.
- For 8 consecutive `o` and 4 consecutive `r`, the low three bits distinguish
  the eight outputs and the next two bank bits distinguish reduction lanes:
  R4 reads are conflict-free. Masked tails retain this property.
- Within one allocated matrix region, `(bank,addr)` identifies `(o,r)` uniquely:
  `addr` determines `r` and the output block; `bank-8*r mod 32` recovers the
  output index within that block.
- These are **bank-access** properties. They do not establish feasible
  memory-to-PE routing, broadcast fanout, RF port availability, reduction latency,
  packed-write throughput, or BRAM timing.

A small independent arithmetic check in this research turn verified 4,096 R1
groups and 4,096 R4 groups with varying bases/reduction offsets, plus injectivity
for output extent 99 and D in `{1,3,4,7,32,63}`. This supports the equations; it is
not an RTL test or a performance measurement. A persistent address/route checker
belongs in the architecture model.

### Packing is a required mechanism, not an omitted prelude

Arbitrary support indices are not eight consecutive packed output indices.
The R4 proof therefore does not apply to directly reading any eight selected
columns of `A^T`. A support gather must either schedule conflicts or create a
packed `A_S`/`A_S^T` working set with contiguous local support IDs.

There is a concrete transpose-write trap. Reading 32 rows of one selected A
column with R1 is conflict-free. Writing these values immediately into packed
`A_S^T` fixes `o=support_local_id` and varies `r=row` over 32 consecutive values:

```text
bank(support_local_id,row) = (support_local_id + 8*row) mod 32
```

Only **four banks** are used, with **eight writes per bank**. A one-write-port
bank cannot accept that burst in one cycle. An arithmetic check confirmed this
count. A valid implementation needs a staging/transpose schedule, buffered
scatter with measured service rate, or a different layout. Count source reads,
destination writes and transpose routing separately. The naive estimate
`pack_cycles=M*|S|/32` is not justified for building both orientations.

The packed-set descriptor needs support order, matrix version, dimensions and a
validity epoch. Invalidate or update on selection, union, prune, rollback, new
matrix, scaling/precision changes, and algorithm changes. Reuse is safest within
one LS solve where S is fixed. Reuse across outer iterations needs measured
support overlap and an explicitly correct incremental-packing policy.

## 4. Why adaptation might help, and when it cannot

Ignoring fill, routes, stores and dependencies only for a first-order comparison:

```text
T1(O,D) ~= ceil(O/32) * D
T4(O,D) ~= ceil(O/8)  * (ceil(D/4) + row_reduction_cost)
```

These are lower-bound-style compute estimates, not the final cycle model. Use
the real MAC initiation interval, accumulator recurrence latency, pipeline fill,
vector broadcasts, RF reads/writes, route hops, output stores and bank service
in the executable model.

For large, well-aligned O, both modes have approximately the same OD/32 MAC
throughput, so R4's final reduction can make it worse. For O<=8 and a long D,
R4 can reduce ideal compute time towards D/4 instead of D. For restricted
transpose in CGLS, `O=|S|` and `D=M`, which makes early/small supports an obvious
candidate. With O=1, R4 still uses only one four-PE row; it does not yield full
32-PE useful utilization. Larger reduction groups may improve that corner but
require more routing and a new banking proof.

The pack-and-adapt decision is profitable only if:

```text
T_pack + T_copy_extra + T_context + sum(T_adaptive_calls)
    < sum(T_unpacked_baseline_calls)
```

For a fixed support reused for q LS steps, a simplified crossover is
`q*(T_unpacked_step - T_packed_step) > T_pack + T_context + T_copy_extra`.
The actual q depends on convergence and precision. Do not use knowledge of the
future test trace to choose q in the deployable policy. Use a declared static
bound or a policy trained on validation, and compare it to an offline oracle
only as a bound. Every extra scalar/certificate pass counts in both sides.

Support changes are algorithm-specific: OMP/gOMP grow support; HTP may replace
it; CoSaMP/SP form temporary unions and prune; GP can reselect. These different
lifetimes are the workload-specific opportunity. IHT/MP are useful controls:
they may gain little from LS packing, and their non-benefit must stay visible.

## 5. Minimal ablations needed to support a paper claim

| Configuration | Purpose |
| --- | --- |
| Always R1, same storage/precision | Tests whether the reduction mode helps small output counts. |
| Always R4, same storage/precision | Required requested baseline; exposes unnecessary reduction overhead for large outputs. |
| Orientation-driven dual mode | Closest conceptual baseline to Bai et al.: choose mode from matrix orientation, without support-size/lifetime awareness. |
| Shape-adaptive R1/R4, no packing | Isolates mode selection; include arbitrary-index bank conflicts. |
| Packing plus always R1 / always R4 | Isolates locality/packing benefit from adaptation. |
| Full shape-and-reuse-aware policy | Candidate: packing decision, reuse, shared swizzle, mapped R1/R4. |
| Single stored orientation / two copies | Quantifies extra BRAM and preload/copy traffic rather than assuming transpose storage is free. |
| Ordinary layout / shared swizzle | Demonstrates that the bank layout contributes after routing and transfer costs. |
| Optional R2/R8 or offline best-mode bound | Tests whether R4 is a sensible topology/complexity compromise; avoid presenting a two-candidate optimum as global. |

Use one fixed 32-PE budget and equal fixed-point quality/certificates. Report
macro-phase and whole-run costs, bytes, working-set footprint, bank conflicts,
route occupancy, useful PE operations, idle/masked cycles and context load
cycles. Include packing cost at its actual reuse frequency, plus cold-matrix
and warm-matrix scenarios. Batch amortization must state the batch size.

Required coverage is the real supported N/M/K grid, support sizes from 1 through
the algorithm's full union capacity, adversarial support residue patterns,
nonmultiples of 4/8/32, short and long reductions, zero/tiny residuals, different
LS iteration counts, and matrix changes. Use the dataset/quality rules from
[BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md). A microbenchmark of a packed
transpose does not establish end-to-end reconstruction acceleration.

After the architecture model and correctness gates, implement equivalent
baselines on the same FPGA/tool target. A design that loses clock frequency or
uses enough extra BRAM/routing can lose real runtime/energy despite fewer model
cycles. Iso-PE and iso-resource comparisons answer different questions; provide
both where extra copies/packing hardware materially change area.

## 6. Candidate claims and explicit go/no-go decisions

| Candidate statement | Go evidence | No-go / narrower report |
| --- | --- | --- |
| One bank layout supports both R1/R4 schedules | Address injectivity, bank-port proof, exact beat-to-PE routes and executable traces including tails and stalls. | If a hidden all-to-all network, duplicated ports or unscheduled arbitration is necessary, redesign or disclose that hardware cost. |
| Support-aware adaptation improves reconstruction execution | Whole-run paired improvement over **both** static modes and the orientation-driven baseline, after pack/copy/context cost, at equal quality. | If only packed kernel cycles improve, report a kernel study; do not claim application acceleration. |
| Packing benefits repeated restricted LS | Measured break-even and support-reuse distribution; correct invalidation; packing service rate proved including transpose writes. | If small supports/short solves lose, the policy must bypass packing. If no realistic reuse amortizes it, remove it. |
| The mechanism generalizes across algorithms | Hold-out algorithm/workload results, explicit support-lifetime cases, and no per-test oracle tuning. | If only OMP benefits, narrow the contribution to OMP or its workload family. |
| Lower fixed-point cost preserves quality | Bit-accurate end-to-end sweep with the agreed degradation limits and fault handling. | This qualifies the hardware design; it is not by itself a new spatial architecture. |

Do not invent a minimum percent speedup after observing the results. Freeze
the performance objective and allowable resource/regression budget before the
full comparison. A tiny gain within model uncertainty is not enough to motivate
additional architecture complexity; state it and simplify.

## 7. What the post-quantization LS certificate contributes

A certificate checked after quantizing the committed coefficients is a
**numerical safety/correctness contract**. It can catch an update that passed an
internal-precision LS test but fails after storage rounding, and it prevents an
invalid reconstruction from being silently committed. It does not prove a small
coefficient forward error for ill-conditioned restricted matrices, exact support
recovery, RIP, or application-level SNR. Those need separate tests/bounds.

This certificate is valuable and should remain mandatory where specified, but
it is not the headline architectural novelty. It can become part of a broader
co-design result only if the paper shows how mapping/precision changes its cost,
convergence and commit behavior without weakening the solver contract. Do not
change acceptance tolerance between baselines merely to obtain a speedup.

## 8. Safe current wording

Before measurements: "We propose to evaluate support-dependent GEMV mapping
and packed-working-set reuse on a two-array, 32-PE CS architecture, and test
whether a common bank layout sustains both mappings at lower end-to-end cost."

After successful evidence, replace this with the measured, bounded result and
its exact baselines. Avoid "first", "optimal", "full utilization", "zero-cost
reconfiguration", or "supports arbitrary matrices" unless the corresponding
scope and proof are actually established. The next step is to finish the
route/packing/cycle contract; a clean block diagram alone does not settle the
novelty or feasibility question.
