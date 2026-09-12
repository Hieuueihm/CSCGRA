"""Copy a completed fixed-eight report without simulator binaries.

The compact archive retains every artifact used to re-hash source execution,
match packages/load images, replay traces, and inspect executed xsim commands.
It deliberately never copies xsim work libraries or other generated binaries.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ArchiveError(ValueError):
    pass


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise ArchiveError(f'invalid JSON {path}: {error}') from error


def copy_file(source, destination, copied):
    if not source.is_file():
        raise ArchiveError(f'missing required artifact: {source}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if digest(source) != digest(destination):
        raise ArchiveError(f'copy hash mismatch: {source}')
    copied.append({'path': destination.as_posix(), 'sha256': digest(destination), 'bytes': destination.stat().st_size})


def validate_summary(report):
    summary_path = report / 'summary.json'
    summary = load_json(summary_path)
    if summary.get('status') != 'PASS' or summary.get('failures') != 0 or summary.get('errors') != 0:
        raise ArchiveError('only completed PASS reports can be archived')
    if summary.get('changed_sources') != [] or summary.get('untracked_imports') != []:
        raise ArchiveError('source closure is not explicitly clean')
    sources = summary.get('source_sha256')
    if not isinstance(sources, dict) or not sources:
        raise ArchiveError('source hash manifest is absent')
    snapshot = report / 'source_snapshot'
    for name, expected in sources.items():
        path = snapshot / name
        if not path.is_file() or digest(path) != expected:
            raise ArchiveError(f'source snapshot mismatch: {name}')
    cases = summary.get('cases')
    if not isinstance(cases, list) or not cases:
        raise ArchiveError('case list is absent')
    return summary, snapshot


def archive(report, output):
    report = report.resolve()
    output = output.resolve()
    if output.exists():
        raise ArchiveError(f'output already exists: {output}')
    summary, snapshot = validate_summary(report)
    execution = sorted(report.glob('recovery_algorithms*/evidence.json'))
    if len(execution) != 1:
        raise ArchiveError(f'expected one execution evidence file, found {len(execution)}')
    evidence_path = execution[0]
    evidence = load_json(evidence_path)
    cases = summary['cases']
    if len(evidence) != len(cases):
        raise ArchiveError('summary/evidence case count mismatch')
    output.mkdir(parents=True)
    copied = []
    # Keep report-level provenance before copying the execution leaf.
    for name in ('summary.json', 'focused_summary.json', 'evidence.json', 'executed_manifest.json',
                 'numerical_preflight.json', 'snapshot_manifest.json'):
        source = report / name
        if source.is_file():
            copy_file(source, output / name, copied)
    for source in snapshot.rglob('*'):
        if source.is_file():
            copy_file(source, output / 'source_snapshot' / source.relative_to(snapshot), copied)
    execution_root = evidence_path.parent
    copy_file(evidence_path, output / execution_root.name / 'evidence.json', copied)
    for index, case in enumerate(cases):
        if evidence[index].get('algorithm') != case.get('algorithm'):
            raise ArchiveError(f'case order differs at {index}')
        for name, expected in ((f'case{index}.txt', case.get('fixture_sha256')),
                               (f'trace{index}.txt', case.get('trace_sha256')),
                               (f'package{index}/package.json', case.get('package_sha256'))):
            source = execution_root / name
            if not source.is_file() or digest(source) != expected:
                raise ArchiveError(f'{case.get("algorithm")}: mismatched {name}')
            copy_file(source, output / execution_root.name / name, copied)
        simulation = execution_root / f'simulation{index}.json'
        copy_file(simulation, output / execution_root.name / simulation.name, copied)
        package = execution_root / f'package{index}'
        # package.json carries the executable word list; load.txt gives its
        # normalized executable digest. Keep optional emitted images too.
        for name in ('load.txt', 'program.hex', 'templates.hex', 'constants.hex'):
            source = package / name
            if source.is_file():
                copy_file(source, output / execution_root.name / f'package{index}' / name, copied)
    manifest = {
        'schema': 1,
        'status': 'PASS',
        'source_report': str(report),
        'source_summary_sha256': digest(report / 'summary.json'),
        'source_snapshot_file_count': len(summary['source_sha256']),
        'case_count': len(cases),
        'copied_files': copied,
        'excluded': ['xsim.dir', '.Xil', 'webtalk', 'xsim binaries and journals'],
    }
    (output / 'archive_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'PASS archived {len(cases)} cases and {len(copied)} files -> {output}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(argv)
    archive(args.report, args.output)


if __name__ == '__main__':
    main()
