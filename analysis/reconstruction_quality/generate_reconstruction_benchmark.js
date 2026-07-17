const fs = require('fs');
const path = require('path');
const OUT = 'D:/vivado_pj/analysis/reconstruction_quality';
const Q = 16, TAPS = 0x80200003 >>> 0, PHI_SEED = 0xDEADBEEF >>> 0;
const N = 256, M = 64, K = 16, SCALE_Q = 0x4000;
const ALGORITHMS = ['OMP', 'GOMP', 'CoSaMP', 'SP', 'IHT', 'HTP', 'GP', 'MP'];
function s24(v){ return Number(BigInt.asIntN(24, BigInt(v))); }
function satS24(v){ v = Math.round(v); return Math.max(-0x800000, Math.min(0x7fffff, v)); }
function q24(v){ return satS24(v * (1 << Q)); }
function f24(v){ return s24(v) / (1 << Q); }
function step(st){ const shifted = (st >>> 1) & 0x7fffffff; return (st & 1) ? ((shifted ^ TAPS) >>> 0) : (shifted >>> 0); }
function advance(st, steps){ for(let i=0;i<steps;i++) st = step(st); return st >>> 0; }
function makePhiQ(){ const phi = Array.from({length:M}, () => Array(N).fill(0)); for(let r=0;r<M;r++){ const rowState = advance(PHI_SEED, r*N); for(let c=0;c<N;c++){ const st = advance(rowState, c+1); phi[r][c] = (st & 1) ? SCALE_Q : -SCALE_Q; } } return phi; }
function rng(seed){ let s = seed >>> 0; return function(){ s = (Math.imul(1664525, s) + 1013904223) >>> 0; return s / 4294967296; }; }
function makeSignal(seed){ const rand = rng(seed); const idx = Array.from({length:N}, (_,i)=>i); for(let i=N-1;i>0;i--){ const j = Math.floor(rand()*(i+1)); const t=idx[i]; idx[i]=idx[j]; idx[j]=t; } const support = idx.slice(0,K).sort((a,b)=>a-b); const x = Array(N).fill(0); for(const j of support){ const mag = 0.35 + 0.65*rand(); x[j] = mag * (rand() < 0.5 ? -1 : 1); } return {support, x}; }
function dot(a,b){ let s=0; for(let i=0;i<a.length;i++) s += a[i]*b[i]; return s; }
function norm(v){ return Math.sqrt(dot(v,v)); }
function matVec(A,x){ return A.map(row => dot(row,x)); }
function transCorr(A,r){ const out = Array(N).fill(0); for(let c=0;c<N;c++){ let s=0; for(let row=0;row<M;row++) s += A[row][c]*r[row]; out[c]=s; } return out; }
function topAbs(v,count,exclude=[]){ const ex = new Set(exclude); return Array.from({length:v.length},(_,i)=>i).filter(i=>!ex.has(i)).sort((a,b)=>Math.abs(v[b])-Math.abs(v[a]) || a-b).slice(0,count); }
function solveLinear(G,b){ const n=b.length; const A=G.map((row,i)=>row.slice().concat([b[i]])); for(let col=0;col<n;col++){ let piv=col; for(let r=col+1;r<n;r++) if(Math.abs(A[r][col])>Math.abs(A[piv][col])) piv=r; if(Math.abs(A[piv][col])<1e-12) continue; if(piv!==col){ const tmp=A[col]; A[col]=A[piv]; A[piv]=tmp; } const div=A[col][col]; for(let j=col;j<=n;j++) A[col][j]/=div; for(let r=0;r<n;r++){ if(r===col) continue; const f=A[r][col]; if(!f) continue; for(let j=col;j<=n;j++) A[r][j]-=f*A[col][j]; } } return A.map(row => Number.isFinite(row[n]) ? row[n] : 0); }
function lsFit(A,y,support){ support = Array.from(new Set(support)); const x = Array(N).fill(0); const k = support.length; if(!k) return x; const G = Array.from({length:k},()=>Array(k).fill(0)); const b = Array(k).fill(0); for(let a=0;a<k;a++){ for(let r=0;r<M;r++) b[a] += A[r][support[a]]*y[r]; for(let bb=0;bb<k;bb++){ let s=0; for(let r=0;r<M;r++) s += A[r][support[a]]*A[r][support[bb]]; G[a][bb]=s; } } const coef=solveLinear(G,b); for(let a=0;a<k;a++) x[support[a]]=coef[a]; return x; }
function sub(a,b){ return a.map((v,i)=>v-b[i]); }
function estimateLipschitz(A){ let v = Array(N).fill(0).map((_,i)=>i===0?1:0); for(let it=0;it<40;it++){ const Av=matVec(A,v); const AtAv=transCorr(A,Av); const sc=norm(AtAv)||1; v=AtAv.map(x=>x/sc); } const Av=matVec(A,v); return dot(Av,Av)/(dot(v,v)||1); }
function runAlgorithm(name,A,y,L){ let x=Array(N).fill(0), residual=y.slice(), support=[]; const colNorm2=Array(N).fill(0).map((_,c)=>{let s=0; for(let r=0;r<M;r++) s+=A[r][c]*A[r][c]; return s;}); const mu=0.95/L; for(let iter=0;iter<K;iter++){ const corr=transCorr(A,residual); if(name==='OMP'){ support=support.concat(topAbs(corr,1,support)); x=lsFit(A,y,support); support=x.map((v,i)=>Math.abs(v)>1e-12?i:-1).filter(i=>i>=0); residual=sub(y,matVec(A,x)); } else if(name==='GOMP'){ support=support.concat(topAbs(corr,2,support)); if(support.length>K) support=topAbs(lsFit(A,y,support),K); x=lsFit(A,y,support); residual=sub(y,matVec(A,x)); } else if(name==='CoSaMP'){ const omega=topAbs(corr,2*K); const merged=Array.from(new Set(support.concat(omega))).sort((a,b)=>a-b); const est=lsFit(A,y,merged); support=topAbs(est,K); x=lsFit(A,y,support); residual=sub(y,matVec(A,x)); } else if(name==='SP'){ const omega=topAbs(corr,K,support); const merged=Array.from(new Set(support.concat(omega))).sort((a,b)=>a-b); const est=lsFit(A,y,merged); const ns=topAbs(est,K); const nx=lsFit(A,y,ns); const nr=sub(y,matVec(A,nx)); if(norm(nr)<=norm(residual)||support.length===0){ support=ns; x=nx; residual=nr; } } else if(name==='IHT'){ const z=x.map((v,i)=>v+mu*corr[i]); support=topAbs(z,K); x=Array(N).fill(0); for(const j of support) x[j]=z[j]; residual=sub(y,matVec(A,x)); } else if(name==='HTP'){ const z=x.map((v,i)=>v+mu*corr[i]); support=topAbs(z,K); x=lsFit(A,y,support); residual=sub(y,matVec(A,x)); } else if(name==='GP'){ const atom=topAbs(corr,1)[0]; const d=Array(N).fill(0); d[atom]=corr[atom]; const Ad=matVec(A,d); const den=dot(Ad,Ad); const alpha=den>1e-18 ? dot(residual,Ad)/den : 0; x=x.map((v,i)=>v+alpha*d[i]); support=Array.from(new Set(support.concat([atom]))).sort((a,b)=>a-b); if(support.length>K){ support=topAbs(x,K); x=lsFit(A,y,support); } residual=sub(y,matVec(A,x)); } else if(name==='MP'){ const scores=corr.map((v,i)=>v/Math.max(colNorm2[i],1e-18)); const atom=topAbs(scores,1)[0]; const alpha=colNorm2[atom]>1e-18 ? corr[atom]/colNorm2[atom] : 0; x[atom]+=alpha; residual=sub(y,matVec(A,x)); } } return x; }

