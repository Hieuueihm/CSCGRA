const fs = require('fs');
const path = require('path');
const OUT = 'D:/vivado_pj/analysis/quantization_study';
fs.mkdirSync(OUT, {recursive:true});

const M=64, N=256, K=16, TRIALS=24;
const BITS=['FP32',12,16,20,24,28,32];
const ALGS=['MP','OMP','GOMP','IHT','GP','SP','CoSaMP','HTP'];
let seed=20260625;
function rnd(){ seed = (1664525*seed + 1013904223) >>> 0; return seed/4294967296; }
function randn(){ const u=Math.max(rnd(),1e-12), v=rnd(); return Math.sqrt(-2*Math.log(u))*Math.cos(2*Math.PI*v); }
function choiceInt(n){ return Math.floor(rnd()*n); }
function quantVal(v,bits){ if(bits==='FP32') return Math.fround(v); const frac=bits-8, scale=2**frac, lo=-(2**(bits-1))/scale, hi=((2**(bits-1))-1)/scale; return Math.max(lo, Math.min(hi, Math.round(v*scale)/scale)); }
function quantVec(a,bits){ const o=new Float64Array(a.length); for(let i=0;i<a.length;i++) o[i]=quantVal(a[i],bits); return o; }
function phiAt(Phi,m,n){ return Phi[m*N+n]; }
function matVec(Phi,x,bits){ const y=new Float64Array(M); for(let m=0;m<M;m++){ let s=0; const off=m*N; for(let n=0;n<N;n++) s += Phi[off+n]*x[n]; y[m]=quantVal(s,bits); } return y; }
function transCorr(Phi,r,bits){ const c=new Float64Array(N); for(let n=0;n<N;n++){ let s=0; for(let m=0;m<M;m++) s += Phi[m*N+n]*r[m]; c[n]=quantVal(s,bits); } return c; }
function residual(y, Phi, x, bits){ const yh=matVec(Phi,x,bits); const r=new Float64Array(M); for(let m=0;m<M;m++) r[m]=quantVal(y[m]-yh[m],bits); return r; }
function topKAbs(v,k,exclude=new Set()){ const arr=[]; for(let i=0;i<v.length;i++) if(!exclude.has(i)) arr.push([Math.abs(v[i]),i]); arr.sort((a,b)=>b[0]-a[0]); return arr.slice(0,k).map(p=>p[1]); }
function norm2(v){ let s=0; for(const x of v) s+=x*x; return Math.sqrt(s); }
function hardThreshold(v,k,bits){ const idx=topKAbs(v,k); const out=new Float64Array(v.length); for(const i of idx) out[i]=quantVal(v[i],bits); return out; }
function spectralNorm2(Phi){ let v=new Float64Array(N); for(let i=0;i<N;i++) v[i]=1/Math.sqrt(N); for(let it=0;it<12;it++){ const u=new Float64Array(M); for(let m=0;m<M;m++){ let s=0; for(let n=0;n<N;n++) s+=Phi[m*N+n]*v[n]; u[m]=s; } const w=new Float64Array(N); for(let n=0;n<N;n++){ let s=0; for(let m=0;m<M;m++) s+=Phi[m*N+n]*u[m]; w[n]=s; } const nw=norm2(w)||1; for(let n=0;n<N;n++) v[n]=w[n]/nw; } const Av=new Float64Array(M); for(let m=0;m<M;m++){ let s=0; for(let n=0;n<N;n++) s+=Phi[m*N+n]*v[n]; Av[m]=s; } const nv=norm2(v)||1; const na=norm2(Av); return (na/nv)*(na/nv); }
function solveLinear(A,b){ const n=b.length; const Mx=A.map((row,i)=>row.concat([b[i]])); for(let i=0;i<n;i++){ let piv=i; for(let r=i+1;r<n;r++) if(Math.abs(Mx[r][i])>Math.abs(Mx[piv][i])) piv=r; if(Math.abs(Mx[piv][i])<1e-12) Mx[piv][i]=1e-12; if(piv!==i){ const tmp=Mx[i]; Mx[i]=Mx[piv]; Mx[piv]=tmp; } const div=Mx[i][i]; for(let c=i;c<=n;c++) Mx[i][c]/=div; for(let r=0;r<n;r++){ if(r===i) continue; const f=Mx[r][i]; if(f===0) continue; for(let c=i;c<=n;c++) Mx[r][c]-=f*Mx[i][c]; } } return Mx.map(row=>row[n]); }
function solveSupport(Phi,y,support,bits){ support=[...new Set(support)].filter(i=>i>=0&&i<N); const k=support.length; const x=new Float64Array(N); if(k===0) return {x,support}; const G=Array.from({length:k},()=>Array(k).fill(0)); const b=Array(k).fill(0); for(let i=0;i<k;i++){ for(let m=0;m<M;m++) b[i]+=phiAt(Phi,m,support[i])*y[m]; b[i]=quantVal(b[i],bits); for(let j=i;j<k;j++){ let s=0; for(let m=0;m<M;m++) s+=phiAt(Phi,m,support[i])*phiAt(Phi,m,support[j]); s=quantVal(s,bits); G[i][j]=s; G[j][i]=s; } }
 const lam = bits==='FP32'?1e-8:2**(-(bits-8)); for(let i=0;i<k;i++) G[i][i]+=lam; const sol=solveLinear(G,b); for(let i=0;i<k;i++) x[support[i]]=quantVal(sol[i],bits); return {x,support}; }
