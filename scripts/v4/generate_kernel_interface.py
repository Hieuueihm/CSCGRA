"""Generate shared kernel opcodes, faults and support flags from JSON."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def render():
    abi = json.loads((ROOT / 'config/v4_kernel_interface.json').read_text())
    values = {'REVISION': abi['revision']}
    for prefix, field in [('OP', 'operations'), ('FAULT', 'faults'),
                          ('STORE', 'store_modes'), ('SUPPORT_DETAIL', 'support_details')]:
        values.update({f'{prefix}_{name}': value for name, value in abi[field].items()})
    for op, flags in abi['support_flags'].items():
        values.update({f'{op}_{name}': value for name, value in flags.items()})
    values.update({f'PROJECT_{name.upper()}': value
                   for name, value in abi.get('factor_project_phase', {}).items()})
    return '\n'.join(['`ifndef CSR_KERNEL_INTERFACE_VH', '`define CSR_KERNEL_INTERFACE_VH',
                      *[f'`define CSR_KERNEL_{key} {value}' for key, value in values.items()],
                      '`endif', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = ROOT / 'rtl/v4/include/kernel_interface.vh'
    expected = render()
    if args.check:
        if not path.is_file() or path.read_text() != expected:
            raise SystemExit('kernel_interface.vh stale or missing')
    else:
        path.write_text(expected)


if __name__ == '__main__':
    main()
