# Selection and support service contract

This extension belongs to the shared kernel described in
[STREAM_SYSTEM_CONTRACT.md](STREAM_SYSTEM_CONTRACT.md). It has no multiplier
array or private copy of the vector pool. `support_service` owns its scan,
index masks and candidate state; `stream_kernel` owns RAM arbitration, source
validity and destination publication. All RTL qualification uses Vivado xsim.

## Common representation and transaction

`length=N` is the index domain, 1..1024. An index is an unscaled S27 integer
in 0..N-1. Lists have explicit lengths, including zero. This service is not
limited to the 96 columns of support LS; the B builder enforces that limit.
Public bases are blocks 0..479; each block contains 32 elements. Bounds and
initialized lane masks are checked on every required read. Unused lanes are
never interpreted as indices or operands.

An accepted request captures operation, dimensions, bases, flags and identity.
One command executes at a time. Responses and pending RAM requests hold all
payload under backpressure; reset/cancel flush ownership and pending responses.
Metadata validation includes the requested RAM tag and mask.

All destination writes go to reserved scratch blocks 480..511. The core
copies and publishes only after successful completion, preserving alias safety.
A scalar-only or zero-length packed result performs no destination writes.
The internal response distinguishes publication length from support count:
APPLY_SUPPORT/SCATTER publish N values but return support cardinality S in
the public kernel `rsp_count`. TOPK/UNION/GATHER return their packed length
as count; PICK returns zero. Capacity overflow faults and never truncates a
support silently. Whole-job commit is a separate top concern.

`rsp_nonzero` describes emitted values, not cardinality. Selecting only index0
has count1 but nonzero=false. Programs use `rsp_count` to detect an empty
selection. PICK uses the selected value's zero/nonzero result.

## Operations

| Operation | Inputs and result | Flags |
|---|---|---|
| TOPK | Read `src_a[N]`, choose up to `k` indices by descending absolute magnitude; lower original index wins ties. Return count=min(k, available). Zero scores remain eligible. | Bit0 excludes `support_base[support_length]`; bit1 sorts the selected indices ascending before output. Default output order is rank order. |
| APPLY_SUPPORT | Dense N-element output: values from `src_a` at support indices, zero elsewhere. | Zero |
| GATHER | Packed output `src_a[support[i]]`, preserving support order; count=support_length. | Zero |
| SCATTER | Dense N-element output initially zero; write packed `src_a[i]` at support[i]. No accumulation. | Zero |
| UNION | Combine `support_base[support_length]` and `aux_base[aux_length]`; deduplicate both lists. `k` is destination capacity. | Bit0 preserves first occurrence order, scanning first list then second. Default is ascending index order. |
| PICK | Return sign-extended raw `src_a[index]` in scalar response, with no vector writes. | Zero |

TOPK/UNION require k=1..1024. All other unassigned flag bits fault. TOPK
excluded duplicates have set semantics. APPLY_SUPPORT/GATHER/SCATTER reject
duplicate support indices because these operations act on a support set.
An empty support produces dense zeros for APPLY_SUPPORT/SCATTER, or no packed
output for GATHER. UNION of two empty lists is a successful empty result.

OMP/GOMP use TOPK with exclusion followed by ordered UNION. CoSaMP/SP use
sorted UNION and pruning with ascending TOPK output. MP/GP preserve first
occurrence order. These choices belong to the loaded program, not classifiers
inside the service. Constant-magnitude live Phi has equal quantized column
norms, so raw magnitude gives the same normalized ranking for MP/OMP; this
does not extend to arbitrary dense measurement matrices.

## Read cost and timing

TOPK scans one 32-lane pool block at a time through a pipelined absolute-value
argmax tree. A 1024-bit mask tracks excluded and already selected indices.
Repeating the scan K times needs at most K*ceil(N/32) input read grants,
plus explicit list reads and output writes. This count is not a cycle claim:
RAM latency, pipeline drain, arbitration and publication remain measured costs.
Handle the most negative S27 value using an unsigned magnitude of sufficient
width. Sorting selected indices may scan the selection mask, but must not
introduce an unreported second dense value pool.

### Bounded bitmap enumeration

`support_service` has an implementation parameter `BITMAP_ENUM_ENABLE`, enabled
by default, for A/B qualification of the completed-bitmap `SORT` phase. It has
no request or response port and does not change the public ABI. Sorted TOPK
enumerates `selected`; unordered UNION enumerates `seen`. Ordered UNION keeps its
first-occurrence `PACK` path and never selects this mode.

The service selects the word path only when
`ceil(length / 32) + result_count < length`. It loads one command-local 32-bit
word, emits its least significant set lane, and clears that lane before the next
emission. Word bases and lanes increase monotonically, so the resulting indices
have the same ascending order as the legacy per-index scan. A zero word advances
in its load cycle; the final emitted lane clears the word and advances its base.
Consequently the sparse enumeration work is one word load per bitmap word plus
one emission per selected index, followed by the existing transition to `PACK`.
The dense inequality leaves the legacy scan unchanged.

The local word is cleared at command capture, fail, cancel, and reset. The path
neither reads the vector pool nor changes `selected`, `seen`, candidate handling,
or `PACK`/`WRITE`, so existing RAM, stall, publication, and fault behavior remain
owned by the established states.


Verification covers N=1, tails and N=1024; K=1 and full capacity; ties,
negative extrema, exclusions, empty lists, duplicate/out-of-range indices,
ordered versus sorted union, aliasing, backpressure, identity faults and
cancel at each endpoint. Compare against an independent integer oracle.
