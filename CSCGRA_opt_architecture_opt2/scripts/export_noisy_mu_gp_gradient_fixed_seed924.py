import json, re
from pathlib import Path
ROOT=Path(r'D:\vivado_pj')
REPO=ROOT/'CSCGRA_opt_architecture'
SCAN=ROOT/'analysis/reconstruction_quality_noisy24/gp_grad_step_fixed_seed_scan_k16_lt1000.json'
OUT=ROOT/'analysis/reconstruction_quality_noisy24/noisy_lfsr_24bit_gp_grad_step_fixed_k16_seed924.json'
VH=REPO/'tests/noisy_lfsr_24bit_cases.vh'
TARGET=924; MASK24=(1<<24)-1
scan=json.loads(SCAN.read_text())
entries=scan['top_by_snr']+scan.get('all_gt20',[])
entry=next(r for r in entries if r['seed']==TARGET)
OUT.write_text(json.dumps({'source_scan':str(SCAN),'algorithm':'GP_grad_step_scaled_fixed_rtl_phi','N':scan['N'],'M':scan['M'],'K':scan['K'],'mu_shift':scan['mu_shift'],'iters':scan['iters'],'x_seed':entry['seed'],'mse':entry['mse'],'snr_db':entry['snr_db'],'support_overlap':f"{entry['overlap']}/{scan['K']}",'true_support':entry['support'],'x_true_q24':entry['x_true_q24'],'y_clean_q24':entry['y_clean_q24'],'y_noisy_q24':entry['y_noisy_q24'],'x_hat_q24':entry['x_hat_q24']},indent=2))
text=VH.read_text()
text=re.sub(r'localparam integer NOISY_GP_SEED = \d+;', f'localparam integer NOISY_GP_SEED = {TARGET};', text)
def repl(func, vals):
 global text
 start=text.index(f'function signed [23:0] {func};')
 cstart=text.index('        case(idx)',start)
 default=f"        default: {func} = 24'sd0;"
 dend=text.index(default,cstart); eline=text.index('\n',dend)
 body=['        case(idx)']+[f"        {i}: {func} = 24'sh{(int(v)&MASK24):06x};" for i,v in enumerate(vals)]+[default]
 text=text[:cstart]+'\n'.join(body)+text[eline:]
repl('NOISY_GP_Y',entry['y_noisy_q24'])
repl('NOISY_GP_XHAT',entry['x_hat_q24'])
lines=[ln for ln in text.splitlines() if not ln.startswith('// GP golden override:')]
lines.insert(1,'// GP golden override: Python fixed-point grad-step reference seed924 (<1000), RTL Phi, see analysis/reconstruction_quality_noisy24/noisy_lfsr_24bit_gp_grad_step_fixed_k16_seed924.json')
VH.write_text('\n'.join(lines)+'\n')
print('seed',entry['seed'],'snr',entry['snr_db'],'overlap',entry['overlap'])
print('wrote',OUT)
