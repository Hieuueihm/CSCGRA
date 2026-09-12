"""Generate native recovery and result-store definitions from their authority."""
import argparse
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]


def render():
    abi = json.loads((ROOT / 'config/v4_recovery_interface.json').read_text())
    values = {'REVISION': abi['revision']}
    for prefix, field in [('FAULT', 'faults'), ('RESULT_FAULT', 'result_faults'),
                          ('LIMIT', 'limits'), ('STORE', 'storage_modes')]:
        values.update({f'{prefix}_{key}': value for key, value in abi[field].items()})
    return '\n'.join(['`ifndef CSR_RECOVERY_INTERFACE_VH', '`define CSR_RECOVERY_INTERFACE_VH',
                      *[f'`define CSR_RECOVERY_{key} {value}' for key, value in values.items()], '`endif', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = ROOT / 'rtl/v4/include/recovery_interface.vh'
    if args.check:
        if not path.is_file() or path.read_text() != render():
            raise SystemExit('recovery_interface.vh stale or missing')
    else:
        path.write_text(render())


if __name__ == '__main__':
    main()
