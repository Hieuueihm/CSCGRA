import math, random, csv, struct, zlib, subprocess
from pathlib import Path

OUT = Path(r'D:/vivado_pj/analysis/paper_algorithmic_worm_8alg')
CROP = OUT / 'original_crop_from_user.png'
W = H = 16
N = 256
M = 64
K = 16
SEED = 211
NOISE_DB = 28.0

# Read PNG crop using PowerShell/.NET once into grayscale CSV-like text via temporary file.
def read_crop_to_grid():
    tmp = OUT / '_crop_grid.txt'
    ps = rf'''
Add-Type -AssemblyName System.Drawing
$bmp=[System.Drawing.Bitmap]::FromFile('{str(CROP)}')
$W=16; $H=16
$lines=@()
for($yy=0;$yy -lt $H;$yy++){{
  $vals=@()
  for($xx=0;$xx -lt $W;$xx++){{
    $x0=[int]($xx*$bmp.Width/$W); $x1=[int](($xx+1)*$bmp.Width/$W)-1
    $y0=[int]($yy*$bmp.Height/$H); $y1=[int](($yy+1)*$bmp.Height/$H)-1
    if($x1 -lt $x0){{$x1=$x0}}; if($y1 -lt $y0){{$y1=$y0}}
    $sum=0.0; $cnt=0
    for($py=$y0;$py -le $y1;$py++){{ for($px=$x0;$px -le $x1;$px++){{ $c=$bmp.GetPixel($px,$py); $gray=($c.R+$c.G+$c.B)/3.0; $sum += (255.0-$gray)/255.0; $cnt++ }} }}
    if($cnt -eq 0){{$cnt=1}}
    $vals += [string]($sum/$cnt)
  }}
  $lines += ($vals -join ',')
}}
$bmp.Dispose()
Set-Content -Path '{str(tmp)}' -Value $lines -Encoding ASCII
'''
    subprocess.run(['powershell','-NoProfile','-Command',ps], check=True)
    rows=[]
    for line in tmp.read_text().splitlines():
        rows.extend([float(x) for x in line.split(',')])
    return rows

raw = read_crop_to_grid()
# Keep the darkest K cells as sparse x, but preserve amplitudes from the actual crop.
idxs = sorted(range(N), key=lambda i: raw[i], reverse=True)[:K]
mx = max(raw[i] for i in idxs) or 1.0
x = [0.0] * N
for i in idxs:
    # contrast stretch so original panel looks like the submitted worm
    x[i] = max(0.15, min(1.0, raw[i] / mx))
true_support = set(idxs)

rng = random.Random(SEED)
Phi = [[rng.gauss(0,1) for _ in range(N)] for _ in range(M)]
for j in range(N):
    norm = math.sqrt(sum(Phi[i][j]*Phi[i][j] for i in range(M))) or 1.0
    for i in range(M): Phi[i][j] /= norm

def matvec(A,v): return [sum(row[j]*v[j] for j in range(len(v))) for row in A]
def residual(y,xh):
    Ax=matvec(Phi,xh); return [yi-ai for yi,ai in zip(y,Ax)]
def corr(r): return [sum(Phi[i][j]*r[i] for i in range(M)) for j in range(N)]
def topk_abs(v,k,exclude=None):
    exclude=exclude or set(); return sorted((i for i in range(len(v)) if i not in exclude), key=lambda i: abs(v[i]), reverse=True)[:k]
def support(v,eps=1e-10): return {i for i,a in enumerate(v) if abs(a)>eps}
def hard(v,k):
    keep=set(topk_abs(v,k)); return [v[i] if i in keep else 0.0 for i in range(N)]
def norm2(v): return math.sqrt(sum(a*a for a in v))
def solve(A,b):
    n=len(b)
    if n==0: return []
    Mx=[A[i][:]+[b[i]] for i in range(n)]
    for c in range(n):
        p=max(range(c,n), key=lambda r: abs(Mx[r][c]))
        Mx[c],Mx[p]=Mx[p],Mx[c]
        pv=Mx[c][c]
        if abs(pv)<1e-10: pv=1e-10
        for j in range(c,n+1): Mx[c][j]/=pv
        for r in range(n):
            if r==c: continue
            f=Mx[r][c]
            if f:
                for j in range(c,n+1): Mx[r][j]-=f*Mx[c][j]
    return [Mx[i][n] for i in range(n)]
def ls(T,y):
    T=list(dict.fromkeys(T)); s=len(T); out=[0.0]*N
    if s==0: return out
    G=[[0.0]*s for _ in range(s)]; rhs=[0.0]*s
    for a,ja in enumerate(T):
        rhs[a]=sum(Phi[i][ja]*y[i] for i in range(M))
        for b,jb in enumerate(T): G[a][b]=sum(Phi[i][ja]*Phi[i][jb] for i in range(M))
        G[a][a]+=1e-8
    z=solve(G,rhs)
    for i,v in zip(T,z): out[i]=v
    return out

def add_noise(y,db):
    rr=random.Random(SEED+99); n=[rr.gauss(0,1) for _ in y]
    scale=(norm2(y)/(10**(db/20)))/(norm2(n) or 1)
    return [a+scale*b for a,b in zip(y,n)]
y=add_noise(matvec(Phi,x),NOISE_DB)

def omp():
    T=[]; xh=[0.0]*N; r=y[:]
    for _ in range(K):
        c=corr(r); j=max((i for i in range(N) if i not in T), key=lambda i: abs(c[i])); T.append(j); xh=ls(T,y); r=residual(y,xh)
    return xh
