"""Generate the generic service-program field/opcode contract."""
import argparse
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from compiler.v4.solver_program import ABI,FIELDS,OFFSETS
def render():
    if (ABI['instruction_bits'],ABI['depth'],ABI['scalar_registers'],ABI['scalar_register_width'])!=(128,256,32,64):raise ValueError('unsupported service machine geometry')
    values={'REVISION':ABI['revision']}
    for name,width in FIELDS.items():values[name.upper()+'_LSB']=OFFSETS[name];values[name.upper()+'_W']=width
    for prefix,table in [('OP',ABI['kinds']),('KERNEL',ABI['kernels']),('FAULT',ABI['faults'])]:
        values.update({prefix+'_'+k:v for k,v in table.items()})
    return '\n'.join(['`ifndef CSR_SOLVER_INTERFACE_VH','`define CSR_SOLVER_INTERFACE_VH',*[f'`define CSR_SOLVER_{k} {v}' for k,v in values.items()],'`endif',''])
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    path=ROOT/'rtl/v4/include/solver_interface.vh';expected=render()
    if args.check:
        if not path.exists() or path.read_text()!=expected:raise SystemExit('stale solver interface')
    else:path.write_text(expected)
if __name__=='__main__':main()
