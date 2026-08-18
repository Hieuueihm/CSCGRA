import importlib.util
p=r'D:\vivado_pj\analysis\reconstruction_quality_noisy24\noisy_lfsr_24bit_per_algorithm_seed_k8.py'
spec=importlib.util.spec_from_file_location('m',p); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
phi_q=m.make_phi_q(); A=[[v/float(1<<m.Q) for v in row] for row in phi_q]
def run_gp_scaled(A,y,seed_shift=3):
    x=[0.0]*m.N; r=list(y); bx=list(x); bn=m.norm(r); support=[]; mu=1.0/(1<<seed_shift)
    for _ in range(m.GP_ITERS):
        corr=m.trans_corr(A,r)
        pick=m.top_abs(corr,1,support)
        if pick: support.append(pick[0])
        z=[x[i]+mu*corr[i] for i in range(m.N)]
        S=m.prune(z,m.K)
        keep=set(S); x=[z[i] if i in keep else 0.0 for i in range(m.N)]
        r=m.residual(A,y,x); bx,bn=m.best_update(x,r,bx,bn)
    return bx
for sh in range(0,8):
    rows=[]
    for seed in [132,192,101,87,140]:
        support,x_true_q=m.make_signal(seed); y_clean_q=m.quant_mat_vec(phi_q,x_true_q); y_noisy_q=m.add_noise(y_clean_q)
        x_true=[m.f24(v) for v in x_true_q]; y=[m.f24(v) for v in y_noisy_q]
        x_hat_q=[m.q24(v) for v in run_gp_scaled(A,y,sh)]
        mse,snr,overlap=m.metrics(x_true,[m.f24(v) for v in x_hat_q])
        rows.append((seed,snr,mse,overlap))
    print('shift',sh,' '.join(f'seed{s}:{snr:.2f}dB/{ov}' for s,snr,mse,ov in rows))
