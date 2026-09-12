"""Run the unchanged fixed validation harness with guarded matrix conversion caching.

The entry point and cache implementation are added to executed-source hashes.
This changes Python study execution cost only, never FPGA/model arithmetic.
"""
from __future__ import annotations
import os
for _task_var in ('OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS', 'OMP_NUM_THREADS'):
    os.environ[_task_var] = '1'
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.v4 import lfsr_application_fixed_validation as harness
from scripts.v4 import fast_integer_study as accelerator
from scripts.v4.fast_integer_study_cached import cached_accelerated_arithmetic


def main():
    original_context = accelerator.accelerated_arithmetic
    original_hashes = harness.source_hashes
    original_ready = harness.json_ready
    def hashes(accelerated, wavelet):
        values = original_hashes(accelerated, wavelet)
        for path in (Path(__file__), ROOT/'scripts/v4/fast_integer_study_cached.py'):
            values[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        return values
    def ready(value):
        if isinstance(value, dict) and value.get('schema') == 'v4-lfsr-selected-fixed-application-v1':
            value = {**value,
                'execution_entrypoint': Path(__file__).relative_to(ROOT).as_posix(),
                'execution_backend': 'guarded_integer_primitives_with_bounded_immutable_matrix_conversion_cache',
                'cache_effect': 'Python_conversion_only_no_numeric_or_hardware_change'}
        return original_ready(value)
    if '--accelerated' not in sys.argv:
        sys.argv.append('--accelerated')
    accelerator.accelerated_arithmetic = cached_accelerated_arithmetic
    harness.source_hashes = hashes
    harness.json_ready = ready
    try:
        harness.main()
    finally:
        accelerator.accelerated_arithmetic = original_context
        harness.source_hashes = original_hashes
        harness.json_ready = original_ready


if __name__ == '__main__':
    main()