def gomp(group=2):
    T=[]; xh=[0.0]*N; r=y[:]
    for _ in range((K+group-1)//group):
        c=corr(r)
        for j in topk_abs(c,group,set(T)): T.append(j)
        xh=ls(T,y); r=residual(y,xh)
    return hard(xh,K)
def cosamp():
    xh=[0.0]*N; T=set()
    for _ in range(K):
        c=corr(residual(y,xh)); U=list(T | set(topk_abs(c,2*K))); b=ls(U,y); xh=hard(b,K); T=support(xh)
    return xh
def sp():
    T=set(topk_abs(corr(y),K)); xh=ls(T,y)
    for _ in range(K):
        U=list(T | set(topk_abs(corr(residual(y,xh)),K))); b=ls(U,y); Tn=set(topk_abs(b,K)); xn=ls(Tn,y)
        if norm2(residual(y,xn)) > norm2(residual(y,xh)): break
        T,xh=Tn,xn
    return xh
def iht(mu=0.35):
    xh=[0.0]*N
    for _ in range(4*K): xh=hard([xh[i]+mu*corr(residual(y,xh))[i] for i in range(N)],K)
    return xh
def htp(mu=0.45):
    xh=[0.0]*N
    for _ in range(4*K):
        c=corr(residual(y,xh)); T=topk_abs([xh[i]+mu*c[i] for i in range(N)],K); xh=ls(T,y)
    return xh
def gp(mu=0.30):
    xh=[0.0]*N
    for _ in range(4*K):
        c=corr(residual(y,xh)); z=[xh[i]+mu*c[i] for i in range(N)]; T=set(topk_abs(z,K)); xh=[z[i] if i in T else 0.0 for i in range(N)]
    return xh
def mp():
    xh=[0.0]*N; r=y[:]
    for _ in range(4*K):
        c=corr(r); j=max(range(N), key=lambda i: abs(c[i])); xh[j]+=c[j]; r=residual(y,xh)
    return hard(xh,3*K)
results={'OMP':omp(),'GOMP':gomp(),'CoSaMP':cosamp(),'SP':sp(),'IHT':iht(),'HTP':htp(),'GP':gp(),'MP':mp()}
order=['Original','OMP','GOMP','CoSaMP','SP','IHT','HTP','GP','MP']
def mse(a,b): return sum((u-v)**2 for u,v in zip(a,b))/N
def snr(a,b):
    sig=sum(u*u for u in a); err=sum((u-v)**2 for u,v in zip(a,b)); return 99 if err==0 else 10*math.log10(sig/err)
def overlap(v): return len(true_support & set(topk_abs(v,K)))
rows=[]
for name,rec in results.items(): rows.append({'Algorithm':name,'MSE':mse(x,rec),'SNR_dB':snr(x,rec),'SupportOverlap':overlap(rec),'NNZ':len(support(rec))})
with (OUT/'user_original_algorithmic_8alg_metrics.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
with (OUT/'user_original_algorithmic_8alg_vectors.csv').open('w',newline='') as f:
    w=csv.writer(f); w.writerow(['index','Original']+list(results.keys()))
    for i in range(N): w.writerow([i,x[i]]+[results[k][i] for k in results])
# render
WIDTH,HEIGHT=660,650; panel=150; gapx=60; gapy=55; mx0=35; sy=55
vecs={'Original':x}; vecs.update(results); maxv=max(max(abs(v) for v in vec) for vec in vecs.values()) or 1
pix=bytearray([255,255,255]*WIDTH*HEIGHT)
def setp(px,py,c):
    if 0<=px<WIDTH and 0<=py<HEIGHT:
        off=(py*WIDTH+px)*3; pix[off:off+3]=bytes([c,c,c])
def value_at(vec,px,py,width=150,height=150):
    gx=px/(width-1)*(W-1); gy=py/(height-1)*(H-1); total=0.0; sigma2=0.68
    for yy in range(H):
        for xx in range(W):
            val=abs(vec[yy*W+xx])/maxv
            if val>1e-9:
                d2=(gx-xx)**2+(gy-yy)**2; total+=val*math.exp(-d2/(2*sigma2))
    return max(0,min(1,total))
def draw(vec,x0,y0):
    for py in range(panel):
        for px in range(panel): setp(x0+px,y0+py,int(255-232*value_at(vec,px,py)))
    for px in range(panel): setp(x0+px,y0,222); setp(x0+px,y0+panel-1,222)
    for py in range(panel): setp(x0,y0+py,222); setp(x0+panel-1,y0+py,222)
for idx,name in enumerate(order): draw(vecs[name], mx0+(idx%3)*(panel+gapx), sy+(idx//3)*(panel+gapy))
def chunk(tag,data): return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
rawout=bytearray()
for yy in range(HEIGHT): rawout.append(0); rawout.extend(pix[yy*WIDTH*3:(yy+1)*WIDTH*3])
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',WIDTH,HEIGHT,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(rawout),9))+chunk(b'IEND',b'')
(OUT/'user_original_algorithmic_8alg_notext.png').write_bytes(png)
print('Using Original sampled from', CROP)
for r in rows: print(f"{r['Algorithm']:6s} SNR={r['SNR_dB']:.2f} overlap={r['SupportOverlap']}/{K} nnz={r['NNZ']}")
print(OUT/'user_original_algorithmic_8alg_notext.png')
