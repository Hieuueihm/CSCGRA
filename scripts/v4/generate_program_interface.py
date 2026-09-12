"""Generate the revision-two generic service-program interface."""
import argparse
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def render():
    a=json.loads((ROOT/'config/v4_program_interface.json').read_text())
    if a['revision']!=2 or sum(a['fields'].values())!=128:
        raise ValueError('unsupported program revision/geometry')
    values={'REVISION':a['revision'],'FORMAT':a['format']}
    values.update({k.upper():v for k,v in a['limits'].items()})
    kernel=json.loads((ROOT/'config/v4_kernel_interface.json').read_text())
    values.update({f'KERNEL_{k}':v for k,v in kernel['operations'].items()})
    for prefix,table in [('FIELD',a['fields']),('IMM',a['service_immediate_fields'])]:
        bit=0
        for key,width in table.items():
            values[f'{prefix}_{key.upper()}_LSB']=bit
            values[f'{prefix}_{key.upper()}_W']=width
            bit+=width
    for prefix,key in [('KIND','kinds'),('SCALAR_OP','scalar_operations'),('LOAD','load_kinds'),('CMP','comparisons'),('FAULT','faults'),('STATUS','statuses'),('LENGTH','length_modes')]:
        values.update({f'{prefix}_{k}':v for k,v in a[key].items()})
    masks=[]
    for kind,fields in a['allowed_fields'].items():
        mask=sum(((1<<a['fields'][name])-1)<<values[f'FIELD_{name.upper()}_LSB'] for name in ['kind',*fields])
        masks.append(f'`define CSR_PROGRAM_ALLOWED_{kind} 128\'h{mask:032x}')
    return '\n'.join(['`ifndef CSR_PROGRAM_INTERFACE_VH','`define CSR_PROGRAM_INTERFACE_VH','`include "stream_interface.vh"',
                      *[f'`define CSR_PROGRAM_{k} {v}' for k,v in values.items()],*masks,'`endif',''])

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args(argv)
    path=ROOT/'rtl/v4/include/program_interface.vh';expected=render()
    if args.check:
        if not path.is_file() or path.read_text()!=expected:raise SystemExit('program_interface.vh stale or missing')
    else:path.write_text(expected)
if __name__=='__main__':main()
