"""Annotate applicability of a rounding-only bound in completed LS evidence.

Does not rerun or replace numerical results. A saturated oracle is outside the
rounding-only bound's assumptions. Preserve the executed source identities and
record this later metadata correction explicitly.
"""
import argparse
import hashlib
import json
from pathlib import Path


def review(path):
    original=path.read_bytes(); report=json.loads(original)
    if report.get('derived_bound_review'): raise ValueError('already reviewed: '+str(path))
    assert report['complete']
    corrected=[]
    for row in report['rows']:
        oracle=row['X_rounded_oracle']
        valid=not any(oracle['events'].values()) and oracle['normal_rounding_upper_bound_relative'] is not None
        oracle['normal_rounding_bound_applicable']=valid
        if not valid and oracle['normal_rounding_upper_bound_relative'] is not None:
            oracle['unclipped_formula_value_not_applicable']=oracle['normal_rounding_upper_bound_relative']
            oracle['normal_rounding_upper_bound_relative']=None
            corrected.append({'case':row['case'],'configuration':row['configuration']})
        row['input_operator_error_scope']='combined measurement D and coefficient C quantization; no recurrence/storage error'
    report['derived_bound_review']={
        'script':'scripts/v4/review_lfsr_evidence.py',
        'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'original_report_sha256':hashlib.sha256(original).hexdigest(),
        'numerical_results_recomputed':False,
        'change':'mark rounding bound unavailable for saturated oracle; clarify combined input/operator error',
        'corrected_rows':corrected,
        'executed_source_hashes_preserved':True}
    path.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(path.name,len(corrected),'inapplicable bounds nulled; numerical results unchanged')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reports',nargs='+',type=Path)
    for path in parser.parse_args().reports: review(path)
