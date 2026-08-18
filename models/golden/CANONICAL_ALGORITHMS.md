# Canonical algorithm reference

The active RTL golden is a hardware-compatible fixed-point model. It must not
be presented as the textbook definition of every algorithm. This file records
the independent algorithmic references used for the audit.

| Name | Canonical reference | Required steps |
| --- | --- | --- |
| OMP | [Tropp & Gilbert, 2007](https://authors.library.caltech.edu/records/vyc9e-gq869/latest) | Pick one unused atom by correlation, add it to the support, solve least squares on the complete support, update the residual. |
| CoSaMP | [Needell & Tropp, 2008](https://arxiv.org/abs/0803.2392) | Pick `2K` proxy atoms, merge with the current support, solve on the union, keep the largest `K`, solve again, update residual. |
| IHT | [Blumensath & Davies, 2009](https://arxiv.org/abs/0805.0510) | Gradient step `x + mu A^T r`, then hard-threshold to `K`. |
| HTP | [Foucart, 2011](https://foucart.github.io/publi/HTP_Final.pdf) | Gradient proxy, hard-threshold support to `K`, then exact least squares on that support. |
| SP | [Dai & Milenkovic, 2008](https://arxiv.org/abs/0803.0811) | Pick `K` proxy atoms, merge, least squares, prune to `K`, least squares again. |
| gOMP | [Wang, Kwon & Shim, 2012](https://arxiv.org/abs/1111.6664) | Pick `L` new atoms per iteration, where the last iteration may pick fewer than `L`, then solve on the complete support. |
| MP | [Mallat & Zhang, 1993](https://doi.org/10.1109/78.258082) | Pick the largest normalized residual correlation, update that coefficient by the one-dimensional projection, and continue. Re-selection is allowed. |
| GP | [Blumensath & Davies, 2008](https://www.compressed-sensing.eng.ed.ac.uk/sites/compressed-sensing.eng.ed.ac.uk/files/publications/BDGP07.pdf) | Expand the support, use the restricted gradient as the direction, and choose a residual line-search step. This is not the same as IHT. |

`canonical_algorithms.py` implements these equations without RTL capacity
limits, Q-format shifts, or PE scheduling. It is an audit reference, not a
replacement for the v2 testbench golden yet.

## Current v2 deviations that must stay explicit

- The K-sweep generator uses a 16-entry merge cap for CoSaMP/SP. The canonical
  algorithms do not have this cap; it is a hardware capacity constraint.
- The current `GP` path is a full-vector gradient update followed by pruning,
  which is IHT-like. It is not the support-expanding line-search GP above.
- The current LS helper forms Gram/RHS in Python floating point, quantizes the
  coefficients, and then computes a fixed-point residual. It is not a cycle- or
  bit-accurate LDLT model.
- The active K-sweep algorithm index order is `OMP, CoSaMP, IHT, HTP, SP, GP,
  GOMP, MP`; the frozen per-iteration include uses a different historical
  order and must be mapped explicitly.
