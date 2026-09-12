# Aligned operand feeder, candidate v1

This implements the unpack/permutation boundary from BASELINE, not a RAM
request scheduler, response joiner, support builder or array sequencer.
All sources in one request must already belong to the same descriptor,
generation, address schedule and job/tag/format. Upstream owns that check;
req_src_fault propagates any failed source/join check as SOURCE.
No autonomous cache read or inferred memory bandwidth is claimed.

## Layout and schedule

32 tiles are ordered array0 then array1, row-major within each 4x4.
In R4, tile=4*output_lane+reduction_lane: each physical row reduces one
output. Coefficients are signed C18F16 sign-extended, not rescaled, into
S27-wide matrix ports; vectors are raw S27F22. Bit 1 means positive Phi.
Scale must be positive signed C18; negative/zero/minimum values fault.
Widths come from the existing generated PE definitions; numerical candidate
status is unchanged. Dense B is already quantized signed C18, including its
minimum value. This boundary does not quantize or normalize it again.

| Mode | Output coordinate | Reduction coordinate | Source bank |
|---|---|---|---|
| PHI_R1 | out+tile (row) | red (column) | column mod 8 |
| PHI_R4 | out+floor(tile/4) (column) | red+8*(tile mod 4)+step (row) | column mod 8 |
| B_R1 | out+tile | red | (row+support_slot) mod 32 |
| B_R4 | out+floor(tile/4) | red+8*(tile mod 4)+step | (row+support_slot) mod 32 |

Phi R1 requires trans=0, Phi R4 trans=1. B trans selects forward or
transpose; columns means ordered support length, never global atom index.
R1 out is 32-aligned and step=0. R4 out is 8-aligned and red is 32-aligned;
step runs 0..7. red/out base must be inside the corresponding dimension.
R4 individual steps may have zero valid lanes on tiny tails and still retire.
R1 broadcasts vector slot0; R4 broadcasts vector slots0..3 along each
reduction lane. Out-of-shape lanes are zero with mask=0 and need no sources.

Sign bundles contain eight bank words/masks from phi_sign_cache; each used
bank address is floor(column/8)*ceil(M/32)+floor(row/32). The caller supplies
exactly that row block. R1 consumes one bank, R4 up to eight. Dense bundles
contain one coefficient per bank at address
row*ceil(S/32)+floor(support_slot/32). B_R4 covers all32 banks without
collision for a full frame, in either orientation. Unused banks may be invalid.
Required source absence faults the entire frame; it does not shorten tails.

## Handshake, faults and scope

Synchronous active-high reset and cancel discard the pending frame and clear
response registers. One outstanding frame, latency1, minimum II2; no same-edge
replacement. rsp_valid/req_ready are suppressed during reset/cancel. All
payload and tags hold under stall even if input pins change. Acceptance
captures job/tag/format/last verbatim. last is supplied by the schedule;
it does not mean all32 lanes are valid or authorize an early memory commit.
No owned arithmetic, RF, cache or program state exists in this module.

Fault priority: SHAPE (M1..128, N1..1024 or S1..96), INDEX (alignment,
orientation/base), SCALE (Phi only), SOURCE. Fault responses retain tags
but zero both operand frames and mask. Constants are generated from
config/v4_feeder_interface.json and the design limits. The fixed TB and
independent integer/cycle model verify mapping, masks, reset/cancel, stall,
fault priority and metadata; they do not certify full GEMV or LSQR execution.
