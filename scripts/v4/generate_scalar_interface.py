"""Generate the explicitly bounded scalar leaf candidate interface."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def render():
    abi = json.loads((ROOT / 'config/v4_scalar_interface.json').read_text())
    pe = json.loads((ROOT / 'config/v4_pe_interface.json').read_text())
    tags = json.loads((ROOT / 'config/v4_phi_interface.json').read_text())
    required = dict(operand_width=64, state_width=27, state_frac=22,
                    job_width=16, tag_width=16, fmt_width=8, opcode_width=2,
                    fault_width=3, frac_width=8, format_id=1,
                    div_source_frac=0, sqrt_source_frac=44)
    if any(abi[k] != v for k, v in required.items()):
        raise ValueError('scalar candidate datapath requires explicit review for any format change')
    if (pe['state_width'], pe['state_frac'], pe['acc_width']) != (27, 22, 64):
        raise ValueError('scalar/PE candidate profile mismatch')
    if (tags['job_tag_bits'], tags['op_tag_bits'], tags['format_tag_bits']) != (16,16,8):
        raise ValueError('scalar/shared tag mismatch')
    if abi['ops'] != dict(DIV=0, SQRT=1) or abi['faults'] != dict(NONE=0, MODE=1, ZERO=2, NEGATIVE=3, RANGE=4):
        raise ValueError('scalar opcode/fault revision needs review')
    expected_schedule = dict(div_latency=87, sqrt_latency=33, fault_latency=1,
                             div_ii=89, sqrt_ii=35, fault_ii=3)
    if any(abi['schedule'][k] != v for k,v in expected_schedule.items()):
        raise ValueError('scalar schedule does not match iterative datapath')
    values = dict(N_W=64, S_W=27, S_F=22, JOB_W=16, TAG_W=16, FMT_W=8,
                  OP_W=2, FAULT_W=3, FRAC_W=8, FORMAT=1, DIV_FRAC=0, SQRT_FRAC=44)
    for prefix, table in [('OP',abi['ops']),('FAULT',abi['faults']),('SCHEDULE',expected_schedule)]:
        values.update({prefix+'_'+k.upper():v for k,v in table.items()})
    return '\n'.join(['`ifndef CSR_SCALAR_INTERFACE_VH','`define CSR_SCALAR_INTERFACE_VH',
                      *[f'`define CSR_SCALAR_{k} {v}' for k,v in values.items()], '`endif',''])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    path=ROOT/'rtl/v4/include/scalar_interface.vh'
    expected=render()
    if args.check:
        if not path.exists() or path.read_text()!=expected:
            raise SystemExit('scalar_interface.vh stale or missing')
    else:
        path.write_text(expected)

if __name__=='__main__':
    main()
