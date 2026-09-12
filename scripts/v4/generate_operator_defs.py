"""Generate the bounded resident execution candidate descriptor layout."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def render():
    config = json.loads((ROOT/'config/v4_operator_exec.json').read_text())
    lines = ['`ifndef CSR_OPERATOR_DEFS_VH', '`define CSR_OPERATOR_DEFS_VH',
             f'`define CSR_OP_REV {config["revision"]}',
             f'`define CSR_OP_DESCRIPTORS {config["descriptor_count"]}',
             f'`define CSR_OP_ADDRESS_MODE {config["address_mode"]}']
    offset = 0
    for name, width in config['descriptor_fields'].items():
        lines += [f'`define CSR_OP_{name.upper()}_LSB {offset}', f'`define CSR_OP_{name.upper()}_W {width}']
        offset += width
    return '\n'.join(lines+[f'`define CSR_OP_DESC_W {offset}', '`endif', ''])
if __name__ == '__main__':
    (ROOT/'rtl/v4/include/operator_defs.vh').write_text(render())
