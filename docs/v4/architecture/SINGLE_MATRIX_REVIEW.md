# Single-copy diagonal matrix layout: independent review

Review date: 2026-09-08. This document reviews a mathematical storage and
schedule candidate for two 4x4 PE arrays, with 32 PEs in total and four PEs in
each local reduction row. It is not an RTL implementation, a measured
performance result, or a novelty claim. The formulas below are the reviewed
candidate; they do not establish that every proposed implementation uses them
correctly.

## 1. Storage bijection and inverse

Let the original matrix be `A[r,c]`, with `0 <= r < M`, `0 <= c < N`, and
`Q = ceil(N/32)`. Store one coefficient copy in 32 single-read banks:

```text
bank(r,c)    = (r+c) mod 32
address(r,c) = r*Q + floor(c/32)
bank_depth   = M*Q
```

The physical padded domain is `0 <= r < M`, `0 <= c < 32*Q`. Padding is in
columns; no row padding is needed by this address formula. Padding cells must
be initialized or excluded by valid masks, according to the image contract.

For any physical bank `b` and address `a` in range, the inverse is:

```text
r = floor(a/Q)
q = a mod Q
c = 32*q + ((b-r) mod 32)
```

The address determines `r` and `q` uniquely. The bank then determines `c mod
32` uniquely. Conversely, substituting this inverse into the storage formulas
returns exactly `(b,a)`. Thus the layout is a bijection over the padded domain
and an injection over the valid `M*N` coefficients. An inverse result with
`c >= N` identifies padding.

Both operations read this same copy:

```text
Ax:   output o, reduction k -> (r,c) = (o,k)
A^Tr: output o, reduction k -> (r,c) = (k,o)
```

In both orientations the bank is `(o+k) mod 32`; only the address expression
changes. A second coefficient copy or a stored transpose address table is not
required by these formulas. Address generators, stride registers, routing and
valid masks are required hardware.

## 2. R1: 32 outputs and one reduction value

For a tile base `B` that is a multiple of 32, PE `i`, `0 <= i < 32`, owns
output `o=B+i`. At reduction index `k`:

```text
PE       = i
bank     = (B+i+k) mod 32
Ax addr  = (B+i)*Q + floor(k/32)
AT addr  = k*Q + floor((B+i)/32)
vector   = v[k], broadcast to active PEs
```

Adding a constant modulo 32 permutes all 32 banks. A partial output tile is a
subset of this permutation, so it also has no read conflict. R1 requires one
vector read and at most one coefficient read per bank per issue.

For a complete tile, forward Ax needs 32 row-dependent coefficient addresses;
transpose needs one common address. This is a change from the old layout's
common R1 address. It must be represented in the dispatcher and bank wiring.

## 3. R4: eight outputs and four reduction lanes

Let `B` be a multiple of eight, `i=0..7` the local output row and `l=0..3` the
PE column within that row. Use:

```text
o          = B+i
PE         = 4*i+l
issue      = 8*t+u, where u=0..7
k          = 32*t+8*l+u
bank       = (B+i+8*l+u) mod 32
Ax address = (B+i)*Q+t
AT address = (32*t+8*l+u)*Q + floor((B+i)/32)
vector     = v[32*t+8*l+u], broadcast down PE column l
```

The 32 values `i+8*l` are exactly `0..31`, each occurring once. Adding `B+u`
modulo 32 therefore gives one read per bank, in either orientation. Removing
invalid output or reduction lanes cannot introduce a collision. Each full
32-element reduction block is partitioned into four disjoint chunks of eight;
each PE accumulates its own chunk, and the existing local row reduction tree
can merge the four partial sums. No inter-array neighbor link is required.

Forward Ax needs eight distinct addresses per full issue, each used for the
four lanes of one output. Transpose needs four distinct addresses, each shared
by the eight outputs. The transpose output tile is contained within one
32-column block because `B` is a multiple of eight.

