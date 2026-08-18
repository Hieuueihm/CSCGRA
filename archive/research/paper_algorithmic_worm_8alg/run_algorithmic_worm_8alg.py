import math, random, csv, struct, zlib
from pathlib import Path

OUT = Path(r'D:/vivado_pj/analysis/paper_algorithmic_worm_8alg')
OUT.mkdir(parents=True, exist_ok=True)
W = H = 16
N = 256
M = 64
K = 12
NOISE_DB = 24.0
SEED = 137

# Worm-like sparse signal.
points = [
    (4,5,0.92),(5,6,1.00),(6,6,0.88),(7,7,0.96),
    (8,7,0.84),(9,8,0.91),(10,8,0.80),(11,9,0.72),
    (5,5,0.58),(6,7,0.62),(8,8,0.54),(10,9,0.50)
]
x = [0.0] * N
for px, py, amp in points:
    x[py*W + px] = amp
true_support = {py*W + px for px, py, amp in points}

rng = random.Random(SEED)
# Column-normalized Gaussian sensing matrix.
Phi = [[rng.gauss(0.0, 1.0) for _ in range(N)] for _ in range(M)]
for j in range(N):
    norm = math.sqrt(sum(Phi[i][j] * Phi[i][j] for i in range(M))) or 1.0
    for i in range(M):
        Phi[i][j] /= norm

def matvec(A, v):
    return [sum(row[j] * v[j] for j in range(len(v))) for row in A]

def residual(y, xhat):
    Ax = matvec(Phi, xhat)
    return [yi - ai for yi, ai in zip(y, Ax)]

def corr(r):
    return [sum(Phi[i][j] * r[i] for i in range(M)) for j in range(N)]

def topk_abs(v, k, exclude=None):
    exclude = exclude or set()
    return sorted((i for i in range(len(v)) if i not in exclude), key=lambda i: abs(v[i]), reverse=True)[:k]

def hard_threshold(v, k):
    keep = set(topk_abs(v, k))
    return [v[i] if i in keep else 0.0 for i in range(len(v))]

def support(v, eps=1e-10):
    return {i for i, val in enumerate(v) if abs(val) > eps}

def solve_linear(A, b):
    n = len(b)
    if n == 0:
        return []
    Mx = [row[:] + [b[i]] for i, row in enumerate(A)]
    for col in range(n):
        piv = max(range(col, n), key=lambda r: abs(Mx[r][col]))
        if abs(Mx[piv][col]) < 1e-12:
            Mx[piv][col] += 1e-8
        Mx[col], Mx[piv] = Mx[piv], Mx[col]
        pv = Mx[col][col]
        if abs(pv) < 1e-12:
            pv = 1e-12
        for c in range(col, n + 1):
            Mx[col][c] /= pv
        for r in range(n):
            if r == col:
                continue
            f = Mx[r][col]
            if f:
                for c in range(col, n + 1):
                    Mx[r][c] -= f * Mx[col][c]
    return [Mx[i][n] for i in range(n)]

def least_squares(T, y):
    T = list(dict.fromkeys(T))
    s = len(T)
    if s == 0:
        return [0.0] * N
    G = [[0.0] * s for _ in range(s)]
    rhs = [0.0] * s
    for a, ja in enumerate(T):
        rhs[a] = sum(Phi[i][ja] * y[i] for i in range(M))
        for b, jb in enumerate(T):
            G[a][b] = sum(Phi[i][ja] * Phi[i][jb] for i in range(M))
        G[a][a] += 1e-9
    z = solve_linear(G, rhs)
    xhat = [0.0] * N
    for idx, val in zip(T, z):
        xhat[idx] = val
    return xhat

def norm2(v):
    return math.sqrt(sum(t*t for t in v))

def add_noise(y, db):
    rr = random.Random(SEED + 999)
    n = [rr.gauss(0.0, 1.0) for _ in y]
    yn = norm2(y); nn = norm2(n) or 1.0
    scale = yn / (10 ** (db / 20.0)) / nn
    return [yi + scale * ni for yi, ni in zip(y, n)]

