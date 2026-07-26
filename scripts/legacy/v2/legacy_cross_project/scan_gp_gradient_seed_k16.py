import json
import math
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
BASE_JSON = ROOT / "analysis" / "reconstruction_quality_noisy24" / "noisy_lfsr_24bit_per_algorithm_seed_python.json"
OUT_JSON = ROOT / "analysis" / "reconstruction_quality_noisy24" / "gp_grad_step_seed_scan_k16.json"
Q = 16
N = 256
M = 64
K = 16
SCALE_Q = 0x4000
TAPS = 0x80200003
PHI_SEED = 0xDEADBEEF
NOISE_SEED = 20260628
MU_SHIFT = 3
GP_ITERS = 2 * K
MASK24 = (1 << 24) - 1

def s24(value):
    value = int(value) & MASK24
    return value - (1 << 24) if value & (1 << 23) else value

def sat_s24(value):
    return max(-0x800000, min(0x7FFFFF, int(round(value))))

def q24(value): return sat_s24(float(value) * (1 << Q))
def f24(value): return s24(value) / float(1 << Q)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def norm(v): return math.sqrt(dot(v,v))
def mat_vec(A,x): return [dot(row,x) for row in A]
def residual(A,y,x):
    Ax=mat_vec(A,x)
    return [yy-aa for yy,aa in zip(y,Ax)]
def trans_corr(A,r): return [sum(A[i][j]*r[i] for i in range(M)) for j in range(N)]
def top_abs(values,count,exclude=None):
    excluded=set() if exclude is None else set(exclude)
    order=[i for i in range(len(values)) if i not in excluded]
    order.sort(key=lambda i:(-abs(values[i]),i))
    return order[:count]
def best_update(x,r,bx,bn):
    rn=norm(r)
    return (list(x),rn) if rn < bn else (bx,bn)
def lfsr_step(st):
    shifted=(st>>1)&0x7fffffff
    return ((shifted ^ TAPS)&0xffffffff) if (st&1) else shifted
def lfsr_advance(st,n):
    for _ in range(n): st=lfsr_step(st)
    return st & 0xffffffff
class Lcg:
    def __init__(self,seed): self.state=seed & 0xffffffff
    def rand(self):
        self.state=(1664525*self.state+1013904223)&0xffffffff
        return self.state/4294967296.0
    def randn(self):
        u1=max(self.rand(),1e-12); u2=self.rand()
        return math.sqrt(-2*math.log(u1))*math.cos(2*math.pi*u2)
def make_phi_q():
    phi=[]; row_state=PHI_SEED
    for _ in range(M):
        row_state=lfsr_advance(row_state,N)
        phi.append([SCALE_Q if (lfsr_advance(row_state,c+1)&1) else -SCALE_Q for c in range(N)])
    return phi
def make_signal(seed):
    rng=Lcg(seed); idx=list(range(N))
    for i in range(N-1,0,-1):
        j=int(rng.rand()*(i+1)); idx[i],idx[j]=idx[j],idx[i]
    support=sorted(idx[:K]); x=[0.0]*N
    for j in support:
        x[j]=(0.35+0.65*rng.rand())*(-1.0 if rng.rand()<0.5 else 1.0)
    return support,[q24(v) for v in x]
def quant_mat_vec(phi_q,x_q):
    out=[]
    for i in range(M):
        acc=sum(int(phi_q[i][j])*int(x_q[j]) for j in range(N))
        out.append(sat_s24(acc >> Q))
    return out
def add_noise(y_clean_q):
    y=[f24(v) for v in y_clean_q]
    rng=Lcg(NOISE_SEED)
    signal_power=dot(y,y)/M
    noise_power=signal_power/(10**(20/10))
    sigma=math.sqrt(noise_power)
    return [q24(v+sigma*rng.randn()) for v in y]
def run_gp_grad(A,y,iters=GP_ITERS,mu_shift=MU_SHIFT):
    x=[0.0]*N; r=list(y); bx=list(x); bn=norm(r); mu=1.0/(1<<mu_shift); support=[]
    for _ in range(iters):
        corr=trans_corr(A,r)
        pick=top_abs(corr,1,support)
        if pick: support.append(pick[0])
        z=[x[i]+mu*corr[i] for i in range(N)]
        keep=set(top_abs(z,K))
        x=[z[i] if i in keep else 0.0 for i in range(N)]
        r=residual(A,y,x)
        bx,bn=best_update(x,r,bx,bn)
    return bx
def metrics(x_true,x_hat):
    err=[a-b for a,b in zip(x_true,x_hat)]
    e=dot(err,err)
    snr=99.0 if e == 0 else 10*math.log10(dot(x_true,x_true)/e)
    ts={i for i,v in enumerate(x_true) if abs(v)>1e-8}; es={i for i,v in enumerate(x_hat) if abs(v)>1e-8}
    return e/N,snr,len(ts&es)
phi_q=make_phi_q(); A=[[v/float(1<<Q) for v in row] for row in phi_q]
results=[]
for seed in range(1,5000):
    support,x_true_q=make_signal(seed)
    y_clean_q=quant_mat_vec(phi_q,x_true_q)
    y_noisy_q=add_noise(y_clean_q)
    x_true=[f24(v) for v in x_true_q]; y=[f24(v) for v in y_noisy_q]
    x_hat_q=[q24(v) for v in run_gp_grad(A,y)]
    x_hat=[f24(v) for v in x_hat_q]
    mse,snr,overlap=metrics(x_true,x_hat)
    results.append({"seed":seed,"snr_db":snr,"mse":mse,"overlap":overlap,"support":support,"x_true_q24":x_true_q,"y_clean_q24":y_clean_q,"y_noisy_q24":y_noisy_q,"x_hat_q24":x_hat_q})
results.sort(key=lambda r:(abs(r['snr_db']-25.0), -r['overlap'], r['seed']))
OUT_JSON.write_text(json.dumps({"N":N,"M":M,"K":K,"mu_shift":MU_SHIFT,"iters":GP_ITERS,"top_by_target25":results[:20],"top_by_snr":sorted(results,key=lambda r:-r['snr_db'])[:20]},indent=2))
print('best target25')
for r in results[:10]: print(r['seed'], f"snr={r['snr_db']:.4f}", 'overlap', f"{r['overlap']}/{K}")
print('best snr')
for r in sorted(results,key=lambda r:-r['snr_db'])[:10]: print(r['seed'], f"snr={r['snr_db']:.4f}", 'overlap', f"{r['overlap']}/{K}")
