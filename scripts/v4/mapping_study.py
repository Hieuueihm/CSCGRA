"""Compare resident GEMV schedules; output is predicted, never measured RTL."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from compiler.v4.mapping import compile_gemv


def main():
    rows = []
    cases = [('dense',128,1024),('support8',128,8),('support32',128,32),
             ('support96',128,96),('tails',33,17)]
    for name,m,n in cases:
        for transpose in (False,True):
            for reduction in (None,1,4):
                schedule = compile_gemv(m,n,transpose=transpose,reduction_lanes=reduction)
                rows.append({'case':name,'matrix_rows':m,'matrix_columns':n,
                    'transpose':transpose,'requested_reduction_lanes':reduction,
                    'selected_reduction_lanes':schedule.reduction_lanes,**schedule.metrics})
    out = ROOT/'reports/v4'
    out.mkdir(parents=True,exist_ok=True)
    source = ROOT/'compiler/v4/mapping.py'
    result = {'scope':'predicted_resident_GEMV_only','includes_DDR_DMA':False,
              'includes_support_pack':False,'rows':rows,
              'mapping_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
    (out/'mapping_comparison.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    lines = ['# V4 resident GEMV mapping study','',
             'Predictions from an executable integer routing model. No v4 RTL measurements.',
             'One-cycle synchronous matrix read; ideal MAC II=1; no stalls, DMA, numeric narrowing or support packing.','',
             '| Matrix | Direction | Fixed R1 cycles | Fixed R4 cycles | Chosen R | Chosen cycles | MAC utilization |',
             '|---|---|---:|---:|---:|---:|---:|']
    for name,m,n in cases:
        for transpose in (False,True):
            group = {r['requested_reduction_lanes']:r for r in rows if r['case']==name and r['transpose']==transpose}
            chosen = group[None]
            direction = 'transpose' if transpose else 'forward'
            lines.append(f"| {m}x{n} | {direction} | {group[1]['predicted_compute_cycles']} | {group[4]['predicted_compute_cycles']} | {chosen['selected_reduction_lanes']} | {chosen['predicted_compute_cycles']} | {chosen['mac_slot_utilization']:.1%} |")
    lines += ['', 'For M128/S8, chosen forward+transpose costs79 predicted cycles versus183 for fixed R4.',
        'This excludes preparation: the proposed conservative two-pass support pack alone takes288 payload issues',
        'plus startup/drain/control, and must be amortized against a measured direct-gather baseline.',
        'No end-to-end speedup or architectural novelty is established by this table.', '',
        'Reproduce: `py -3 scripts/v4/mapping_study.py`.']
    (out/'MAPPING_SUMMARY.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('Wrote30 predicted schedule comparisons; RTL measured cycles remain null.')


if __name__ == '__main__':
    main()
