# Flow configuration

`project.json` is the single project selector and release-policy authority. It
separates two roles explicitly:

- `active_config=rtl-v2.json` is the last complete release baseline;
- `development_config=rtl-v3.json` is the current v3 implementation target.

V3 is not labelled as the active release while M13 device/board closure remains
open. M0-M12 RTL and the production lifecycle top are complete. The consistency checker validates its complete source
filelist, module ownership, verification root, architecture manifest and
[v3 status](../reports/v3/GOLDEN_STATUS.md), so it is no longer an untracked
side configuration.

`rtl-v2.json` contains only stable tool inputs: manifest, verification root,
default testbench/top, FPGA part, clock and architecture capacity. Dynamic
commit, timing, cycle and utilization values are forbidden here because they
become stale when source changes.

`rtl-v1.json` remains a historical reproduction map for `archive/v1`; it is
not selectable as the active project. Canonical run metadata records Git HEAD,
source dirty state, and content hashes so uncommitted RTL is still traceable.
