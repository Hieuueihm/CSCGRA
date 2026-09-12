"""Archive verified numerical-study source bundles without changing results."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def archive(report_path):
    report=json.loads(report_path.read_text(encoding='utf-8'))
    sources=report.get('source_sha256', report.get('source_sha256_at_start'))
    if not sources: raise ValueError('report has no executed source hashes')
    bundle_id=hashlib.sha256(json.dumps(sources,sort_keys=True).encode()).hexdigest()
    destination=ROOT/'reports/v4/source_snapshots'/bundle_id
    for relative,expected in sources.items():
        source=(ROOT/relative).resolve()
        if not source.is_relative_to(ROOT): raise ValueError('source outside workspace')
        payload=source.read_bytes()
        if hashlib.sha256(payload).hexdigest()!=expected: raise ValueError('source changed: '+relative)
        target=destination/relative
        if target.exists() and target.read_bytes()!=payload: raise ValueError('snapshot collision')
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(payload)
    manifest={'bundle_id':bundle_id,'source_sha256':sources,'purpose':'exact executed numerical source; no credentials or dataset payload'}
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(report_path.name,'->',destination.relative_to(ROOT).as_posix())


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reports',nargs='+',type=Path)
    for path in parser.parse_args().reports: archive(path)