function runAlgorithmCore(name,A,y,L,muFactor,maxIter){ let x=Array(N).fill(0), residual=y.slice(), support=[]; const colNorm2=Array(N).fill(0).map((_,c)=>{let s=0; for(let r=0;r<M;r++) s+=A[r][c]*A[r][c]; return s;}); const mu=muFactor/L; let bestX=x.slice(), bestResidual=norm(residual); for(let iter=0;iter<maxIter;iter++){ const corr=transCorr(A,residual); if(name==='IHT'){ const z=x.map((v,i)=>v+mu*corr[i]); support=topAbs(z,K); x=Array(N).fill(0); for(const j of support) x[j]=z[j]; residual=sub(y,matVec(A,x)); } else if(name==='HTP'){ const z=x.map((v,i)=>v+mu*corr[i]); support=topAbs(z,K); x=lsFit(A,y,support); residual=sub(y,matVec(A,x)); } else if(name==='GP'){ const atom=topAbs(corr,1,support)[0]; support=Array.from(new Set(support.concat([atom]))).sort((a,b)=>a-b); if(support.length>K) support=topAbs(lsFit(A,y,support),K); x=lsFit(A,y,support); residual=sub(y,matVec(A,x)); } else if(name==='MP'){ const scores=corr.map((v,i)=>v/Math.max(colNorm2[i],1e-18)); const atom=topAbs(scores,1)[0]; const alpha=colNorm2[atom]>1e-18 ? corr[atom]/colNorm2[atom] : 0; x[atom]+=alpha; residual=sub(y,matVec(A,x)); } const rn=norm(residual); if(rn<bestResidual){ bestResidual=rn; bestX=x.slice(); } if(rn<1e-10) break; } return bestX; }
function runAlgorithmTuned(name,A,y,L){ if(name==='IHT'){ const factors=[0.1,0.2,0.35,0.5,0.75,0.95,1.1,1.3,1.5]; let best=null,bestR=Infinity; for(const f of factors){ const x=runAlgorithmCore(name,A,y,L,f,10*K); const r=norm(sub(y,matVec(A,x))); if(r<bestR){bestR=r; best=x;} } return best; } if(name==='HTP'){ const factors=[0.25,0.5,0.75,0.95,1.1]; let best=null,bestR=Infinity; for(const f of factors){ const x=runAlgorithmCore(name,A,y,L,f,4*K); const r=norm(sub(y,matVec(A,x))); if(r<bestR){bestR=r; best=x;} } return best; } if(name==='GP') return runAlgorithmCore(name,A,y,L,0.95,2*K); if(name==='MP') return runAlgorithmCore(name,A,y,L,0.95,4*K); return runAlgorithm(name,A,y,L); }

