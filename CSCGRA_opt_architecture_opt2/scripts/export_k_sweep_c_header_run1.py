import re
from pathlib import Path
root=Path(r'D:\vivado_pj')
vh=(root/'CSCGRA_noisy_mu_peop8/tests/run1/k_sweep_golden_mu3.vh').read_text()
out=root/'CSCGRA_noisy_mu_peop8/sdk_app/run1/cscgra_k_sweep_golden.h'
case_count=int(re.search(r'KSWEEP_GOLD_CASES = (\d+)', vh).group(1))
alg_count=int(re.search(r'KSWEEP_GOLD_ALGS = (\d+)', vh).group(1))
max_n=int(re.search(r'KSWEEP_GOLD_MAX_N = (\d+)', vh).group(1))
ms=[int(re.search(rf'KSWEEP_CASE_{i}_M = (\d+)', vh).group(1)) for i in range(case_count)]
ns=[int(re.search(rf'KSWEEP_CASE_{i}_N = (\d+)', vh).group(1)) for i in range(case_count)]
ks=[int(re.search(rf'KSWEEP_CASE_{i}_K = (\d+)', vh).group(1)) for i in range(case_count)]
y=[0]*64
for mm in re.finditer(r"\b(\d+)\s*:\s*ksgold_y\s*=\s*24'h([0-9A-Fa-f]+);", vh):
    idx=int(mm.group(1))
    if idx < len(y): y[idx]=int(mm.group(2),16)
x=[[[0 for _ in range(max_n)] for _ in range(case_count)] for _ in range(alg_count)]
for mm in re.finditer(r"\b(\d+)\s*:\s*ksgold_x_final\s*=\s*24'h([0-9A-Fa-f]+);", vh):
    flat=int(mm.group(1)); val=int(mm.group(2),16)
    elem=flat % max_n
    tmp=flat // max_n
    alg=tmp % alg_count
    case=tmp // alg_count
    if case < case_count and alg < alg_count and elem < max_n:
        x[alg][case][elem]=val
lines=[]
lines.append('#ifndef CSCGRA_K_SWEEP_GOLDEN_H')
lines.append('#define CSCGRA_K_SWEEP_GOLDEN_H')
lines.append('')
lines.append('#include <stdint.h>')
lines.append('')
lines.append('#define KSGOLD_MAX_M 64U')
lines.append(f'#define KSGOLD_MAX_N {max_n}U')
lines.append('#define KSGOLD_SEED 17U')
lines.append('#define KSGOLD_SCALE 0x00004000U')
lines.append('#define KSGOLD_PHI_KIND 0U')
lines.append('#define KSGOLD_TOL 512U')
lines.append(f'#define KSGOLD_ALG_COUNT {alg_count}U')
lines.append(f'#define KSGOLD_CASE_COUNT {case_count}U')
lines.append('#define KSGOLD_SOURCE_TAG "CSCGRA_noisy_mu_peop8/tests/run1/k_sweep_golden_mu3.vh"')
lines.append('#define KSGOLD_MU_SHIFT 3U')
lines.append('')
lines.append('static const char * const ksgold_alg_names[KSGOLD_ALG_COUNT] = {')
lines.append('    "OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"')
lines.append('};')
lines.append('')
lines.append('static const uint32_t ksgold_case_m[KSGOLD_CASE_COUNT] = { ' + ', '.join(f'{v}U' for v in ms) + ' };')
lines.append('static const uint32_t ksgold_case_n[KSGOLD_CASE_COUNT] = { ' + ', '.join(f'{v}U' for v in ns) + ' };')
lines.append('static const uint32_t ksgold_case_k[KSGOLD_CASE_COUNT] = { ' + ', '.join(f'{v}U' for v in ks) + ' };')
lines.append('')
def emit_array(vals, indent):
    for i in range(0,len(vals),8):
        suffix=',' if i+8 < len(vals) else ''
        lines.append(indent + ', '.join(f'0x{v:08X}U' for v in vals[i:i+8]) + suffix)
lines.append('static const uint32_t ksgold_y[KSGOLD_MAX_M] = {')
emit_array(y,'    ')
lines.append('};')
lines.append('')
lines.append('static const uint32_t ksgold_x_final[KSGOLD_ALG_COUNT][KSGOLD_CASE_COUNT][KSGOLD_MAX_N] = {')
for alg in range(alg_count):
    lines.append('    {')
    for case in range(case_count):
        lines.append('        {')
        emit_array(x[alg][case], '            ')
        lines.append('        },')
    lines.append('    },')
lines.append('};')
lines.append('')
lines.append('#endif')
out.write_text('\n'.join(lines)+'\n', newline='\n')
print(out)
