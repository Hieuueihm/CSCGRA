# Fair reconstruction-quality evaluation for the paper

## Why the old representative table is not sufficient

The previous representative quality table used a different `x_seed` for each algorithm. This makes the comparison statistically unfair because each algorithm sees a different sparse signal and a different noise realization. Therefore, the table can only be used as an example of per-algorithm reconstruction, not as evidence that one algorithm is better than another.

For example, if GOMP uses seed 13 and MP uses seed 140, then the measured SNR gap may be caused by the signal/noise instance rather than the algorithm. A reviewer can correctly object that the experiment does not isolate algorithmic behavior.

## Replacement methodology

Use a common-trial Monte Carlo protocol:

- Fixed configuration: `(N,M,K)=(256,64,8)`.
- Fixed sensing matrix seed: `Phi seed = 0xDEADBEEF`.
- For each Monte Carlo trial `l`, generate one sparse vector `x^(l)` and one noise vector per measurement-SNR setting.
- Run all eight algorithms on exactly the same `Phi`, `x^(l)`, clean measurement, and noisy measurement.
- Report aggregate statistics across trials, not a single hand-picked seed.

The generated script reports:

- mean and standard deviation of reconstruction SNR;
- mean MSE;
- mean NMSE;
- average support overlap;
- exact-support recovery rate;
- success rate, defined here as exact support and `NMSE <= 1e-2`.

## Files

- Script: `D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_quality.py`
- Raw per-trial data: `D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_raw.csv`
- Summary CSV: `D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_summary.csv`
- Summary Markdown: `D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_summary.md`
- LaTeX table: `D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_summary_table.tex`

## Current run

The current run uses 100 trials at 10, 20, 30, and 40 dB measurement noise. This is enough to replace the problematic single-seed table during drafting. For a final camera-ready paper, rerun the same script with `--trials 1000` if runtime is acceptable.

Command:

```powershell
python D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_quality.py --trials 100 --snrs 10,20,30,40
```

Optional final run:

```powershell
python D:\vivado_pj\analysis\fair_quality_monte_carlo\fair_monte_carlo_quality.py --trials 1000 --snrs 10,20,30,40
```

## Paper wording suggestion

Instead of saying that a method is best based on a single seed, write:

> Reconstruction quality is evaluated using a common-trial Monte Carlo setup. For each trial, all algorithms use the same sensing matrix, sparse signal, and noise realization. We report the mean and standard deviation of reconstruction SNR, mean MSE/NMSE, exact-support recovery rate, and success probability over 100 trials for each measurement SNR.

This directly addresses the fairness issue in the previous table.