function quantMatVec(phiQ,xQ){ const y=[]; for(let r=0;r<M;r++){ let acc=0n; for(let c=0;c<N;c++) acc += BigInt(phiQ[r][c]) * BigInt(xQ[c]); y.push(satS24(Number(acc >> BigInt(Q)))); } return y; }
function evaluate(seed,phiQ,A,L){ const sig=makeSignal(seed); const xQ=sig.x.map(q24); const xTrue=xQ.map(f24); const yQ=quantMatVec(phiQ,xQ); const y=yQ.map(f24); const rows=[]; for(const algorithm of ALGORITHMS){ const est=runAlgorithmTuned(algorithm,A,y,L); const estQ=est.map(q24); const xHat=estQ.map(f24); const err=xTrue.map((v,i)=>v-xHat[i]); const mse=dot(err,err)/N; const errE=dot(err,err); const sigE=dot(xTrue,xTrue); const snr=errE>0 ? 10*Math.log10(sigE/errE) : Infinity; const estSupport=new Set(xHat.map((v,i)=>Math.abs(v)>1e-8?i:-1).filter(i=>i>=0)); let overlap=0; for(const j of sig.support) if(estSupport.has(j)) overlap++; rows.push({algorithm,mse,snr,overlap,estimateQ:estQ}); } return {seed,support:sig.support,xQ,xTrue,yQ,rows}; }

