"""Export a complete native recovery program and verified loader records.

Input JSON: algorithm, policy, and an LFSR operator descriptor
{kind:"lfsr32", seed, rows, columns, scale_raw}. No host iteration schedule is
generated. Measurements and operator publication remain the native host's job.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v4.greedy_qr_emit import ALGORITHMS as QR_ALGORITHMS, compile_greedy_qr
from compiler.v4.recovery_emit import compile_recovery
from compiler.v4.recovery_program import export_package
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.proximal import ALGORITHMS as PROXIMAL_ALGORITHMS, Policy as ProximalPolicy
from models.v4.recovery import Policy


def compile_spec(spec, *, qr_profile='balanced', qr_panel_min_columns=8, target_kernel_revision=2,
                 sparse_forward=None, operand_chains=False, factor_range_template=False,
                 factor_energy_tap=False, outer_fusion=False):
    if type(outer_fusion) is not bool:
        raise ValueError('outer_fusion must be boolean')
    if not isinstance(operand_chains, bool):
        raise ValueError('operand_chains must be boolean')
    if not isinstance(factor_range_template, bool):
        raise ValueError('factor_range_template must be boolean')
    if not isinstance(factor_energy_tap, bool):
        raise ValueError('factor_energy_tap must be boolean')
    if not isinstance(spec.get('operator'), dict) or 'matrix' in spec:
        raise ValueError('Provide a live LFSR operator descriptor; arbitrary matrix preload is not implemented by this native host')
    operator = spec.get('operator')
    if operator is not None:
        if operator.get('kind') != 'lfsr32':
            raise ValueError('Only the existing lfsr32 live operator is supported')
        rows, cols, scale, seed = (operator[k] for k in ('rows', 'columns', 'scale_raw', 'seed'))
        if any(type(v) is not int for v in (rows, cols, scale, seed)):
            raise ValueError('LFSR descriptor fields must be integers')
        if not (1 <= rows <= 128 and 1 <= cols <= 1024 and 0 < scale < (1 << 17) and 0 < seed < (1 << 32)):
            raise ValueError('LFSR descriptor is outside the native operator bounds')
        matrix = np.asarray(lfsr32_matrix(seed, rows, cols, scale=scale), dtype=float) / 65536
    algorithm = spec['algorithm']
    policy = (ProximalPolicy if algorithm in PROXIMAL_ALGORITHMS else Policy)(**spec['policy'])
    r4 = spec.get('r4')
    sparse = spec.get('sparse_forward', False) if sparse_forward is None else sparse_forward
    if algorithm in QR_ALGORITHMS:
        if sparse:
            raise ValueError('sparse_forward selects the MP/GP/IHT compiler path only')
        package = compile_greedy_qr(algorithm, matrix, policy, r4=r4,
            max_refinements=spec.get('qr_max_refinements', 2), qr_profile=qr_profile,
            qr_panel_min_columns=qr_panel_min_columns, operand_chains=operand_chains,
            factor_range_template=factor_range_template,
            factor_energy_tap=factor_energy_tap, outer_fusion=outer_fusion)
    else:
        if outer_fusion:
            raise ValueError('outer_fusion selects the QR outer compiler path only')
        package = compile_recovery(algorithm, matrix, policy, r4=r4, sparse_forward=sparse,
                                   operand_chains=operand_chains)
    if type(target_kernel_revision) is not int or target_kernel_revision not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10):
        raise ValueError('Target kernel revision must be1..10')
    if package['required_kernel_revision'] > target_kernel_revision:
        raise ValueError('Selected QR profile requires a newer kernel revision')
    package['target_kernel_revision'] = target_kernel_revision
    package['operator_descriptor'] = operator
    package['export_scope'] = 'Complete loadable program; native host must publish matching Phi and preload the measurement descriptor before START. No quality-policy tuning or host loop schedule.'
    return package


def export_spec(source, output, **options):
    source, output = Path(source), Path(output)
    payload = source.read_bytes()
    package = compile_spec(json.loads(payload), **options)
    package['input_spec_sha256'] = hashlib.sha256(payload).hexdigest()
    package['exporter_source_sha256'] = {
        name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        for name in ('scripts/v4/export_recovery.py', 'compiler/v4/greedy_qr_emit.py',
                     'compiler/v4/qr_program.py', 'compiler/v4/recovery_emit.py',
                     'compiler/v4/live_mapping.py', 'config/v4_gemv_mapping_calibration.json')}
    metadata = export_package(package, output)
    # The canonical stream checksum is over LF bytes. Explicit binary writing
    # avoids Windows text-mode CRLF translation without changing its records.
    load_path = output / 'load.txt'
    load_path.write_bytes(load_path.read_text().encode('utf-8'))
    if hashlib.sha256(load_path.read_bytes()).hexdigest() != metadata['load_sha256']:
        raise RuntimeError('Exported loader bytes do not match the canonical checksum')
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--qr-profile', choices=('reference', 'balanced', 'panel', 'reuse', 'resident', 'compact', 'streamed', 'view'), default='balanced',
                        help='QR schedule; reuse is explicit revision4 OMP/GOMP prefix extension; resident is explicit feature5 private factor projection; compact uses feature6 scalar insertion in backsolve; streamed additionally uses feature6 scalar insertion for QR reflector tau, beta, and head publication')
    parser.add_argument('--qr-panel-min-columns', type=int, default=8,
                        help='Explicit panel threshold, 1..96; the selected profile emits panels only when its policy can reach a wider trailing rectangle')
    parser.add_argument('--target-kernel-revision', type=int, choices=(1, 2, 3, 4, 5, 6, 7, 8, 9, 10), default=2)
    parser.add_argument('--factor-range-template', action=argparse.BooleanOptionalAction, default=False,
                        help='Opt-in feature9 QR view lowering: factor-range raw DOT plus candidate tap')
    parser.add_argument('--factor-energy-tap', action=argparse.BooleanOptionalAction, default=False,
                        help='Opt-in feature10 QR view reflector statistic/tap lowering')
    parser.add_argument('--operand-chains', action=argparse.BooleanOptionalAction, default=False,
                        help='Explicit feature8 non-QR ROUNDED_AFFINE selection; defaults to the legacy separate SCALE then ADD/SUB image')
    parser.add_argument('--outer-fusion', action=argparse.BooleanOptionalAction, default=False,
                        help='Opt-in feature8 rounded HTP outer update; inner QR remains unchanged')
    parser.add_argument('--sparse-forward', action=argparse.BooleanOptionalAction, default=None,
                        help='Explicit MP/GP/IHT sparse-forward selection; otherwise use the input JSON field')
    args = parser.parse_args()
    metadata = export_spec(args.source, args.output, qr_profile=args.qr_profile,
                          qr_panel_min_columns=args.qr_panel_min_columns,
                          target_kernel_revision=args.target_kernel_revision, sparse_forward=args.sparse_forward,
                          operand_chains=args.operand_chains, outer_fusion=args.outer_fusion, factor_range_template=args.factor_range_template,
                          factor_energy_tap=args.factor_energy_tap)
    print(json.dumps(dict(algorithm=metadata['algorithm'], program_words=len(metadata['program']),
                         templates=len(metadata['templates']), vectors=len(metadata['vectors']),
                         qr_profile=metadata.get('qr_execution_profile'),
                         required_kernel_revision=metadata['required_kernel_revision'],
                         load_sha256=metadata['load_sha256'], output=str(args.output.resolve())), indent=2))


if __name__ == '__main__':
    main()

