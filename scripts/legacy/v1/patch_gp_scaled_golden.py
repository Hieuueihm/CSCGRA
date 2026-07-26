import json, re
from pathlib import Path
root=Path(r'D:\vivado_pj\CSCGRA_opt_architecture')
json_path=Path(r'D:\vivado_pj\analysis\reconstruction_quality_noisy24\noisy_lfsr_24bit_per_algorithm_seed_k8_gp_scaled.json')
data=json.loads(json_path.read_text())
gp=data['algorithms']['GP']

def u24(v): return int(v) & 0xffffff

def c_array(vals, indent='        ', per=8):
    parts=[]
    for i in range(0,len(vals),per):
        chunk=', '.join(f'0x{u24(v):08X}U' for v in vals[i:i+per])
        suffix=',' if i+per < len(vals) else ''
        parts.append(indent+chunk+suffix)
    return '\n'.join(parts)

def replace_alg_block(text, array_name, alg_comment, vals):
    start=text.index(f'static const uint32_t {array_name}')
    # find GP comment after array start
    gp_start=text.index(f'    /* {alg_comment} */ {{', start)
    content_start=gp_start + len(f'    /* {alg_comment} */ {{')
    # find matching block end: first \n    }, after gp_start
    end=text.index('\n    }', content_start)
    new='    /* '+alg_comment+' */ {\n'+c_array(vals)+'\n    }'
    return text[:gp_start]+new+text[end+len('\n    }'):]

cpath=root/'sdk_app/src/main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c'
text=cpath.read_text()
def repl_array_line(text,name,value):
    m=re.search(rf'static const uint32_t {name}\[NOISY24_ALG_COUNT\] = \{{ ([^}}]*) \}};', text)
    vals=[x.strip() for x in m.group(1).split(',')]
    vals[5]=f'{value}U'
    return text[:m.start()]+f'static const uint32_t {name}[NOISY24_ALG_COUNT] = {{ '+', '.join(vals)+' };'+text[m.end():]
text=repl_array_line(text,'noisy24_x_seed',int(gp['x_seed']))
text=repl_array_line(text,'noisy24_mse_e10',round(gp['mse']*1e10))
text=repl_array_line(text,'noisy24_snr_db_x100',round(gp['snr_db']*100))
text=re.sub(r'#define NOISY24_RUNNER_BUILD_TAG ".*"',
            f'#define NOISY24_RUNNER_BUILD_TAG "2026-07-04 k8_gp_scaled_seed{int(gp["x_seed"])}_v1"',
            text)
text=replace_alg_block(text,'noisy24_y_noisy[NOISY24_ALG_COUNT][64]','GP',gp['y_noisy_q24'])
text=replace_alg_block(text,'noisy24_x_true[NOISY24_ALG_COUNT][256]','GP',gp['x_true_q24'])
text=replace_alg_block(text,'noisy24_x_hat[NOISY24_ALG_COUNT][256]','GP',gp['x_hat_q24'])
cpath.write_text(text)

# patch TB functions gold_y and gold_xhat case 5

def sv_case(func, vals):
    lines=[f'  5: begin case(idx)']
    for i,v in enumerate(vals):
        lines.append(f"    {i}: {func} = 24'h{u24(v):06X};")
    lines.append(f"    default: {func} = 24'h000000; endcase end")
    return '\n'.join(lines)

def replace_sv_case(text, func, vals):
    fstart=text.index(f'function [23:0] {func};')
    cstart=text.index('  5: begin case(idx)', fstart)
    # case 5 ends at its default line
    dend=text.index(f"    default: {func} = 24'h000000; endcase end", cstart)
    dend=text.index('\n', dend)
    new=sv_case(func, vals)
    return text[:cstart]+new+text[dend:]

for rel in [
    'tests/tb_noisy24_k8_rep_final.v',
    'tests/run1/tb_run1_noisy24_k8_rep.v',
    'tests/run1/tb_run1_noisy24_k8_rep_gpopt.v',
]:
    tpath=root/rel
    txt=tpath.read_text()
    txt=replace_sv_case(txt,'gold_y',gp['y_noisy_q24'])
    txt=replace_sv_case(txt,'gold_xhat',gp['x_hat_q24'])
    tpath.write_text(txt)
print('patched GP golden from', json_path)
print('GP mse_e10', round(gp['mse']*1e10), 'snr_x100', round(gp['snr_db']*100))