With the existing vector layout `bank=k mod 32`, `address=floor(k/32)`, the
four vector reads use banks `8*l+u`, all distinct, at vector address `t`.
This is a different vector order from the old four-consecutive-value feed.
The coefficient and vector tags must use the same `k`; lane ownership is
`floor((k mod 32)/8)`, rather than `k mod 4`.

For `K` divisible by 32, R4 still issues exactly `K/4` MAC cycles per output
tile and performs exactly `O*K` useful MACs over the complete operation.
Under the existing timing assumptions, its cycle formula remains
`ceil(O/8)*(K/4+7)`. This arithmetic equality is not evidence that the changed
feeder meets the same clock period or read latency in RTL.

### Reduction tails

The straightforward reviewed loop uses `8*ceil(K/32)` issue positions per
output tile and masks `k >= K`. It is not generally `ceil(K/4)`. For example,
`K=8` uses eight positions with only one active reduction lane per output;
the old layout used two positions with four active lanes.

Entirely empty positions can be removed without changing lane ownership. The
resulting issue count is `8*floor(K/32)+min(K mod 32,8)`. This optimization still
does not generally reach `ceil(K/4)` and must not be assumed unless modeled.
Output tails are independently masked. Mode selection must charge the actual
schedule, including reduction and store overheads.

Other schedules are possible. For example, choosing outputs
`o=32*g+4*i+v`, for `i=0..7` and `v=0..3`, permits contiguous reductions
`k=4*t+l`, since `bank=(v+4*i+4*t+l) mod 32` is also a permutation. That
alternative retains the old reduction order but fragments small output tails.
It has not replaced the contiguous-output R4 candidate reviewed here.

## 4. Bank routing and physical cost

For R1, bank `b` belongs to PE `i=(b-B-k) mod 32`. For R4, define:

```text
z  = (b-B-u) mod 32
i  = z mod 8
l  = floor(z/8)
PE = 4*i+l
```

A cyclic rotation and a fixed transpose of lane numbering are sufficient;
an arbitrary 32-by-32 crossbar is not mathematically necessary. However, the
old layout only rotated four groups of eight banks. The new layout requires
arbitrary rotation by one through 31 words as well. The old group-only
rotation network cannot implement it unchanged.

A simple 32-word barrel rotator has five stages of 32 word-wide 2:1 muxes,
compared with two stages for a four-group rotation. At coefficient width 18,
those illustrative structures contain 2,880 and 1,152 bit-wide 2:1 muxes,
respectively. These are structural estimates, not LUT counts, area predictions
or timing results. Bank address distribution, control, registers and placement
also have cost. Additional pipelining would change the schedule's latency
contract and must be accounted for.

At `M=128,N=1024,C=18`, the single copy contains 131,072 coefficients and
288 KiB of useful payload. Each of the 32 banks has depth 4,096 at width 18.
Using a nominal 2,048-by-18 BRAM36 organization requires two BRAM36 blocks per
bank, or 64 total. This saves 64 nominal BRAM36 blocks against two copies;
32 logical banks do not imply 32 physical BRAM36 blocks. Actual inference and
the complete device budget remain separate checks.

## 5. Accumulator order and certificate

Over mathematical integers, the R4 partition visits every reduction term once
and the final result is unchanged. With bounded intermediate arithmetic, equal
final dots do not prove identical behavior.

Concrete counterexample with `K=32`, one output, an 8-bit accumulator and
vector entries all equal to one:

```text
A[0] = A[1] = 100
A[8] = A[9] = -100
all other coefficients = 0
exact final dot = 0
```

In the old interleaved R4 order, lane zero sees `100,0,-100,...`, lane one
does likewise, and the other lanes remain zero. All local and tree values fit
in signed eight bits. In the proposed chunked order, lane zero reaches 200 at
`u=1`, which must fault; lane one's later partial sum can reach -200. Checking
only the final zero misses the problem.

The existing full-range bound already covers any accumulation order. For
signed operand widths `Wa,Wb` and at most `L` products, let:

