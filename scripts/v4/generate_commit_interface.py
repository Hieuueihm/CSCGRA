"""Generate the fixed candidate result publication interface."""
import argparse
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def render():
    abi=json.loads((ROOT/'config/v4_commit_interface.json').read_text())
    pe=json.loads((ROOT/'config/v4_pe_interface.json').read_text())
    required=dict(state_width=27,state_frac=22,x_width=24,x_frac=20,lanes=32,
                  capacity=96,index_width=10,format_id=1)
    if any(abi[k]!=v for k,v in required.items()) or (pe['state_width'],pe['state_frac'])!=(27,22):
        raise ValueError('result publication supports only the explicit S27F22/X24F20 candidate')
    values=dict(S_W=27,X_W=24,SHIFT=2,LANES=32,CAPACITY=96,INDEX_W=10,FORMAT=1)
    values.update({'FAULT_'+k:v for k,v in abi['faults'].items()})
    return '\n'.join(['`ifndef CSR_COMMIT_INTERFACE_VH','`define CSR_COMMIT_INTERFACE_VH',
        *[f'`define CSR_COMMIT_{k} {v}' for k,v in values.items()],'`endif',''])
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true')
    args=parser.parse_args();path=ROOT/'rtl/v4/include/commit_interface.vh';expected=render()
    if args.check:
        if not path.exists() or path.read_text()!=expected:raise SystemExit('stale commit interface')
    else:path.write_text(expected)
if __name__=='__main__':main()
