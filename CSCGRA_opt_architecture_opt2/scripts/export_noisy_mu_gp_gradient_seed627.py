import json
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]
WORKSPACE=REPO.parent
SCAN=WORKSPACE/'analysis/reconstruction_quality_noisy24/gp_grad_step_seed_scan_k16.json'
OUT=WORKSPACE/'analysis/reconstruction_quality_noisy24/noisy_lfsr_24bit_gp_grad_step_k16_seed627.json'
VH=REPO/'tests/noisy_lfsr_24bit_cases.vh'
TARGET_SEED=627
MASK24=(1<<24)-1
scan=json.loads(SCAN.read_text())
entries=scan['top_by_target25']+scan['top_by_snr']
entry=next(r for r in entries if r['seed']==TARGET_SEED)
OUT.write_text(json.dumps({
    'source_scan': str(SCAN),
    'algorithm': 'GP_grad_step_scaled',
    'N': scan['N'], 'M': scan['M'], 'K': scan['K'],
    'mu_shift': scan['mu_shift'], 'iters': scan['iters'],
    'x_seed': entry['seed'], 'mse': entry['mse'], 'snr_db': entry['snr_db'],
    'support_overlap': f"{entry['overlap']}/{scan['K']}",
    'true_support': entry['support'],
    'x_true_q24': entry['x_true_q24'],
    'y_clean_q24': entry['y_clean_q24'],
    'y_noisy_q24': entry['y_noisy_q24'],
    'x_hat_q24': entry['x_hat_q24'],
}, indent=2))
text=VH.read_text()
import re
text=re.sub(r'localparam integer NOISY_GP_SEED = \d+;', f'localparam integer NOISY_GP_SEED = {TARGET_SEED};', text)
def replace_func(func, vals):
    global text
    start=text.index(f'function signed [23:0] {func};')
    cstart=text.index('        case(idx)', start)
    default=f"        default: {func} = 24'sd0;"
    dend=text.index(default, cstart)
    eline=text.index('\n', dend)
    body=['        case(idx)']
    for i,v in enumerate(vals):
        body.append(f"        {i}: {func} = 24'sh{(int(v)&MASK24):06x};")
    body.append(default)
    text=text[:cstart]+'\n'.join(body)+text[eline:]
replace_func('NOISY_GP_Y', entry['y_noisy_q24'])
replace_func('NOISY_GP_XHAT', entry['x_hat_q24'])
lines=text.splitlines()
lines=[ln for ln in lines if not ln.startswith('// GP golden override:')]
lines.insert(1, '// GP golden override: Python grad-step reference seed627 (<1000), see analysis/reconstruction_quality_noisy24/noisy_lfsr_24bit_gp_grad_step_k16_seed627.json')
VH.write_text('\n'.join(lines)+'\n')
print(f'patched {VH}')
print(f'wrote {OUT}')
print(f"seed={entry['seed']} snr={entry['snr_db']:.4f} overlap={entry['overlap']}/{scan['K']}")
