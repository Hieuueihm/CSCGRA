"""Portable immutable golden-image guard for Step-1 mapping selection.

The fixture was recorded from the qualified five-non-QR, two-geometry,
auto/forced-R4 closure.  It is intentionally narrower than active10 fixed8
qualification and is never regenerated from the code under test.
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'verification/v4/fixtures/op8_mapping_image_compatibility.json'

EMIT = r'''import hashlib, json
import numpy as np
from compiler.v4.recovery_emit import compile_recovery
from models.v4.recovery import Policy
from models.v4.proximal import Policy as ProximalPolicy

def image(package):
    fields = {key: package[key] for key in ('program','templates','vectors','constants','load_records') if key in package}
    return hashlib.sha256(json.dumps(fields, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

rows=[]
for m,n in ((32,64),(64,256)):
    matrix=np.full((m,n), 1.0/1024.0)
    for r4 in (None,True):
        for algorithm in ('MP','GP','IHT'):
            package=compile_recovery(algorithm,matrix,Policy(8,max_iterations=8),r4=r4)
            rows.append(dict(algorithm=algorithm,m=m,n=n,r4=r4,image=image(package),
                             selected=[item['selected_r4'] for item in package['mapping_decisions']]))
        for algorithm in ('FISTA','PDHG'):
            package=compile_recovery(algorithm,matrix,ProximalPolicy(max_iterations=8,inner_max_iterations=24),r4=r4)
            rows.append(dict(algorithm=algorithm,m=m,n=n,r4=r4,image=image(package),
                             selected=[item['selected_r4'] for item in package['mapping_decisions']]))
print(json.dumps(rows,sort_keys=True))
'''


class MappingSelectionImageCompatibilityTests(unittest.TestCase):
    def test_qualified_twenty_image_fixture_is_immutable_and_matches(self):
        fixture = json.loads(FIXTURE.read_text(encoding='utf-8'))
        self.assertEqual(fixture['status'], 'PASS')
        expected = fixture['fixtures']
        self.assertEqual(len(expected), 20)
        result = subprocess.run([sys.executable, '-X', 'utf8', '-c', EMIT], cwd=ROOT,
                                text=True, capture_output=True, check=False, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), expected)


if __name__ == '__main__':
    unittest.main()
