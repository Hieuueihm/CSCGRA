import json, math
from pathlib import Path
Q=16; N=256; M=64; K=16; SCALE_Q=0x4000; TAPS=0x80200003; PHI_SEED=0xDEADBEEF; NOISE_SEED=20260628; MU_SHIFT=3; GP_ITERS=32; MASK24=(1<<24)-1

def s24(v):
 v=int(v)&MASK24; return v-(1<<24) if v&(1<<23) else v
def sat_s24(v): return max(-0x800000,min(0x7fffff,int(round(float(v)))))
def q24(v): return sat_s24(float(v)*(1<<Q))
def f24(v): return s24(v)/float(1<<Q)
def lfsr_step(st):
 shifted=(st>>1)&0x7fffffff; return ((shifted^TAPS)&0xffffffff) if (st&1) else shifted
def lfsr_advance(st,n):
 for _ in range(n): st=lfsr_step(st)
 return st&0xffffffff
class Lcg:
 def __init__(self,seed): self.state=seed&0xffffffff
 def rand(self): self.state=(1664525*self.state+1013904223)&0xffffffff; return self.state/4294967296.0
 def randn(self):
  u1=max(self.rand(),1e-12); u2=self.rand(); return math.sqrt(-2*math.log(u1))*math.cos(2*math.pi*u2)
def make_phi_q():
 phi=[]
 for row in range(M):
  row_state=lfsr_advance(PHI_SEED,row*N)
  phi.append([SCALE_Q if (lfsr_advance(row_state,c+1)&1) else s24(-SCALE_Q) for c in range(N)])
 return phi
def make_signal(seed):
 rng=Lcg(seed); idx=list(range(N))
 for i in range(N-1,0,-1):
  j=int(rng.rand()*(i+1)); idx[i],idx[j]=idx[j],idx[i]
 support=sorted(idx[:K]); xq=[0]*N
 for j in support:
  val=(0.35+0.65*rng.rand())*(-1.0 if rng.rand()<0.5 else 1.0); xq[j]=q24(val)
 return support,xq
def quant_mat_vec(phi,xq):
 y=[]
 for i in range(M): y.append(sat_s24(sum(int(phi[i][j])*int(xq[j]) for j in range(N)) >> Q))
 return y
def add_noise(y_clean_q):
 y=[f24(v) for v in y_clean_q]; rng=Lcg(NOISE_SEED); sigma=math.sqrt(sum(v*v for v in y)/M/(10**(20/10)))
 return [q24(v+sigma*rng.randn()) for v in y]
def corr_scores(phi,residual):
 out=[]
 for c in range(N):
  acc=0
  for r in range(M): acc += int(phi[r][c]) * s24(residual[r])
  out.append(sat_s24(acc >> Q))
 return out
def prune_by_abs(x,k):
 return sorted(range(len(x)), key=lambda i:(-abs(s24(x[i])), i))[:k]
def resid_from_x(phi,y,x,support):
 keep=set(support); residual=[]
 for r in range(M):
  acc=0
  for c in keep: acc += int(phi[r][c]) * s24(x[c])
  residual.append(sat_s24(s24(y[r]) - (acc >> Q)))
 return residual
def run_gp_fixed(phi,y):
 x=[0]*N; residual=list(y); support=[]
 for _ in range(GP_ITERS):
  scores=corr_scores(phi,residual)
  x=[sat_s24(s24(x[i]) + (s24(scores[i]) >> MU_SHIFT)) for i in range(N)]
  support=prune_by_abs(x,K); keep=set(support)
  x=[x[i] if i in keep else 0 for i in range(N)]
  residual=resid_from_x(phi,y,x,support)
 return x
def metrics(x_true_q,x_hat_q):
 xt=[f24(v) for v in x_true_q]; xh=[f24(v) for v in x_hat_q]; err=[a-b for a,b in zip(xt,xh)]; e=sum(v*v for v in err); p=sum(v*v for v in xt); snr=99 if e==0 else 10*math.log10(p/e); ov=len({i for i,v in enumerate(xt) if abs(v)>1e-8} & {i for i,v in enumerate(xh) if abs(v)>1e-8}); return e/N,snr,ov
phi=make_phi_q(); results=[]
for seed in range(1,1000):
 support,xq=make_signal(seed); yclean=quant_mat_vec(phi,xq); y=add_noise(yclean); xhat=run_gp_fixed(phi,y); mse,snr,ov=metrics(xq,xhat)
 if snr>20 or seed==627: results.append({'seed':seed,'snr_db':snr,'mse':mse,'overlap':ov,'support':support,'x_true_q24':xq,'y_clean_q24':yclean,'y_noisy_q24':y,'x_hat_q24':xhat})
print('seed627', [r for r in results if r['seed']==627])
by=sorted(results,key=lambda r:(-r['snr_db'],r['seed']))
print('best fixed')
for r in by[:20]: print(r['seed'],f"snr={r['snr_db']:.4f}",f"overlap={r['overlap']}/{K}")
out=Path(r'D:\vivado_pj\analysis\reconstruction_quality_noisy24\gp_grad_step_fixed_seed_scan_k16_lt1000.json')
out.write_text(json.dumps({'N':N,'M':M,'K':K,'mu_shift':MU_SHIFT,'iters':GP_ITERS,'top_by_snr':by[:50],'all_gt20':results},indent=2))