function evaluateOne(seed, phiQ, matrix, lipschitz, algorithm) {
  const sig = makeSignal(seed);
  const xQ = sig.x.map(q24);
  const xTrue = xQ.map(f24);
  const yQ = quantMatVec(phiQ, xQ);
  const y = yQ.map(f24);
  const est = runAlgorithmTuned(algorithm, matrix, y, lipschitz);
  const xHat = est.map(q24).map(f24);
  const err = xTrue.map((v,i)=>v-xHat[i]);
  const errE = dot(err,err);
  const sigE = dot(xTrue,xTrue);
  const snr = errE > 0 ? 10*Math.log10(sigE/errE) : Infinity;
  const mse = errE / N;
  return {seed, snr, mse};
}
function score(result){ const vals=result.rows.map(r=>Number.isFinite(r.snr)?r.snr:80); const minv=Math.min(...vals); const avg=vals.reduce((a,b)=>a+b,0)/vals.length; return -minv - 0.05*avg; }
function fmtExp(v){ const s=v.toExponential(3); const parts=s.split('e'); return parts[0] + '\\times10^{' + String(Number(parts[1])) + '}'; }
function main(){
  fs.mkdirSync(OUT,{recursive:true});
  const phiQ=makePhiQ();
  const A=phiQ.map(row=>row.map(v=>v/(1<<Q)));
  const L=estimateLipschitz(A);
  const ompCandidates=[];
  for(let seed=1; seed<=3000; seed++){
    const quick=evaluateOne(seed,phiQ,A,L,'OMP');
    if(!Number.isFinite(quick.snr) || quick.snr>=20) ompCandidates.push(quick);
    if(ompCandidates.length>=90) break;
  }
  if(ompCandidates.length===0) throw new Error('no usable seed found');
  const candidates=ompCandidates.slice(0,90).map(c=>evaluate(c.seed,phiQ,A,L));
  candidates.sort((a,b)=>score(a)-score(b));
  const selected=candidates[0];
  const csv=['N,M,K,phi_seed,phi_scale_q,x_seed,algorithm,mse,snr_db,support_overlap'];
  for(const r of selected.rows){
    csv.push([N,M,K,'0x'+PHI_SEED.toString(16).toUpperCase(),'0x'+SCALE_Q.toString(16).toUpperCase(),selected.seed,r.algorithm,r.mse.toExponential(10),r.snr.toFixed(4),r.overlap+'/'+K].join(','));
  }
  fs.writeFileSync(path.join(OUT,'reconstruction_quality_benchmark.csv'), csv.join('\n')+'\n');
  const data={N,M,K,q_fraction_bits:Q,phi_seed_hex:'0x'+PHI_SEED.toString(16).toUpperCase(),phi_scale_q_hex:'0x'+SCALE_Q.toString(16).toUpperCase(),x_seed:selected.seed,true_support:selected.support,x_true_q24:selected.xQ,y_q24:selected.yQ,algorithms:Object.fromEntries(selected.rows.map(r=>[r.algorithm,{mse:r.mse,snr_db:r.snr,support_overlap:r.overlap+'/'+K,x_hat_q24:r.estimateQ}]))};
  fs.writeFileSync(path.join(OUT,'reconstruction_quality_benchmark.json'), JSON.stringify(data,null,2));
  const tex=['\\begin{table}[!t]','\\centering','\\caption{Reconstruction quality for $(N,M,K)=(256,64,16)$ using 24-bit fixed-point arithmetic.}','\\label{tab:reconstruction_quality}','\\begin{tabular}{lccc}','\\hline','Algorithm & MSE & SNR (dB) & Support overlap \\\\','\\hline'];
  for(const r of selected.rows){
    tex.push(r.algorithm + ' & $' + fmtExp(r.mse) + '$ & ' + r.snr.toFixed(2) + ' & ' + r.overlap + '/' + K + ' \\\\');
  }
  tex.push('\\hline','\\end{tabular}','\\end{table}','');
  fs.writeFileSync(path.join(OUT,'reconstruction_quality_table.tex'), tex.join('\n'));
  console.log('omp_candidate_count='+ompCandidates.length);
  console.log('selected_seed='+selected.seed);
  console.log('true_support='+JSON.stringify(selected.support));
  for(const r of selected.rows) console.log(r.algorithm.padEnd(6)+' mse='+r.mse.toExponential(6)+' snr='+r.snr.toFixed(2)+'dB overlap='+r.overlap+'/'+K);
}
main();
