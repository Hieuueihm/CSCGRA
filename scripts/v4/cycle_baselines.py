"""Extract retained V2/V3 RTL cycle evidence; do not run or modify old designs."""
from pathlib import Path
import csv
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'reports/v4/legacy_cycle_baselines_20260909'
ALGORITHMS = ('OMP', 'CoSaMP', 'IHT', 'HTP', 'SP', 'GP', 'GOMP', 'MP')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sources = {}

    def read(relative):
        path = ROOT / relative
        data = path.read_bytes()
        sources[relative] = hashlib.sha256(data).hexdigest()
        target = OUT / 'sources' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return data.decode('utf-8-sig')

    report = read('reports/v2/hardware_golden_signoff.md')
    header = read('verification/v2/run1/k_sweep_golden_hardware.vh')
    read('verification/v2/run1/tb_run1_k_sweep.v')
    records = []
    for case in (1, 5, 7):
        dimensions = {key.lower(): int(re.search(
            rf'KSHW_CASE_{case}_{key} = (\d+);', header)[1]) for key in ('M', 'N', 'K')}
        cells = re.search(rf'^\| {case} \(K\d+\) \|(.+)\|$', report, re.M)[1].split('|')
        for algorithm, cell in zip(ALGORITHMS, cells):
            records.append(dict(version='V2', suite='hardware_golden_signoff', case=case,
                **dimensions, algorithm=algorithm, cycles=int(cell.strip()),
                outer_limit=(dimensions['k']+1)//2 if algorithm == 'GOMP' else dimensions['k'],
                actual_outer=None, validation='retained_report_only',
                note='Original logs absent at the report path; current header/TB corroborate geometry/budget, not historical source identity. GP is the full-gradient variant.'))

    for suite in ('m13_fixed_iteration_benchmark/outer8',
                  'm13_correctness_sweep_rtl_pe_colocated_20260908',
                  'm13_correctness_sweep_p1_selection_policy_full_20260908'):
        relative = f'reports/v3/{suite}/results.csv'
        for row in csv.DictReader(read(relative).splitlines()):
            if row['profile'] != 'strict_paper':
                continue
            if 'selection_policy' in suite and int(row['k']) != 16:
                continue
            log_relative = f"reports/v3/{suite}/{Path(row['log']).name}"
            log = read(log_relative)
            matches = re.findall(r'M13 E2E CASE PASS m=(\d+) n=(\d+) k=(\d+) algorithm=(\d+) profile=(\d+) cycles=(\d+)', log)
            expected = (int(row['m']), int(row['n']), int(row['k']),
                        ALGORITHMS.index(next(a for a in ALGORITHMS if a.lower() == row['algorithm'])),
                        0, int(row['cycles']))
            failed = bool(re.search(r'^FAIL:', log, re.M))
            validated = not failed and expected in [tuple(map(int, item)) for item in matches]
            iterations = re.findall(r'M13 E2E ITERATIONS .*?actual=(\d+) expected=(\d+)', log)
            records.append(dict(version='V3', suite=suite, m=expected[0], n=expected[1], k=expected[2],
                algorithm=ALGORITHMS[expected[3]], seed=int(row['seed']), cycles=expected[5],
                outer_limit=int(row['outer_iteration_limit']),
                actual_outer=int(iterations[-1][0]) if iterations else None,
                csv_status=row['status'], validation='csv_and_log_agree' if validated else 'excluded_csv_log_conflict',
                log=log_relative, source_bundle_hash=row.get('source_bundle_hash'),
                failures_present=failed))

    payload = dict(scope='Historical RTL cycle evidence, not fresh simulation or an equal-quality V4 speed comparison',
                   records=records, source_sha256=sources,
                   excluded_models=['reports/v3/architecture_cycle_simulation/summary.md'])
    (OUT/'baselines.json').write_text(json.dumps(payload, indent=2)+'\n', encoding='utf-8')
    lines = ['# V2/V3 cycle anchors', '',
             'Extracted from retained evidence on 2026-09-09. No V2/V3 files modified.', '',
             'V2 rows are retained report evidence; the original simulation logs are absent at the cited path. '
             'V3 rows marked `verified` match the PASS line, geometry and cycle count in the saved xsim log, '
             'with no FAIL line. This does not requalify current RTL or establish equal numerical quality.', '',
             '| Version / suite | M / N / K | Algorithm | Outer limit / actual | Cycles | Evidence |',
             '|---|---|---|---|---:|---|']
    for r in records:
        state = {'csv_and_log_agree':'verified', 'retained_report_only':'report only',
                 'excluded_csv_log_conflict':'EXCLUDED: CSV/log conflict'}[r['validation']]
        lines.append(f"| {r['version']} / {r['suite']} | {r['m']} / {r['n']} / {r['k']} | {r['algorithm']} | "
                     f"{r['outer_limit']} / {r['actual_outer'] if r['actual_outer'] is not None else 'unrecorded'} | {r['cycles']} | {state} |")
    lines += ['', 'The forced-eight CSV has conflicting logs for some rows; excluded rows are preserved for traceability, '
              'never used as a passing baseline. The older `v2_v3_k8_cycle_compare.md` also contains different counts. '
              'Use the record-level evidence above.', '',
              'V2 counts `seq_busy`; V3 counts `engine_busy` after resident-image and measurement preload, including runtime '
              'Phi generation and result drain. V4 reports accepted START through DONE and separately profiles services and commit. '
              'These boundaries need separate setup/core/drain reporting before any speedup claim.', '',
              'V2 default GP and CoSaMP have documented semantic differences; V3 uses Threefry/CGLS with side arithmetic; '
              'V4 uses LFSR/shared PE arithmetic/QR. GOMP uses ceil(K/2) outer iterations in V2, versus eight in the V3 forced-eight suite.', '',
              '[Machine-readable records and SHA256 provenance](baselines.json). Exact consumed source bytes are in `sources/`.']
    (OUT/'README.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(json.dumps(dict(records=len(records), verified=sum(r['validation']=='csv_and_log_agree' for r in records),
                          conflicts=sum(r['validation']=='excluded_csv_log_conflict' for r in records))))


if __name__ == '__main__':
    main()
