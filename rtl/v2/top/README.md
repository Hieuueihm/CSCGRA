# RTL v2 top levels

- `cgra_top.v`: canonical OOC synthesis and K-sweep top level.
- `cgra_soc_top.v`: SoC/board-facing wrapper.

The canonical OOC command targets `cgra_top`; generated block designs,
bitstreams, and exported hardware platforms belong under ignored `work/`.
