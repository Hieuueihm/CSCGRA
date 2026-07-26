import json, math
from pathlib import Path
import numpy as np
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
 phi=[]; row_state=PHI_SEED
 for _ in range(M):
  row_state=lfsr_advance(row_state,N); phi.append([SCALE_Q if (lfsr_advance(row_state,c+1)&1) else -SCALE_Q for c in range(N)])
 return np.array(phi,dtype=np.float64)
def make_signal(seed):
 rng=Lcg(seed); idx=list(range(N))
 for i in range(N-1,0,-1):
  j=int(rng.rand()*(i+1)); idx[i],idx[j]=idx[j],idx[i]
 support=sorted(idx[:K]); x=np.zeros(N); xq=[0]*N
 for j in support:
  val=(0.35+0.65*rng.rand())*(-1.0 if rng.rand()<0.5 else 1.0); x[j]=val; xq[j]=q24(val)
 return support,x,np.array(xq,dtype=np.int64)
def quant_mat_vec(phi_q,x_q):
 out=[]; phil=phi_q.astype(np.int64).tolist(); xl=[int(v) for v in x_q]
 for i in range(M): out.append(sat_s24(sum(phil[i][j]*xl[j] for j in range(N)) >> Q))
 return np.array(out,dtype=np.int64)
def add_noise(y_clean_q):
 y=np.array([f24(v) for v in y_clean_q]); rng=Lcg(NOISE_SEED); sigma=math.sqrt(float(np.dot(y,y))/M/(10**(20/10)))
 return np.array([q24(v+sigma*rng.randn()) for v in y],dtype=np.int64)
def metrics(x_true,x_hat):
 err=x_true-x_hat; e=float(np.dot(err,err)); p=float(np.dot(x_true,x_true)); snr=99 if e==0 else 10*math.log10(p/e); ov=len(set(np.flatnonzero(abs(x_true)>1e-8)) & set(np.flatnonzero(abs(x_hat)>1e-8))); return snr,ov
def run(seed):
 phi=make_phi_q(); A=phi/float(1<<Q); support,x_true,xq=make_signal(seed); yq=add_noise(quant_mat_vec(phi,xq)); y=np.array([f24(v) for v in yq]); x=np.zeros(N); r=y.copy(); bx=x.copy(); bn=float(np.linalg.norm(r)); mu=1/(1<<MU_SHIFT); supp=set()
 for _ in range(GP_ITERS):
  corr=A.T@r; masked=np.abs(corr).copy();
  if supp: masked[list(supp)]=-1
  supp.add(int(np.argmax(masked)))
  z=x+mu*corr; keep=np.lexsort((np.arange(N),-np.abs(z)))[:K]; x=np.zeros(N); x[keep]=z[keep]; r=y-(A@x); rn=float(np.linalg.norm(r))
  if rn<bn: bx=x.copy(); bn=rn
 final_q=[q24(v) for v in x]; best_q=[q24(v) for v in bx]
 xf=np.array([f24(v) for v in final_q]); xb=np.array([f24(v) for v in best_q])
 print('seed',seed,'final',metrics(x_true,xf),'best',metrics(x_true,xb),'diff_count',sum(a!=b for a,b in zip(final_q,best_q)))
 print('final nz',[(i,hex(v & MASK24)) for i,v in enumerate(final_q) if v])
 print('best nz',[(i,hex(v & MASK24)) for i,v in enumerate(best_q) if v])
run(627)