y_clean = matvec(Phi, x)
y = add_noise(y_clean, NOISE_DB)

def omp(iters=K):
    T = []
    xhat = [0.0] * N
    r = y[:]
    for _ in range(iters):
        c = corr(r)
        j = max((i for i in range(N) if i not in T), key=lambda i: abs(c[i]))
        T.append(j)
        xhat = least_squares(T, y)
        r = residual(y, xhat)
    return xhat

def gomp(group=2, iters=(K + 1)//2):
    T = []
    xhat = [0.0] * N
    r = y[:]
    for _ in range(iters):
        c = corr(r)
        for j in topk_abs(c, group, set(T)):
            T.append(j)
        T = topk_abs([xhat[i] if i in T else (c[i] if i in T else 0.0) for i in range(N)], min(len(T), K)) if len(T) > K else T
        xhat = least_squares(T, y)
        r = residual(y, xhat)
    return hard_threshold(xhat, K)

def cosamp(iters=K):
    xhat = [0.0] * N
    T = set()
    for _ in range(iters):
        r = residual(y, xhat)
        c = corr(r)
        Omega = set(topk_abs(c, 2*K))
        U = list(T | Omega)
        b = least_squares(U, y)
        xhat = hard_threshold(b, K)
        T = support(xhat)
    return xhat

def sp(iters=K):
    c = corr(y)
    T = set(topk_abs(c, K))
    xhat = least_squares(T, y)
    for _ in range(iters):
        r = residual(y, xhat)
        c = corr(r)
        U = list(T | set(topk_abs(c, K)))
        b = least_squares(U, y)
        Tnew = set(topk_abs(b, K))
        xnew = least_squares(Tnew, y)
        if norm2(residual(y, xnew)) > norm2(residual(y, xhat)):
            break
        T, xhat = Tnew, xnew
    return xhat

def iht(iters=K*2, mu=0.9):
    xhat = [0.0] * N
    for _ in range(iters):
        r = residual(y, xhat)
        c = corr(r)
        xhat = hard_threshold([xhat[i] + mu * c[i] for i in range(N)], K)
    return xhat

def htp(iters=K*4, mu=0.9):
    xhat = [0.0] * N
    for _ in range(iters):
        r = residual(y, xhat)
        c = corr(r)
        T = topk_abs([xhat[i] + mu * c[i] for i in range(N)], K)
        xhat = least_squares(T, y)
    return xhat

def gp(iters=K*2, mu=0.75):
    xhat = [0.0] * N
    T = set()
    for _ in range(iters):
        r = residual(y, xhat)
        c = corr(r)
        z = [xhat[i] + mu * c[i] for i in range(N)]
        T = set(topk_abs(z, K))
        # projected gradient without LS refine, intentionally different from HTP
        xhat = [z[i] if i in T else 0.0 for i in range(N)]
    return xhat

def mp(iters=K*4):
    xhat = [0.0] * N
    r = y[:]
    for _ in range(iters):
        c = corr(r)
        j = max(range(N), key=lambda i: abs(c[i]))
        xhat[j] += c[j]
        r = residual(y, xhat)
    return hard_threshold(xhat, K*3)

results = {
    'OMP': omp(),
    'GOMP': gomp(),
    'CoSaMP': cosamp(),
    'SP': sp(),
    'IHT': iht(),
    'HTP': htp(),
    'GP': gp(),
    'MP': mp(),
}
order = ['Original','OMP','GOMP','CoSaMP','SP','IHT','HTP','GP','MP']

def mse(a,b): return sum((ai-bi)**2 for ai,bi in zip(a,b))/len(a)
def snr(a,b):
    sig=sum(ai*ai for ai in a); err=sum((ai-bi)**2 for ai,bi in zip(a,b))
    return 99.0 if err == 0 else 10*math.log10(sig/err)
def overlap(v): return len(true_support & set(topk_abs(v, K)))
rows=[]
for name, rec in results.items():
    rows.append({'Algorithm':name,'MSE':mse(x,rec),'SNR_dB':snr(x,rec),'SupportOverlap':overlap(rec),'NNZ':len(support(rec))})
with (OUT/'algorithmic_worm_8alg_metrics.csv').open('w', newline='') as f:
    w=csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
with (OUT/'algorithmic_worm_8alg_vectors.csv').open('w', newline='') as f:
    w=csv.writer(f); w.writerow(['index','Original']+list(results.keys()))
    for i in range(N): w.writerow([i,x[i]]+[results[k][i] for k in results])
# Render clean PNG content (labels added by PowerShell)
WIDTH,HEIGHT=660,650; panel=150; gapx=60; gapy=55; mx=35; sy=55
vecs={'Original':x}; vecs.update(results)
maxv=max(max(abs(v) for v in vec) for vec in vecs.values()) or 1
pix=bytearray([255,255,255]*WIDTH*HEIGHT)
def setp(px,py,c):
    if 0<=px<WIDTH and 0<=py<HEIGHT:
        off=(py*WIDTH+px)*3; pix[off:off+3]=bytes([c,c,c])
def value_at(vec, px, py, width=150, height=150):
    gx=px/(width-1)*(W-1); gy=py/(height-1)*(H-1); total=0.0; sigma2=0.72
    for yy in range(H):
        for xx in range(W):
            val=abs(vec[yy*W+xx])/maxv
            if val>1e-9:
                d2=(gx-xx)**2+(gy-yy)**2; total += val*math.exp(-d2/(2*sigma2))
    return max(0,min(1,total))
def draw_panel(vec,x0,y0):
    for py in range(panel):
        for px in range(panel):
            shade=int(255-232*value_at(vec,px,py)); setp(x0+px,y0+py,shade)
    for px in range(panel): setp(x0+px,y0,222); setp(x0+px,y0+panel-1,222)
    for py in range(panel): setp(x0,y0+py,222); setp(x0+panel-1,y0+py,222)
for idx,name in enumerate(order):
    row=idx//3; col=idx%3; draw_panel(vecs[name], mx+col*(panel+gapx), sy+row*(panel+gapy))
def chunk(tag,data): return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
raw=bytearray()
for yy in range(HEIGHT): raw.append(0); raw.extend(pix[yy*WIDTH*3:(yy+1)*WIDTH*3])
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',WIDTH,HEIGHT,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(raw),9))+chunk(b'IEND',b'')
(OUT/'algorithmic_worm_8alg_notext.png').write_bytes(png)
# SVG
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="660" height="650" viewBox="0 0 660 650"><rect width="100%" height="100%" fill="white"/>']
for idx,name in enumerate(order):
    row=idx//3; col=idx%3; x0=mx+col*(panel+gapx); y0=sy+row*(panel+gapy)
    svg.append(f'<text x="{x0+panel/2:.0f}" y="{y0-14}" text-anchor="middle" font-family="Arial" font-size="14">{name}</text>')
    for py in range(0,panel,3):
        for px in range(0,panel,3):
            shade=int(255-232*value_at(vecs[name],px+1.5,py+1.5)); svg.append(f'<rect x="{x0+px}" y="{y0+py}" width="3" height="3" fill="rgb({shade},{shade},{shade})"/>')
    svg.append(f'<rect x="{x0}" y="{y0}" width="{panel}" height="{panel}" fill="none" stroke="#dddddd"/>')
svg.append('</svg>')
(OUT/'algorithmic_worm_8alg.svg').write_text('\n'.join(svg))
print('Algorithmic CS results, seed', SEED)
for r in rows:
    print(f"{r['Algorithm']:6s} MSE={r['MSE']:.3e} SNR={r['SNR_dB']:.2f} overlap={r['SupportOverlap']}/{K} nnz={r['NNZ']}")
print(OUT/'algorithmic_worm_8alg_notext.png')
print(OUT/'algorithmic_worm_8alg.svg')
