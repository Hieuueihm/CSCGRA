"""Fail-closed QR panel-threshold survey for matched fixed-K8 archives."""
import argparse
import hashlib
import json
from pathlib import Path

from scripts.v4 import report_resident_chain_comparison as base

QR = ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP')


class ValidationError(ValueError):
    pass


def read(path):
    return base.read_summary(path)


def _sources_equal(left, right, label):
    excluded = base.PRODUCTION_SOURCE_EXCLUSIONS
    l = {k: v for k, v in left.items() if k not in excluded}
    r = {k: v for k, v in right.items() if k not in excluded}
    if l != r:
        raise ValidationError(f'{label}: production source snapshot differs')


def survey_pair(before_path, after_path, rows):
    bp, before = read(before_path); ap, after = read(after_path)
    try:
        before_cases, before_cfg, before_sources = base.load_cases(before, bp, rows, f'before M{rows}', QR)
        after_cases, after_cfg, after_sources = base.load_cases(after, ap, rows, f'after M{rows}', QR)
        base.compare_config(before_cfg, after_cfg, f'M{rows}', frozenset({'qr_panel_min_columns'}))
    except base.ValidationError as error:
        raise ValidationError(str(error)) from error
    if before_cfg.get('qr_profile') != 'view' or after_cfg.get('qr_profile') != 'view':
        raise ValidationError(f'M{rows}: threshold survey requires qr_profile=view')
    if any(type(config.get('qr_panel_min_columns')) is not int or not 1 <= config['qr_panel_min_columns'] <= 96
           for config in (before_cfg, after_cfg)):
        raise ValidationError(f'M{rows}: panel threshold must be an integer in1..96')
    if before_cfg.get('qr_panel_min_columns') == after_cfg.get('qr_panel_min_columns'):
        raise ValidationError(f'M{rows}: panel thresholds must differ')
    _sources_equal(before_sources, after_sources, f'M{rows}')
    rows_out = []
    for algorithm in QR:
        try:
            rows_out.append(base.compare_case(before_cases[algorithm], after_cases[algorithm], rows, algorithm, frozenset(QR)))
        except base.ValidationError as error:
            raise ValidationError(str(error)) from error
    return dict(rows=rows, columns=64 if rows == 32 else 256, fixed_k=8, actual_outer=8,
                threshold_before=before_cfg['qr_panel_min_columns'], threshold_after=after_cfg['qr_panel_min_columns'],
                before_summary_sha256=base.digest(bp), after_summary_sha256=base.digest(ap), rows_output=rows_out)


def render(result):
    lines=['# Khảo sát ngưỡng panel QR', '',
           'Mỗi cặp dùng cùng nguồn production, profile `view`, K=8, outer thực tế=8, Phi/Y thô, policy, raw X/R/support/status, chứng chỉ/refinement và chất lượng. Chỉ `qr_panel_min_columns` và `report_name` được phép khác.',
           'Không có ước lượng timing, PPA hoặc xác nhận chất lượng ứng dụng.', '']
    for geometry in result['geometries']:
        lines += [f"## M={geometry['rows']}, N={geometry['columns']}", '', f"Ngưỡng: {geometry['threshold_before']} → {geometry['threshold_after']}.", '', '| Thuật toán | Chu kỳ trước | Chu kỳ sau | Giảm % | outer | LS/refine | QR max S |', '|---|---:|---:|---:|---:|---:|---:|']
        for row in geometry['rows_output']:
            ls=row['logical_ls']; lines.append(f"| {row['algorithm']} | {row['cycles_before']} | {row['cycles_after']} | {row['reduction_percent']:.2f} | 8 | {ls['solver_solve_count']}/{ls['solver_refinement_count']} | {ls['maximum_ls_support']} |")
        lines.append('')
    return '\n'.join(lines)+'\n'


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    for rows in (32,64):
        p.add_argument(f'--before-m{rows}', required=True); p.add_argument(f'--after-m{rows}', required=True)
    p.add_argument('--output', required=True); args=p.parse_args(argv); output=Path(args.output)
    if output.exists(): raise ValidationError(f'output exists: {output}')
    result=dict(schema=1,status='PASS',scope='QR-only threshold survey; active10 validator remains unchanged',geometries=[survey_pair(args.before_m32,args.after_m32,32),survey_pair(args.before_m64,args.after_m64,64)])
    output.mkdir(parents=True); (output/'panel_threshold_survey.json').write_text(json.dumps(result,indent=2)+'\n'); (output/'panel_threshold_survey_vi.md').write_text(render(result))

if __name__=='__main__': main()