```text
B    = L * 2^(Wa-1) * 2^(Wb-1)
Wacc = B.bit_length()+1
```

Every prefix, local partial and merge of disjoint term subsets has magnitude
at most `B`, so the same width suffices for this candidate. C18-by-S27 with
`L=1024` consequently still needs 55 bits under this bound; the layout change
does not intrinsically require a wider accumulator. A tighter declared-bound
certificate must also cover every prefix and tree intermediate. Runtime
overflow checks must remain active. The numerical oracle's final-dot-only
check is not such a certificate.

## 6. One-copy support gather

A separate support cache can use the same diagonal layout for `A_S`, with
`Q_S=ceil(S/32)`. For ordered support slot `s` and source atom `j[s]`, copy 32
consecutive valid rows per payload issue:

```text
source bank/address = (r+j[s]) mod 32, r*Q + floor(j[s]/32)
cache bank/address  = (r+s) mod 32,    r*Q_S + floor(s/32)
```

Both bank sets are permutations for 32 consecutive rows, and their difference
is the constant rotation `(s-j[s]) mod 32`. One read per source bank and one
write per destination bank suffice. The cache then serves both `A_S` and
`A_S^T`; it does not need a second transpose-copy pass.

The proposed payload issue count is `S*ceil(M/32)`, or 32 issues at
`M=128,S=8`. This is a cost specification only. It requires separate source
and destination physical stores, a registered response/buffer before writes,
valid masks and correctly generated addresses. Startup/drain, support-index
reads, arbitration, controller bubbles, cache invalidation and any new routing
latency must be added. No support-gather execution model or RTL was established
by this review, and overlap with compute is not assumed.

At `M=128,S<=96`, the diagonal cache bank depth is at most 384. A conservative
one-BRAM36-per-bank allocation is 32 BRAM36 blocks. With the main matrix's 64
and the existing illustrative context allocation of 36, these three regions
sum to 132 BRAM36 blocks. This is a partial candidate budget, not whole-design
utilization. For small `S`, column padding and shallow-bank granularity are
material.

Direct support access is a different schedule. Direct forward R1 still reads
a fixed selected column across 32 rows without conflict. Dense R4 cannot
simply substitute arbitrary atom IDs for its reduction indices: selected IDs
may have equal bank residues or overlapping eight-bank windows. A direct
transpose schedule also needs its own conflict analysis. The gather result
does not establish a free general sparse read path or cache break-even point.

## 7. Independent executable evidence and limits

A read-only Python check was run in the workspace on 2026-09-08, separately
from the candidate implementation. It generated the formulas above directly
and checked these shapes:

```text
(M,N) = (1,1), (3,35), (17,35), (31,33),
        (32,32), (33,31), (65,71), (128,1024)
```

For every valid coefficient it checked unique `(bank,address)` occupancy and
the inverse identity. For both orientations and both R modes it enumerated
each output tile and issue, masked invalid coordinates and checked that the
active bank list had no duplicates. The R4 enumeration used the full padded
`8*ceil(K/32)` loop. The reported **18,022 issue-bank checks** count those
tile/issue sets, including masked or empty positions; they are not clock
cycles measured from hardware. All checks passed.

For each shape and `S` in `{1,8,33,96}`, the check used
`j[s]=(29*s+7) mod N` and verified unique source/destination banks and constant
rotation for every 32-row gather group. Repeated IDs in this synthetic support
sequence were allowed solely to exercise copy addressing; this did not test
support-selection validity. The existing interleaved replay returned zero for
the overflow counterexample, while direct enumeration of the new lane prefixes
found a maximum positive partial of 200.

This evidence supports the storage and port proofs. It does not verify the
candidate's image importer/exporter, synchronous vector reads, stalls, reset,
DMA, support-cache execution, context execution or implemented feeder. It does
not establish synthesis utilization, clock frequency, sustained throughput,
board behavior or an end-to-end speedup. The candidate remains subject to
those implementation and correctness gates.
