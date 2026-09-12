# Local reduction proposal after the correctness baseline

The current `stream_array` contains independent lanes and a central sequential
fold. It is not an implemented full-mesh CGRA. Merely grouping32 lanes as two
4x4 arrays does not establish routing novelty. This proposal adds a concrete
use for local array links while reusing arithmetic already inside the PEs.
It remains a proposal; there is no xsim or timing qualification for it yet.

## Terminal phase on existing ACC adders

After the final MAC frame, a loaded terminal-reduction mode routes a registered
64-bit neighbor partial into the PE's existing ACC adder with the multiplier
disabled. A new compatible template/context revision must declare this phase;
old reserved bits must not silently acquire meaning.

- R4: pair columns0+1 and2+3, then add the two partials at column0. The eight
  array rows produce eight independent outputs in two logical reduction levels.
- DOT/ENERGY: two pair levels per row, two levels between row roots inside
  each array, then one add between the two array roots. Five logical levels
  replace the sequential32-lane fold.
- Keep the raw accumulator throughout the tree. Round and check the target
  storage format only once at the same semantic boundary as the baseline.

This requires local64-bit links, registers, operand muxes and control. It does
not require a second multiplier array. Logical levels are not promised clock
cycles until the valid/ready pipeline is implemented and measured.

## Overflow and masks

Tree and serial summation can have different intermediate overflows in general.
For the existing bounded kernel interface, at most1024 signed S27 products
participate in a reduction. Every product magnitude is at most2^52, so the
sum of absolute product magnitudes is at most2^62, within signed64. This bound
also bounds every subtree and serial prefix; the C18 matrix path is narrower.
The proof requires the command's actual product-count limit, a cleared ACC
at command start and no arbitrary external ACC preload. Preserve the existing
policy or reject a mode outside that proven subset.

Inactive lanes contribute their already accumulated value where the baseline
includes it; the final mask is not permission to discard contributions from
earlier frames. Last-only tail masks, zero-length partial groups and stalls
must follow the accepted raw-accumulator contract.

## Shared performance evaluation

First retain the serialized feeder/fold source-bound snapshot. Then measure
request/retirement overlap, two frame credits, vector-block reuse and local
reduction as separate changes. Track matrix/vector join waits, queue/PE stalls,
accepted-frame intervals, scalar time and final publication cost.

Use full-program cycles per algorithm, alongside SNR/NMSE/correctness, at the
same100 MHz target. QR has many short dots and may benefit more than FISTA's
long matrix passes; report both and any regressions. Include LUT/FF, BRAM,
DSP and timing margin after correctness. Neither the local links nor a FIFO
alone establishes novelty, II1 throughput or a whole-program speedup.
