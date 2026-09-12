"""Check current compiler image compatibility across all active algorithms."""
import hashlib
import json
from pathlib import Path
import unittest

import numpy as np
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import compile_recovery
from models.v4.proximal import Policy as ProximalPolicy
from models.v4.recovery import Policy

ALGORITHMS = ('MP', 'OMP', 'GOMP', 'CoSaMP', 'SP', 'IHT', 'HTP', 'GP', 'FISTA', 'PDHG')
QR = ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP')
FIXTURE = Path(__file__).parent / 'fixtures/live_mapping_images.json'


def images():
    rows = []
    for height, width in ((32, 64), (64, 256)):
        matrix = np.full((height, width), 1.0 / 1024.0)
        for algorithm in ALGORITHMS:
            policy = ProximalPolicy(max_iterations=8) if algorithm in ('FISTA', 'PDHG') else Policy(8, max_iterations=8)
            for override in (None, False, True):
                package = (compile_greedy_qr(algorithm, matrix, policy, r4=override, qr_profile='view', factor_range_template=True, factor_energy_tap=True)
                           if algorithm in QR else compile_recovery(algorithm, matrix, policy, r4=override, operand_chains=True))
                binary = {name: package[name] for name in ('program', 'templates', 'vectors', 'constants')}
                digest = hashlib.sha256(json.dumps(binary, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
                rows.append(dict(algorithm=algorithm, rows=height, columns=width, r4=override, sha256=digest))
    return rows


class LiveMappingImageTests(unittest.TestCase):
    def test_sixty_images_unchanged_by_bank_metadata(self):
        expected = json.loads(FIXTURE.read_text())
        self.assertEqual(len(expected['images']), 60)
        self.assertEqual(images(), expected['images'])


if __name__ == '__main__':
    unittest.main()
