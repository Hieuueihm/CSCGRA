# Generic scalar insertion (feature 6)

`SCALAR_INSERT` is kernel opcode 21. It replaces exactly one S27F22 lane of a
public vector with one S27F22 value captured from the sequencer scalar RF. It
is a generic range transaction; it does not name a QR/CoSaMP/SP algorithm or
allocate an arithmetic unit, PE, or RAM.

## Command and loaded-image ABI

Program-image revision stays 2. Feature 6 includes feature 5 and accepts an
opcode-21 kernel record with these canonical fields:

- `src_a` and `dst` are valid public vector descriptors. `length` is in
  `1..1024`; `index` is an RF value in `0..length-1` and selects the replaced
  lane. `scalar_a` is the RF value captured before dispatch. Register zero is
  a legal scalar source and therefore scalar field zero does not imply an
  unused field.
- The template index may name any loaded entry, but its descriptor, both bind
  masks, all 32 contexts, and every scalar/flag/shift/target control must be
  zero. `src_b`, auxiliary/support descriptors and lengths, `k`, flags,
  transpose, R4, and store mode are canonical zero. Captured job, tag, format,
  shape, key, generation, and matrix identity buses retain their ordinary
  generic-command ownership; they are not forced to zero by this transport.
- The sequencer checks the full signed 64-bit RF value fits S27F22 before it
  drives the existing 27-bit `scalar_a` request bus. The kernel therefore
  never observes a truncated value.

The response has the normal vector result: `count=length`, full-vector
`nonzero`, and the held job/tag/format identity. It does not return the scalar
as response data.

## Transactional execution

The range adjunct reads only the source lanes needed for the complete output.
For `SCALAR_INSERT` its scalar provider is virtual: it reads no auxiliary pool
block. Every source lane except the replaced lane must be valid. The replaced
source lane may be invalid, matching the existing replace-range rule. The
result is formed in the existing 32 scratch slots, retains exact tail masks,
and commits through feature-4 resident mapping when enabled. Source/destination
aliasing observes the pre-command mapping. No public validity publishes before
the final remap/copy commit.

A fault, cancellation, identity error, held-response mismatch, or invalid
source lane invalidates the whole requested destination extent and publishes no
partial result. Cancellation during resident remap retains the internal
permutation but leaves the full public destination invalid, as feature 4
requires.



The unused program descriptor indices for `SCALAR_INSERT` are canonical zero. The sequencer drives their unused raw `src_b`, support-base, and auxiliary-base buses to literal zero regardless of descriptor 0’s mapped base. This does not reserve vector 0, require its base to be zero, or add a null-vector RAM.

`SCALAR_INSERT` writes the full result through existing scratch slots and publishes the complete requested destination extent through the resident commit path. It does not publish one changed word directly.

## Compiler use

`scalar_insert=True` is opt-in. QR backsolve may replace a scalar construction
vector followed by `REPLACE_RANGE` with `SCALAR_INSERT` only after liveness
proves the construction vector has no remaining use. The default and existing
resident profiles retain their byte-identical command streams. The new
`compact` profile inherits resident feature requirements and enables this
replacement for QR algorithms. Both independent VMs use the same one-lane
replacement rule and retain existing DIV rounding and certificates.
