import re
from pathlib import Path
root=Path(r'D:\vivado_pj')
src=root/'golden_model/golden_cases.vh'
out=root/'CSCGRA_opt/tests/k_sweep_golden.vh'
text=src.read_text(errors='ignore')

def parse_hex_func(fname):
    m=re.search(rf"function\s+\[[^\]]+\]\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise SystemExit(f'missing {fname}')
    vals={}
    for mm in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*24'h([0-9a-fA-F]+)\s*;", m.group('body')):
        vals[int(mm.group(1))]=int(mm.group(2),16)
    return vals

def parse_int_func(fname):
    m=re.search(rf"function\s+integer\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise SystemExit(f'missing {fname}')
    vals={}
    for mm in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*(\d+)\s*;", m.group('body')):
        vals[int(mm.group(1))]=int(mm.group(2))
    return vals

def param(name):
    m=re.search(rf"localparam\s+integer\s+{name}\s*=\s*(\d+)\s*;", text)
    if not m:
        raise SystemExit(f'missing param {name}')
    return int(m.group(1))

max_n=param('GOLD_MAX_N')
max_iters=param('GOLD_MAX_ITERS')
gold_algs=param('GOLD_ALGS')
gold_y=parse_hex_func('gold_y')
gold_x=parse_hex_func('gold_iter_x_hat')
seed=parse_int_func('gold_case_seed').get(0,17)
scale=parse_hex_func('gold_case_scale').get(0,0x4000)
phi_kind=parse_hex_func('gold_case_phi_kind').get(0,0)
# k-sweep runner alg order: OMP, CoSaMP, IHT, HTP, SP, GP, GOMP, MP
tb_to_gold=[0,2,4,5,3,6,1,7]
cases=[(64,256,4),(64,256,8),(64,256,16)]
lines=[]
lines.append('// Auto-generated from immutable golden_model/golden_cases.vh')
lines.append('// Source manifest: golden_model/manifest.json')
lines.append('// Covers only configurations present in the immutable reference: m64/n256/k4,k8,k16.')
lines.append('localparam integer KSWEEP_GOLD_CASES = 3;')
lines.append('localparam integer KSWEEP_GOLD_ALGS = 8;')
lines.append('localparam integer KSWEEP_GOLD_MAX_N = 256;')
lines.append('localparam integer KSWEEP_GOLD_TOL = 512;')
for ci,(m,n,k) in enumerate(cases):
    lines.append(f'localparam integer KSWEEP_CASE_{ci}_M = {m};')
    lines.append(f'localparam integer KSWEEP_CASE_{ci}_N = {n};')
    lines.append(f'localparam integer KSWEEP_CASE_{ci}_K = {k};')

def emit_int(name, vals, default='0'):
    lines.append(f'function integer {name};')
    lines.append('input integer case_idx; begin case(case_idx)')
    for i,v in enumerate(vals): lines.append(f'  {i}: {name} = {v};')
    lines.append(f'  default: {name} = {default}; endcase end endfunction')

emit_int('ksgold_case_m',[c[0] for c in cases])
emit_int('ksgold_case_n',[c[1] for c in cases])
emit_int('ksgold_case_k',[c[2] for c in cases])
emit_int('ksgold_case_seed',[seed]*len(cases), str(seed))
lines.append('function [23:0] ksgold_case_scale;')
lines.append('input integer case_idx; begin case(case_idx)')
for i in range(len(cases)): lines.append(f"  {i}: ksgold_case_scale = 24'h{scale:06X};")
lines.append(f"  default: ksgold_case_scale = 24'h{scale:06X}; endcase end endfunction")
emit_int('ksgold_case_phi_kind',[phi_kind]*len(cases), str(phi_kind))
lines.append('function [23:0] ksgold_y;')
lines.append('input integer elem_idx; begin case(elem_idx)')
for i in range(64):
    lines.append(f"  {i}: ksgold_y = 24'h{gold_y.get(i,0):06X};")
lines.append("  default: ksgold_y = 24'h000000; endcase end endfunction")
lines.append('function [23:0] ksgold_x_final;')
lines.append('input integer case_idx; input integer alg_idx; input integer elem_idx; begin case(((case_idx * KSWEEP_GOLD_ALGS + alg_idx) * KSWEEP_GOLD_MAX_N) + elem_idx)')
for ci,(_m,_n,k) in enumerate(cases):
    iter_idx=k-1
    for tb_alg,g_alg in enumerate(tb_to_gold):
        for elem in range(256):
            key=((0*gold_algs + g_alg)*max_iters + iter_idx)*max_n + elem
            val=gold_x.get(key,0)
            if val:
                flat=((ci*8 + tb_alg)*256) + elem
                lines.append(f"  {flat}: ksgold_x_final = 24'h{val:06X};")
lines.append("  default: ksgold_x_final = 24'h000000; endcase end endfunction")
out.write_text('\n'.join(lines)+'\n', newline='\n')
print(out)
