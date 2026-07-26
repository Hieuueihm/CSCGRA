# Fair Monte Carlo Reconstruction Quality

Configuration: N=256, M=64, K=8, trials per SNR=100, Phi seed=0xDEADBEEF, mu_shift=3.
Each trial uses the same sparse signal, sensing matrix, and noise realization for all algorithms.

## Measurement SNR 10 dB
| Algorithm | SNR mean (dB) | SNR std (dB) | MSE mean | NMSE mean | Support overlap | Exact support | Success |
|---|---:|---:|---:|---:|---:|---:|---:|
| OMP | 16.67 | 6.06 | 1.283e-03 | 8.221e-02 | 7.51/8 | 76.0% | 31.0% |
| GOMP | 13.06 | 6.18 | 1.750e-03 | 1.144e-01 | 7.01/8 | 39.0% | 20.0% |
| CoSaMP | 14.73 | 5.73 | 1.264e-03 | 8.547e-02 | 7.28/8 | 52.0% | 21.0% |
| SP | 16.66 | 5.03 | 7.641e-04 | 4.928e-02 | 7.60/8 | 70.0% | 28.0% |
| IHT | 10.63 | 6.38 | 3.062e-03 | 1.950e-01 | 6.37/8 | 28.0% | 7.0% |
| HTP | 11.44 | 6.56 | 2.731e-03 | 1.784e-01 | 6.54/8 | 34.0% | 12.0% |
| GP | 10.63 | 6.38 | 3.062e-03 | 1.950e-01 | 6.37/8 | 28.0% | 7.0% |
| MP | 7.75 | 2.50 | 3.284e-03 | 2.071e-01 | 7.40/8 | 70.0% | 0.0% |

## Measurement SNR 20 dB
| Algorithm | SNR mean (dB) | SNR std (dB) | MSE mean | NMSE mean | Support overlap | Exact support | Success |
|---|---:|---:|---:|---:|---:|---:|---:|
| OMP | 27.49 | 6.59 | 3.722e-04 | 2.025e-02 | 7.86/8 | 91.0% | 91.0% |
| GOMP | 24.45 | 8.24 | 5.172e-04 | 3.047e-02 | 7.70/8 | 76.0% | 76.0% |
| CoSaMP | 29.02 | 3.70 | 1.059e-04 | 7.071e-03 | 7.96/8 | 99.0% | 99.0% |
| SP | 29.01 | 3.72 | 1.127e-04 | 7.530e-03 | 7.96/8 | 99.0% | 99.0% |
| IHT | 22.33 | 9.39 | 1.225e-03 | 7.621e-02 | 7.42/8 | 77.0% | 72.0% |
| HTP | 24.95 | 9.39 | 1.050e-03 | 6.463e-02 | 7.50/8 | 82.0% | 82.0% |
| GP | 22.33 | 9.39 | 1.225e-03 | 7.621e-02 | 7.42/8 | 77.0% | 72.0% |
| MP | 17.19 | 3.26 | 6.284e-04 | 3.674e-02 | 7.91/8 | 97.0% | 8.0% |

## Measurement SNR 30 dB
| Algorithm | SNR mean (dB) | SNR std (dB) | MSE mean | NMSE mean | Support overlap | Exact support | Success |
|---|---:|---:|---:|---:|---:|---:|---:|
| OMP | 37.18 | 8.21 | 2.912e-04 | 1.531e-02 | 7.89/8 | 93.0% | 93.0% |
| GOMP | 32.61 | 12.42 | 5.063e-04 | 3.135e-02 | 7.68/8 | 77.0% | 77.0% |
| CoSaMP | 39.32 | 2.46 | 2.100e-06 | 1.365e-04 | 8.00/8 | 100.0% | 100.0% |
| SP | 39.32 | 2.46 | 2.100e-06 | 1.365e-04 | 8.00/8 | 100.0% | 100.0% |
| IHT | 28.65 | 12.28 | 9.531e-04 | 5.832e-02 | 7.54/8 | 81.0% | 79.0% |
| HTP | 33.90 | 12.52 | 8.807e-04 | 5.358e-02 | 7.55/8 | 84.0% | 84.0% |
| GP | 28.65 | 12.28 | 9.531e-04 | 5.832e-02 | 7.54/8 | 81.0% | 79.0% |
| MP | 26.82 | 5.61 | 3.617e-04 | 1.988e-02 | 7.91/8 | 97.0% | 93.0% |

## Measurement SNR 40 dB
| Algorithm | SNR mean (dB) | SNR std (dB) | MSE mean | NMSE mean | Support overlap | Exact support | Success |
|---|---:|---:|---:|---:|---:|---:|---:|
| OMP | 47.15 | 9.43 | 2.628e-04 | 1.354e-02 | 7.91/8 | 95.0% | 95.0% |
| GOMP | 41.68 | 15.64 | 3.953e-04 | 2.426e-02 | 7.73/8 | 80.0% | 80.0% |
| CoSaMP | 49.14 | 2.73 | 2.297e-07 | 1.470e-05 | 8.00/8 | 100.0% | 100.0% |
| SP | 49.14 | 2.73 | 2.297e-07 | 1.470e-05 | 8.00/8 | 100.0% | 100.0% |
| IHT | 31.46 | 14.53 | 9.784e-04 | 6.005e-02 | 7.53/8 | 79.0% | 78.0% |
| HTP | 43.43 | 15.10 | 7.782e-04 | 4.918e-02 | 7.60/8 | 87.0% | 87.0% |
| GP | 31.46 | 14.53 | 9.784e-04 | 6.005e-02 | 7.53/8 | 79.0% | 78.0% |
| MP | 36.52 | 6.98 | 2.176e-04 | 1.116e-02 | 7.93/8 | 98.0% | 94.0% |

Paper note: do not compare algorithms using different x-seeds. Use these aggregate statistics or an equivalent common-trial Monte Carlo setup.