function omp(Phi,y,bits){ let r=quantVec(y,bits), support=[], x=new Float64Array(N); for(let t=0;t<K;t++){ const c=transCorr(Phi,r,bits); const j=topKAbs(c,1,new Set(support))[0]; support.push(j); ({x,support}=solveSupport(Phi,y,support,bits)); r=residual(y,Phi,x,bits); } return {x,support}; }
function mp(Phi,y,bits){ let r=quantVec(y,bits), x=new Float64Array(N), support=[]; for(let t=0;t<K;t++){ const c=transCorr(Phi,r,bits); const j=topKAbs(c,1)[0]; x[j]=quantVal(x[j]+c[j],bits); if(!support.includes(j)) support.push(j); for(let m=0;m<M;m++) r[m]=quantVal(r[m]-Phi[m*N+j]*c[j],bits); } return {x,support}; }
function gomp(Phi,y,bits){ let r=quantVec(y,bits), support=[], x=new Float64Array(N); for(let t=0;t<Math.ceil(K/2);t++){ const c=transCorr(Phi,r,bits); for(const j of topKAbs(c,N,new Set(support))){ support.push(j); if(support.length>=K) break; } ({x,support}=solveSupport(Phi,y,support.slice(0,K),bits)); r=residual(y,Phi,x,bits); } return {x,support:support.slice(0,K)}; }
function iht(Phi,y,bits){ let x=new Float64Array(N); const mu=0.95/Math.max(spectralNorm2(Phi),1e-12); for(let t=0;t<16;t++){ const r=residual(y,Phi,x,bits); const g=transCorr(Phi,r,bits); const z=new Float64Array(N); for(let i=0;i<N;i++) z[i]=quantVal(x[i]+mu*g[i],bits); x=hardThreshold(z,K,bits); } return {x,support:[...x.keys()].filter(i=>x[i]!==0)}; }
function gp(Phi,y,bits){ let x=new Float64Array(N), support=[]; const mu=0.95/Math.max(spectralNorm2(Phi),1e-12); for(let t=0;t<16;t++){ const r=residual(y,Phi,x,bits); const g=transCorr(Phi,r,bits); const z=new Float64Array(N); for(let i=0;i<N;i++) z[i]=quantVal(x[i]+mu*g[i],bits); support=topKAbs(z,K); ({x,support}=solveSupport(Phi,y,support,bits)); } return {x,support}; }
function sp(Phi,y,bits){ let c=transCorr(Phi,y,bits), support=topKAbs(c,K); let sol=solveSupport(Phi,y,support,bits), x=sol.x; support=sol.support; let r=residual(y,Phi,x,bits); for(let t=0;t<8;t++){ c=transCorr(Phi,r,bits); const cand=[...new Set(support.concat(topKAbs(c,K)))]; sol=solveSupport(Phi,y,cand,bits); support=topKAbs(sol.x,K); sol=solveSupport(Phi,y,support,bits); x=sol.x; support=sol.support; r=residual(y,Phi,x,bits); } return {x,support}; }
function cosamp(Phi,y,bits){ let x=new Float64Array(N), r=quantVec(y,bits), support=[]; for(let t=0;t<8;t++){ const c=transCorr(Phi,r,bits); const T=[...new Set(support.concat(topKAbs(c,2*K)))]; const solT=solveSupport(Phi,y,T,bits); support=topKAbs(solT.x,K); const sol=solveSupport(Phi,y,support,bits); x=sol.x; support=sol.support; r=residual(y,Phi,x,bits); } return {x,support}; }
function htp(Phi,y,bits){ let x=new Float64Array(N), support=[]; const mu=0.95/Math.max(spectralNorm2(Phi),1e-12); for(let t=0;t<8;t++){ const r=residual(y,Phi,x,bits); const g=transCorr(Phi,r,bits); const z=new Float64Array(N); for(let i=0;i<N;i++) z[i]=quantVal(x[i]+mu*g[i],bits); support=topKAbs(z,K); ({x,support}=solveSupport(Phi,y,support,bits)); } return {x,support}; }
const fns={MP:mp,OMP:omp,GOMP:gomp,IHT:iht,GP:gp,SP:sp,CoSaMP:cosamp,HTP:htp};
const rows=[];
for(let tr=0;tr<TRIALS;tr++){
  const Phi=new Float64Array(M*N); for(let i=0;i<M*N;i++) Phi[i]=(rnd()<0.5?-1:1)/Math.sqrt(M);
  const xTrue=new Float64Array(N); const supp=[]; while(supp.length<K){ const j=choiceInt(N); if(!supp.includes(j)) supp.push(j); }
  for(const j of supp) xTrue[j]=(rnd()<0.5?-1:1)*(0.5+rnd());
  const y=matVec(Phi,xTrue,'FP32'); const trueSet=new Set(supp);
  for(const bits of BITS){ const PhiQ=quantVec(Phi,bits), yQ=quantVec(y,bits); for(const alg of ALGS){ const {x,support}=fns[alg](PhiQ,yQ,bits); let e=0, xt=0; for(let i=0;i<N;i++){ const d=x[i]-xTrue[i]; e+=d*d; xt+=xTrue[i]*xTrue[i]; } const yh=matVec(Phi,x,'FP32'); let re=0, yn=0; for(let m=0;m<M;m++){ const d=y[m]-yh[m]; re+=d*d; yn+=y[m]*y[m]; } let hit=0; for(const j of new Set(support)) if(trueSet.has(j)) hit++; rows.push({trial:tr,bits:String(bits),algorithm:alg,nmse:e/xt,residual:Math.sqrt(re/yn),support_rate:hit/K,exact_support:hit===K?1:0}); }}
  console.log(`trial ${tr+1}/${TRIALS}`);
}
function median(a){ const b=[...a].sort((x,y)=>x-y); return b[Math.floor(b.length/2)]; }
const summary={}; for(const alg of ALGS){ summary[alg]={}; for(const bits of BITS.map(String)){ const s=rows.filter(r=>r.algorithm===alg&&r.bits===bits); summary[alg][bits]={nmse_median:median(s.map(r=>r.nmse)), residual_median:median(s.map(r=>r.residual)), support_mean:s.reduce((a,r)=>a+r.support_rate,0)/s.length, exact_support_mean:s.reduce((a,r)=>a+r.exact_support,0)/s.length}; }}
fs.writeFileSync(path.join(OUT,'quantization_results.json'),JSON.stringify({M,N,K,TRIALS,BITS:BITS.map(String),rows},null,2));
fs.writeFileSync(path.join(OUT,'quantization_summary.json'),JSON.stringify(summary,null,2));
let csv='algorithm,bits,nmse_median,residual_median,support_mean,exact_support_mean\n'; for(const alg of ALGS) for(const bits of BITS.map(String)){ const s=summary[alg][bits]; csv += `${alg},${bits},${s.nmse_median},${s.residual_median},${s.support_mean},${s.exact_support_mean}\n`; } fs.writeFileSync(path.join(OUT,'quantization_summary.csv'),csv);
function svgPlot(metric,ylabel,title,file,{log=false}={}){ const W=980,H=560, ml=80,mr=30,mt=55,mb=75; const labels=BITS.map(String), xs=labels.map((_,i)=>ml+i*(W-ml-mr)/(labels.length-1)); let vals=[]; for(const alg of ALGS) for(const b of labels) vals.push(summary[alg][b][metric]); if(log) vals=vals.map(v=>Math.log10(Math.max(v,1e-8))); let ymin=Math.min(...vals), ymax=Math.max(...vals); if(!log){ ymin=Math.min(0,ymin); ymax=Math.min(1,Math.max(0.001,ymax)); } if(ymax===ymin){ ymax=ymin+1; } const pad=(ymax-ymin)*0.08; ymin-=pad; ymax+=pad; const ymap=v=>{ const vv=log?Math.log10(Math.max(v,1e-8)):v; return mt+(ymax-vv)*(H-mt-mb)/(ymax-ymin); }; const colors=['#1f77b4','#ff7f0e','#2ca02c','#d62728','#9467bd','#8c564b','#e377c2','#17becf']; let s=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">\n<style>text{font-family:Arial,Helvetica,sans-serif;font-size:14px}.title{font-size:20px;font-weight:600}.axis{stroke:#222;stroke-width:1.2}.grid{stroke:#ddd;stroke-width:1}.lab{font-size:15px}.legend{font-size:13px}</style>\n<rect width="100%" height="100%" fill="white"/>\n<text x="${W/2}" y="28" text-anchor="middle" class="title">${title}</text>\n`;
 for(let t=0;t<=5;t++){ const yy=mt+t*(H-mt-mb)/5; const val=ymax-t*(ymax-ymin)/5; const label=log?(10**val).toExponential(1):val.toFixed(2); s+=`<line x1="${ml}" y1="${yy}" x2="${W-mr}" y2="${yy}" class="grid"/><text x="${ml-10}" y="${yy+5}" text-anchor="end">${label}</text>\n`; }
 s+=`<line x1="${ml}" y1="${H-mb}" x2="${W-mr}" y2="${H-mb}" class="axis"/><line x1="${ml}" y1="${mt}" x2="${ml}" y2="${H-mb}" class="axis"/>\n`;
 for(let i=0;i<labels.length;i++){ s+=`<line x1="${xs[i]}" y1="${H-mb}" x2="${xs[i]}" y2="${H-mb+6}" stroke="#222"/><text x="${xs[i]}" y="${H-mb+25}" text-anchor="middle">${labels[i]}</text>\n`; }
 const x24=xs[labels.indexOf('24')]; s+=`<line x1="${x24}" y1="${mt}" x2="${x24}" y2="${H-mb}" stroke="#111" stroke-dasharray="6,5"/><text x="${x24+7}" y="${mt+18}">24-bit</text>\n`;
 for(let a=0;a<ALGS.length;a++){ const alg=ALGS[a]; let pts=[]; for(let i=0;i<labels.length;i++) pts.push(`${xs[i]},${ymap(summary[alg][labels[i]][metric])}`); s+=`<polyline fill="none" stroke="${colors[a]}" stroke-width="2.4" points="${pts.join(' ')}"/>\n`; for(let i=0;i<labels.length;i++) s+=`<circle cx="${xs[i]}" cy="${ymap(summary[alg][labels[i]][metric])}" r="4" fill="${colors[a]}"/>\n`; }
 s+=`<text x="${W/2}" y="${H-18}" text-anchor="middle" class="lab">Numeric format / datapath width</text><text transform="translate(20 ${H/2}) rotate(-90)" text-anchor="middle" class="lab">${ylabel}</text>\n`;
 for(let a=0;a<ALGS.length;a++){ const lx=ml+(a%4)*210, ly=H-48+Math.floor(a/4)*20; s+=`<line x1="${lx}" y1="${ly}" x2="${lx+25}" y2="${ly}" stroke="${colors[a]}" stroke-width="2.4"/><circle cx="${lx+12}" cy="${ly}" r="4" fill="${colors[a]}"/><text x="${lx+33}" y="${ly+5}" class="legend">${ALGS[a]}</text>\n`; }
 s+='</svg>\n'; fs.writeFileSync(path.join(OUT,file+'.svg'),s); }
svgPlot('nmse_median','Median NMSE of recovered x','Quantization impact on reconstruction error','fig_quant_nmse',{log:true});
svgPlot('support_mean','Mean support recovery rate','Quantization impact on support recovery','fig_quant_support');
svgPlot('residual_median','Median relative residual norm','Quantization impact on residual consistency','fig_quant_residual',{log:true});
console.log('DONE '+OUT); for(const alg of ALGS) console.log(alg, 'support@24=', summary[alg]['24'].support_mean.toFixed(3), 'nmse@24=', summary[alg]['24'].nmse_median.toExponential(2));

