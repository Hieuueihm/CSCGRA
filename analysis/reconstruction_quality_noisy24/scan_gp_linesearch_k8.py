import importlib.util
p=r'D:\vivado_pj\analysis\reconstruction_quality_noisy24\noisy_lfsr_24bit_per_algorithm_seed_k8_gp_linesearch.py'
spec=importlib.util.spec_from_file_location('gpmod',p)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
phi_q=m.make_phi_q(); A=[[v/float(1<<m.Q) for v in row] for row in phi_q]
rows=[]
for seed in range(1,301):
    support,x_true_q=m.make_signal(seed)
    y_clean_q=m.quant_mat_vec(phi_q,x_true_q); y_noisy_q=m.add_noise(y_clean_q)
    x_true=[m.f24(v) for v in x_true_q]; y=[m.f24(v) for v in y_noisy_q]
    x_hat_q=[m.q24(v) for v in m.run_gp(A,y)]
    mse,snr,overlap=m.metrics(x_true,[m.f24(v) for v in x_hat_q])
    rows.append((snr,mse,overlap,seed))
rows.sort(reverse=True)
for snr,mse,overlap,seed in rows[:25]:
    print(f'seed={seed:3d} snr={snr:6.2f} mse={mse:.10e} overlap={overlap}/8')
