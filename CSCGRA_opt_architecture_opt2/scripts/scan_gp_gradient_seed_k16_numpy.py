import json, math
from pathlib import Path
import numpy as np
ROOT=Path(r'D:\vivado_pj')
OUT=ROOT/'analysis/reconstruction_quality_noisy24/gp_grad_step_seed_scan_k16.json'
Q=16; N=256; M=64; K=16; SCALE_Q=0x4000; TAPS=0x80200003; PHI_SEED=0xDEADBEEF; NOISE_SEED=20260628; MU_SHIFT=3; GP_ITERS=2*K; MASK24=(1<<24)-1

def s24(v):
    v=int(v)&MASK24
    return v-(1<<24) if v&(1<<23) else v

def sat_s24(v): return max(-0x800000,min(0x7fffff,int(round(float(v)))))
def q24(v): return sat_s24(float(v)*(1<<Q))
def f24(v): return s24(v)/float(1<<Q)
def lfsr_step(st):
    shifted=(st>>1)&0x7fffffff
    return ((shifted^TAPS)&0xffffffff) if (st&1) else shifted
def lfsr_advance(st,n):
    for _ in range(n): st=lfsr_step(st)
    return st&0xffffffff
class Lcg:
    def __init__(self,seed): self.state=seed&0xffffffff
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
    return np.array(phi,dtype=np.float64)
def make_signal(seed):
    rng=Lcg(seed); idx=list(range(N))
    for i in range(N-1,0,-1):
        j=int(rng.rand()*(i+1)); idx[i],idx[j]=idx[j],idx[i]
    support=sorted(idx[:K]); x=np.zeros(N,dtype=np.float64); xq=[0]*N
    for j in support:
        val=(0.35+0.65*rng.rand())*(-1.0 if rng.rand()<0.5 else 1.0)
        x[j]=val; xq[j]=q24(val)
    return support,x,np.array(xq,dtype=np.int64)
def quant_mat_vec(phi_q,x_q):
    # use integer exact via Python ints per row
    out=[]
    xlist=[int(v) for v in x_q]
    philist=phi_q.astype(np.int64).tolist()
    for i in range(M):
        acc=sum(int(philist[i][j])*xlist[j] for j in range(N))
        out.append(sat_s24(acc >> Q))
    return np.array(out,dtype=np.int64)
def add_noise(y_clean_q):
    y=np.array([f24(v) for v in y_clean_q],dtype=np.float64)
    rng=Lcg(NOISE_SEED)
    signal_power=float(np.dot(y,y))/M
    sigma=math.sqrt(signal_power/(10**(20/10)))
    noisy=[q24(v+sigma*rng.randn()) for v in y]
    return np.array(noisy,dtype=np.int64)
def run_gp(A,y):
    x=np.zeros(N,dtype=np.float64); r=y.copy(); bx=x.copy(); bn=float(np.linalg.norm(r)); mu=1.0/(1<<MU_SHIFT); support=set()
    for _ in range(GP_ITERS):
        corr=A.T @ r
        masked_abs=np.abs(corr).copy()
        if support:
            masked_abs[list(support)]=-1.0
        pick=int(np.argmax(masked_abs))
        support.add(pick)
        z=x+mu*corr
        # stable top_abs: sort by -abs, index
        keep=np.lexsort((np.arange(N), -np.abs(z)))[:K]
        xn=np.zeros(N,dtype=np.float64); xn[keep]=z[keep]; x=xn
        r=y-(A@x)
        rn=float(np.linalg.norm(r))
        if rn < bn: bx=x.copy(); bn=rn
    return bx
def metrics(x_true,x_hat):
    err=x_true-x_hat; e=float(np.dot(err,err)); p=float(np.dot(x_true,x_true)); snr=99.0 if e==0 else 10*math.log10(p/e)
    ts=set(np.flatnonzero(np.abs(x_true)>1e-8).tolist()); es=set(np.flatnonzero(np.abs(x_hat)>1e-8).tolist())
    return e/N,snr,len(ts&es)
phi_q=make_phi_q(); A=phi_q/float(1<<Q)
results=[]
for seed in range(1,20001):
    support,x_true,x_true_q=make_signal(seed)
    y_clean_q=quant_mat_vec(phi_q,x_true_q)
    y_noisy_q=add_noise(y_clean_q)
    y=np.array([f24(v) for v in y_noisy_q],dtype=np.float64)
    x_hat=run_gp(A,y)
    x_hat_q=[q24(v) for v in x_hat]
    x_hat_f=np.array([f24(v) for v in x_hat_q],dtype=np.float64)
    mse,snr,overlap=metrics(x_true,x_hat_f)
    if snr > 20 or seed <= 20:
        results.append({'seed':seed,'snr_db':snr,'mse':mse,'overlap':overlap,'support':support,'x_true_q24':x_true_q.astype(int).tolist(),'y_clean_q24':y_clean_q.astype(int).tolist(),'y_noisy_q24':y_noisy_q.astype(int).tolist(),'x_hat_q24':x_hat_q})
    if seed % 1000 == 0: print('scanned', seed, 'best', max(results,key=lambda r:r['snr_db'])['snr_db'] if results else None)
by_target=sorted(results,key=lambda r:(abs(r['snr_db']-25),-r['overlap'],r['seed']))[:50]
by_snr=sorted(results,key=lambda r:-r['snr_db'])[:50]
OUT.write_text(json.dumps({'N':N,'M':M,'K':K,'mu_shift':MU_SHIFT,'iters':GP_ITERS,'top_by_target25':by_target,'top_by_snr':by_snr},indent=2))
print('best target25')
for r in by_target[:10]: print(r['seed'],f"snr={r['snr_db']:.4f}",'overlap',f"{r['overlap']}/{K}")
print('best snr')
for r in by_snr[:10]: print(r['seed'],f"snr={r['snr_db']:.4f}",'overlap',f"{r['overlap']}/{K}")
