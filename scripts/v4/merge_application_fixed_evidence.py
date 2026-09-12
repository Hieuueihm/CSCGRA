"""Assemble completed fixed-case evidence, retaining every execution provenance.

Completed rows from a deliberately interrupted checkpoint may be reused. Such
checkpoints remain separate, incomplete artifacts. No numerical result is run,
repaired, or relabelled by this assembler; overlapping results must match exactly.
"""
from __future__ import annotations
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def key(row):
    return row['domain'],row['case'],row['algorithm'],row['recipe_id']


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parts',nargs='+',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    paths=[p.resolve() for p in args.parts]
    output=args.output.resolve()
    assert output not in paths
    reports=[json.loads(p.read_text(encoding='utf-8')) for p in paths]
    template=reports[0]
    selection_path=ROOT/template['selection_report']
    assert sha(selection_path)==template['selection_report_sha256']
    provenance=[]; union_sources={}; rows={}; duplicates=[]
    for path,part in zip(paths,reports):
        assert part['complete'] or part.get('interrupted_for_execution_acceleration'),path
        for field in ('selection_report','selection_report_sha256','thresholds','LS_coefficient_diagnostic_rtol'):
            assert part[field]==template[field],(path,field)
        for field in ('profile','solution_format'):
            assert part['configuration'][field]==template['configuration'][field],(path,field)
        source_hashes=part['source_sha256']
        bundle=hashlib.sha256(json.dumps(source_hashes,sort_keys=True).encode()).hexdigest()
        archive=ROOT/'reports/v4/source_snapshots'/bundle
        base=archive if archive.exists() else ROOT
        for relative,digest in source_hashes.items():
            assert sha(base/relative)==digest,(path,relative)
            if relative in union_sources:
                assert union_sources[relative]==digest,('mixed revisions require separate review',relative)
            union_sources[relative]=digest
        item={'report':path.relative_to(ROOT).as_posix(),'sha256':sha(path),
              'source_bundle':bundle,'component_complete':part['complete'],
              'completed_case_rows':len(part['rows']),
              'execution_entrypoint':part.get('execution_entrypoint','scripts/v4/lfsr_application_fixed_validation.py')}
        provenance.append(item)
        for row in part['rows']:
            identity=key(row)
            if identity in rows:
                previous=deepcopy(rows[identity])
                previous.pop('execution_provenance')
                previous.pop('model_seconds')
                current=deepcopy(row);current.pop('model_seconds')
                assert previous==current,('different numerical outputs',identity)
                duplicates.append({'identity':list(identity),'compared_report':item['report'],
                                   'previous_report':rows[identity]['execution_provenance']['report'],
                                   'all_numerical_fields_exactly_equal':True})
            rows[identity]={**deepcopy(row),'execution_provenance':item}
    expected=[(s['domain'],c['case'],s['algorithm'],s['winner']['recipe_id'])
              for s in template['selected_policies'] for c in s['winner']['case_results']]
    assert len(expected)==len(set(expected))==template['rows_expected']
    assert set(rows)==set(expected),('missing or extraneous rows',set(expected)-set(rows),set(rows)-set(expected))
    ordered=[rows[k] for k in expected]
    union_sources[Path(__file__).relative_to(ROOT).as_posix()]=sha(Path(__file__))
    report=deepcopy(template)
    for field in ('interrupted_for_execution_acceleration','interruption_reason','original_checkpoint_path',
                  'source_unchanged_during_run'):
        report.pop(field,None)
    report.update(complete=True,assembly_only=True,
        assembly_scope='union_of_completed_selected_cases_with_verified_original_execution_sources',
        execution_backend='per_row_provenance_guarded_integer_with_or_without_conversion_cache',
        source_sha256=union_sources,source_unchanged_during_assembly=True,
        execution_components=provenance,duplicate_execution_comparisons=duplicates,
        rows=ordered,summary={'rows':len(ordered),'combined_pass':sum(r['combined_pass'] for r in ordered),
            'quality_no_fault_pass':sum(r['quality_and_no_fault_pass'] for r in ordered),
            'LS_diagnostic_fail_rows':sum(not r['LS_diagnostic_pass'] for r in ordered)})
    report['configuration']['output']=output.as_posix()
    for path,item in zip(paths,provenance):
        assert sha(path)==item['sha256'],'component changed while assembling'
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(output.name,report['summary'],'exact duplicate checks',len(duplicates))


if __name__=='__main__':
    main()
