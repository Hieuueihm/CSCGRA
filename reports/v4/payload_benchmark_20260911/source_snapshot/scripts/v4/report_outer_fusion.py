"""Fail-closed fixed-eight comparison of the bounded HTP outer fusion."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from scripts.v4 import report_resident_chain_comparison as evidence
from verification.v4.recovery_cycle_profile import cycle_profile

INPUTS = {
    32: ('02524e01f702995b6e494e81c2142b1f66b526303323a37dcfc3aa4d0b8b7971',
         'c7ae387e7a98fca15d60862397b6164419c4cdfe11f5913b37ddec9b105108c9'),
    64: ('8a498acd18fc9909cd3900feaf9951ff262ae5fd8b7f867331d9720fcd727de8',
         '2fa1e50a2a54d25f9a0393ccffc91b3977a2b83014f33039ec0696365f09ba4e'),
}

def require(condition, message):
    if not condition:
        raise evidence.ValidationError(message)

def raw_digest(values):
    return hashlib.sha256(b''.join(struct.pack('<i',value) for value in values)).hexdigest()

def trace_outputs(text, case):
    vectors = {'X':[], 'V':[]}
    done, metadata = [], []
    for line in text.splitlines():
        fields = line.split()
        if len(fields)<2 or fields[1]!='1':
            continue
        if fields[0] in vectors:
            require(int(fields[2])==len(vectors[fields[0]]),'noncontiguous result indices')
            raw = int(fields[3],16)
            vectors[fields[0]].append(raw-(1<<27) if raw&(1<<26) else raw)
        elif fields[0]=='D':
            done.append(fields[2:])
        elif fields[0]=='M':
            metadata.append(fields[2:])
    require(len(done)==1 and len(metadata)==1,'missing or duplicate completion')
    require(len(vectors['X'])==case['columns'] and len(vectors['V'])==case['rows'],'short result')
    require(raw_digest(vectors['X'])==case['output_raw_x_sha256'],'raw X digest mismatch')
    require(raw_digest(vectors['V'])==case['output_raw_r_sha256'],'raw residual digest mismatch')
    require(int(done[0][-1])==case['job_cycles'] and int(done[0][4])==8,'cycle or actual outer mismatch')
    require(done[0][0]=='0' and done[0][3]=='1','faulted or unpublished result')
    return dict(vectors=vectors,done=done[0][:-1],metadata=metadata[0])

def load(path, rows):
    path, summary = evidence.read_summary(path)
    sources = evidence.require_clean(summary,path,str(path))
    config = evidence.require_frozen_benchmark_config(summary,path,str(path))
    require(rows in INPUTS,'unsupported measured geometry')
    columns = 64 if rows==32 else 256
    require((config['rows'],config['columns'],config['sparsity'],config['outer'])==(rows,columns,8,8),
            'geometry, K or outer mismatch')
    require(config.get('fixed_iteration_benchmark') is True,'fixed-eight policy required')
    require(len(config['algorithms'])==10 and set(config['algorithms'])==set(evidence.ACTIVE),'active10 required')
    require(summary['replays']==10 and summary['expected_replays']==10 and
            summary['failures']==0 and summary['errors']==0,'incomplete benchmark')
    cases = {}
    for case in summary['cases']:
        algorithm = case['algorithm']
        require(algorithm in evidence.ACTIVE and algorithm not in cases,'duplicate or unexpected algorithm')
        require(all(key in case for key in evidence.IDENTITY),'missing fairness fields')
        require(case['rows']==rows and case['columns']==columns and case['returncode']==0,'invalid RTL result')
        require(case['requested_outer_iterations']==case['outer_iterations']==8,'not actual eight iterations')
        require(len(case['planted_support'])==8,'truth sparsity mismatch')
        require((case['raw_phi_sha256'],case['raw_y_sha256'])==INPUTS[rows],'input differs from pinned fixture')
        for key, expected in zip(('expected_phi_sha256','expected_y_sha256'),INPUTS[rows]):
            require(config.get(key) in (None,expected),'configured input hash mismatch')
        current = dict(case)
        current['_artifacts'] = evidence.artifact_digests(case,path.parent,config,algorithm)
        current['_services'] = evidence.service_totals(case,algorithm)
        _, package_root, index = evidence.load_digest(case,path.parent,algorithm)
        trace = (package_root.parent / f'trace{index}.txt').read_text()
        require(cycle_profile(trace)==case['cycle_profile'],'cycle profile differs from raw trace')
        require(case['cycle_profile']['incomplete_services']==[],'unfinished service')
        current['_raw'] = trace_outputs(trace,case)
        package = json.loads((package_root/'package.json').read_text())
        if algorithm in evidence.QR:
            require(package['outer_fusion'] is config['outer_fusion'],'package fusion flag mismatch')
            require(package['outer_fusion_emitted'] is (config['outer_fusion'] and algorithm=='HTP'),
                    'unexpected fusion site')
        cases[algorithm] = current
    require(set(cases)==set(evidence.ACTIVE),'missing active algorithm')
    return path,summary,sources,config,cases

def compare(before_path, after_path, rows):
    before_path,before,before_sources,before_config,old = load(before_path,rows)
    after_path,after,after_sources,after_config,new = load(after_path,rows)
    require(before_config['outer_fusion'] is False and after_config['outer_fusion'] is True,'expected off-to-on')
    require({key:value for key,value in before_config.items() if key!='outer_fusion'}==
            {key:value for key,value in after_config.items() if key!='outer_fusion'},'other configuration changed')
    require(evidence.production_sources(before_sources)==evidence.production_sources(after_sources),'production sources changed')
    output = []
    for algorithm in evidence.ACTIVE:
        baseline,candidate = old[algorithm],new[algorithm]
        require(baseline['_raw']==candidate['_raw'],f'{algorithm}: raw result/status/support differs')
        row = evidence.compare_case(baseline,candidate,rows,algorithm,{'HTP'})
        require(evidence._physical_factor_counts(baseline,algorithm)==
                evidence._physical_factor_counts(candidate,algorithm),'QR physical work differs')
        for key in set(baseline['_services']) | set(candidate['_services']):
            if key in ('KERNEL:0','KERNEL:23'):
                continue
            require(baseline['_services'].get(key)==candidate['_services'].get(key),
                    f'{algorithm}: unrelated service changed: {key}')
        if algorithm=='HTP':
            require(row['image_changed'],'HTP image did not change')
            require('KERNEL:23' not in baseline['_services'],'baseline already fused')
            require(candidate['_services']['KERNEL:23']['calls']==8,'fusion must execute eight times')
            require(baseline['_services']['KERNEL:0']['calls']-candidate['_services']['KERNEL:0']['calls']==16,
                    'expected sixteen separate update services removed')
            require(baseline['retired_instructions']-candidate['retired_instructions']==8,'unexpected retired delta')
            require(row['cycles_after']<row['cycles_before'],'fusion has no whole-program benefit')
        else:
            require(row['cycles_before']==row['cycles_after'],f'{algorithm}: unrelated cycle change')
            require(baseline['_services']==candidate['_services'],f'{algorithm}: unrelated profile change')
        row['cycles_saved'] = row['cycles_before']-row['cycles_after']
        row['timing'] = {}
        for name,case in (('before',baseline),('after',candidate)):
            profile = case['cycle_profile']
            row['timing'][name] = dict(total=case['job_cycles'],program=profile['program_done_clock'],
                result_drain=profile['result_drain_clocks'],accepted_frames=profile['accepted_frames'],
                fixture_non_job=case['fixture_non_job_cycles'],raw_setup_markers=case['raw_setup_markers'],
                fixture_total=case['cycles'],
                separate_setup_load_compute_stall_writeback=None)
        output.append(row)
    return dict(status='PASS',rows=rows,columns=64 if rows==32 else 256,cases=output,
                before_summary_sha256=evidence.digest(before_path),after_summary_sha256=evidence.digest(after_path),
                scope='Exact raw results, actual outer8, same source/policy and pinned inputs; only HTP fusion changes',
                ppa=None)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before',type=Path)
    parser.add_argument('after',type=Path)
    parser.add_argument('--rows',type=int,choices=(32,64),required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    result = compare(args.before,args.after,args.rows)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    for case in result['cases']:
        print(f"{case['algorithm']}: {case['cycles_before']} -> {case['cycles_after']} ({case['reduction_percent']:.3f}%)")

if __name__=='__main__':
    main()
