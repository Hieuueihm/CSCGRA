"""Independent full-size replay check for the one-copy research prototype."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
source_path = ROOT/'compiler/v4/single_matrix.py'
source_sha256 = hashlib.sha256(source_path.read_bytes()).hexdigest()
from compiler.v4.single_matrix import compile_single_matrix, replay_gemv

rows = []
for m, n in ((128, 1024), (128, 8), (128, 32), (128, 96)):
    a = [[((i*37+j*11+i*j)%31)-15 for j in range(n)] for i in range(m)]
    for transpose in (False, True):
        v = [((i*7)%17)-8 for i in range(m if transpose else n)]
        if transpose:
            expected = [sum(a[i][j]*v[i] for i in range(m)) for j in range(n)]
        else:
            expected = [sum(a[i][j]*v[j] for j in range(n)) for i in range(m)]
        for lanes in (1, 4):
            schedule = compile_single_matrix(m, n, transpose=transpose, reduction_lanes=lanes)
            result = replay_gemv(schedule, a, v)
            assert result == expected
            rows.append(dict(m=m, n=n, transpose=transpose, reduction_lanes=lanes,
                             exact_integer_match=True, accumulator_bits=64,
                             output_sha256=hashlib.sha256(json.dumps(result).encode()).hexdigest()))
assert hashlib.sha256(source_path.read_bytes()).hexdigest() == source_sha256, 'Source changed during validation'
report = dict(status="INTEGER_BANK_REPLAY_ONLY_NO_RTL_PIPELINE_OR_APPLICATION_QUALITY_PROOF",
              cases=rows, count=len(rows),
              source_sha256=source_sha256,
              validation_script="scripts/v4/single_matrix_validation.py",
              validation_script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
(ROOT/'reports/v4/single_matrix_replay_validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"{len(rows)} full-size/restricted bank and prefix-checked integer replays match independent sums")
