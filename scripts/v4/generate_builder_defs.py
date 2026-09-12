"""Generate support builder fault definitions from its candidate contract."""
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
def render():
    cfg=json.loads((ROOT/'config/v4_builder_exec.json').read_text())
    return '\n'.join(['`ifndef CSR_BUILDER_DEFS_VH','`define CSR_BUILDER_DEFS_VH']+[f'`define CSR_BUILD_FAULT_{k} 4\'d{v}' for k,v in cfg['faults'].items()]+['`endif',''])
if __name__=='__main__':
    p=ROOT/'rtl/v4/include/builder_defs.vh'
    if '--check' in sys.argv:
        if p.read_text()!=render(): raise SystemExit('builder definitions drift')
    else: p.write_text(render())
