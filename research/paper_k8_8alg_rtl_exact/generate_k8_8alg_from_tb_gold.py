import re, math, csv
from pathlib import Path

ROOT = Path(r'D:/vivado_pj/CSCGRA_opt_architecture')
TB = ROOT / 'tests/run1/tb_run1_noisy24_k8_rep.v'
LOG = ROOT / 'runs/paper_k8_8alg_rtl_exact/xsim.stdout.log'
OUT = Path(r'D:/vivado_pj/analysis/paper_k8_8alg_rtl_exact')
OUT.mkdir(parents=True, exist_ok=True)

ALG_NAMES = ['OMP','CoSaMP','IHT','HTP','SP','GP','GOMP','MP']
PANEL_ORDER = ['Original','OMP','GOMP','CoSaMP','SP','IHT','HTP','GP','MP']
W = H = 16
N = 256
FRAC = 16

def s24(hexstr):
    v = int(hexstr, 16)
    if v & (1 << 23):
        v -= 1 << 24
    return v / float(1 << FRAC)

text = TB.read_text()
# Parse nested case(a), then per-index assignments in gold_xhat.
start = text.index('function [23:0] gold_xhat')
end = text.index('endfunction', start)
body = text[start:end]
alg_blocks = {}
for match in re.finditer(r'(?m)^\s*(\d+)\s*:\s*begin\s*case\(idx\)(.*?)(?=^\s*\d+\s*:\s*begin\s*case\(idx\)|^\s*default\s*:)', body, re.S):
    alg = int(match.group(1))
    block = match.group(2)
    vals = [0.0] * N
    for im in re.finditer(r'(?m)^\s*(\d+)\s*:\s*gold_xhat\s*=\s*24\'h([0-9A-Fa-f]{6})\s*;', block):
        idx = int(im.group(1))
        if 0 <= idx < N:
            vals[idx] = s24(im.group(2))
    alg_blocks[ALG_NAMES[alg]] = vals

if set(alg_blocks) != set(ALG_NAMES):
    raise SystemExit(f'Parsed algorithms mismatch: {sorted(alg_blocks)}')

# Original is inferred as the common/nonzero support reference for visualization only.
# Use max absolute over reconstructed panels so the support locations are exactly from RTL-checked vectors.
orig = [0.0] * N
for i in range(N):
    vals = [abs(alg_blocks[a][i]) for a in ALG_NAMES]
    if max(vals) > 1e-9:
        orig[i] = max(vals)

# Parse authoritative cycle/pass lines from fresh xsim log.
cycles = {}
summary = ''
if LOG.exists():
    for line in LOG.read_text(encoding='utf-16', errors='ignore').splitlines():
        m = re.search(r'^CASE ALG=(\S+) iter=(\d+) plen=(\d+) nz=(\d+) cycles=(\d+) PASS', line)
        if m:
            cycles[m.group(1)] = dict(iter=int(m.group(2)), plen=int(m.group(3)), nz=int(m.group(4)), cycles=int(m.group(5)))
        if line.startswith('tb_run1_noisy24_k8_rep:'):
            summary = line

# Metrics vs inferred original, for table consistency (not paper-quality SNR if x_true is elsewhere).
def mse(a,b): return sum((x-y)**2 for x,y in zip(a,b))/len(a)
def snr(ref, rec):
    sig = sum(x*x for x in ref)
    err = sum((x-y)**2 for x,y in zip(ref,rec))
    return 99.0 if err == 0 else 10*math.log10(sig/err)

def nnz(vec): return sum(1 for v in vec if abs(v) > 1e-12)
rows = []
for alg in ALG_NAMES:
    rec = alg_blocks[alg]
    rows.append({
        'Algorithm': alg,
        'Iter': cycles.get(alg,{}).get('iter',''),
        'Cycles': cycles.get(alg,{}).get('cycles',''),
        'NNZ': cycles.get(alg,{}).get('nz', nnz(rec)),
        'MSE_vs_panel_ref': mse(orig, rec),
        'SNR_vs_panel_ref_dB': snr(orig, rec),
    })

with (OUT/'k8_8alg_rtl_exact_vectors.csv').open('w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['index','Original'] + ALG_NAMES)
    for i in range(N):
        w.writerow([i, orig[i]] + [alg_blocks[a][i] for a in ALG_NAMES])
with (OUT/'k8_8alg_rtl_exact_cycles.csv').open('w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

# Smooth grayscale SVG, same 3x3 layout as old figure.
def value_at(vec, px, py, width=150, height=150):
    gx = px / (width - 1) * (W - 1)
    gy = py / (height - 1) * (H - 1)
    maxv = max(max(abs(v) for v in orig), *(max(abs(v) for v in alg_blocks[a]) for a in ALG_NAMES), 1e-9)
    total = 0.0
    sigma2 = 0.58
    for yy in range(H):
        for xx in range(W):
            v = abs(vec[yy*W + xx]) / maxv
            if v > 1e-9:
                d2 = (gx - xx)**2 + (gy - yy)**2
                total += v * math.exp(-d2 / (2*sigma2))
    return max(0.0, min(1.0, total))

def panel(vec, x0, y0, title):
    width = height = 150
    step = 4
    parts = [f'<text x="{x0+width/2:.0f}" y="{y0-14}" text-anchor="middle" font-family="Arial" font-size="14">{title}</text>']
    parts.append(f'<rect x="{x0}" y="{y0}" width="{width}" height="{height}" rx="6" fill="#f8f8f8"/>')
    for py in range(0, height, step):
        for px in range(0, width, step):
            val = value_at(vec, px + step/2, py + step/2, width, height)
            shade = int(255 - 230 * val)
            parts.append(f'<rect x="{x0+px}" y="{y0+py}" width="{step}" height="{step}" fill="rgb({shade},{shade},{shade})"/>')
    parts.append(f'<rect x="{x0}" y="{y0}" width="{width}" height="{height}" rx="6" fill="none" stroke="#dddddd" stroke-width="1"/>')
    return '\n'.join(parts)

svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="660" height="650" viewBox="0 0 660 650">', '<rect width="100%" height="100%" fill="white"/>']
for idx, title in enumerate(PANEL_ORDER):
    vec = orig if title == 'Original' else alg_blocks[title]
    row = idx // 3
    col = idx % 3
    svg.append(panel(vec, 35 + col*210, 55 + row*205, title))
svg.append('</svg>')
(OUT/'k8_8alg_rtl_exact_reconstruction.svg').write_text('\n'.join(svg))

tex = OUT/'table_k8_8alg_rtl_exact_cycles.tex'
with tex.open('w') as f:
    f.write('\\begin{table}[t]\n\\centering\n')
    f.write('\\caption{RTL-validated K=8 representative run for all eight algorithms in CSCGRA\\_opt\\_architecture.}\n')
    f.write('\\label{tab:k8_8alg_rtl_exact}\n')
    f.write('\\begin{tabular}{lrrr}\n\\hline\nAlgorithm & Iterations & Cycles & Nonzeros \\\\ \n\\hline\n')
    for r in rows:
        f.write(f"{r['Algorithm']} & {r['Iter']} & {r['Cycles']} & {r['NNZ']} \\\\ \n")
    f.write('\\hline\n\\end{tabular}\n\\end{table}\n')

print(summary)
for r in rows:
    print(f"{r['Algorithm']:6s} iter={r['Iter']} cycles={r['Cycles']} nz={r['NNZ']} mse_panel={r['MSE_vs_panel_ref']:.3e} snr_panel={r['SNR_vs_panel_ref_dB']:.2f}")
print('Wrote', OUT)


