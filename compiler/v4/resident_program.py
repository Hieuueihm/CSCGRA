"""Executable candidate resident GEMV images; separate from old demonstration templates."""
import json
from pathlib import Path
from compiler.v4.context_image import TileInstruction as T, ControlInstruction as C, pack_context
ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT/'config/v4_operator_exec.json').read_text())

def descriptor(**values):
    result, shift = 0, 0
    for name, width in CONFIG['descriptor_fields'].items():
        value = values[name]
        if not isinstance(value, int) or not 0 <= value < (1 << width):
            raise ValueError(f'{name} does not fit {width} bits')
        result |= value << shift
        shift += width
    if set(values) != set(CONFIG['descriptor_fields']):
        raise ValueError('unknown descriptor field')
    return result

def gemv(rows, cols, mode, trans, index=0, stride=1, address_mode='MATRIX'):
    if mode not in range(4) or not 1 <= rows <= 128 or not 1 <= cols <= (96 if mode >= 2 else 1024):
        raise ValueError('unsupported resident shape/mode')
    if mode < 2 and bool(trans) != bool(mode & 1):
        raise ValueError('Phi direction does not match mode')
    outputs, reductions = (cols, rows) if trans else (rows, cols)
    r4 = mode & 1
    blocks = (outputs+(7 if r4 else 31))//(8 if r4 else 32)
    frames = ((reductions+31)//32)*8 if r4 else reductions
    nop = [T()]*32
    tiles = [[T('CLEAR', acc_write=1)]*32, nop,
             [T('MAC', 'MATRIX', 'VECTOR', acc_write=1, format='FIXED')]*32, nop]
    controls = [C('LOOP_BEGIN', count=blocks, loop_target=1),
                C('LOOP_BEGIN', count=frames, loop_target=2),
                C('ADDRESS', address_mode=address_mode, immediate_address=index, stride=stride & 65535),
                C('LOOP_END', loop_target=1)]
    if r4:
        tiles += [[T('ROUTE', 'ACC', routeW='VALUE') if p%4 in (1,3) else T() for p in range(32)],
                  [T('ADD', 'ACC', 'LINK', srcB_reg=1, acc_write=1, format='FIXED') if p%4 in (0,2) else T() for p in range(32)],
                  [T('ROUTE', 'ACC', routeW='VALUE') if p%4 == 2 else T() for p in range(32)],
                  [T('ROUTE', 'LINK', srcA_reg=1, routeW='VALUE') if p%4 == 1 else T() for p in range(32)],
                  [T('ADD', 'ACC', 'LINK', srcB_reg=1, acc_write=1, format='FIXED') if p%4 == 0 else T() for p in range(32)]]
        controls += [C()]*5
    tiles += [[T('STORE', 'ACC') if not r4 or p%4 == 0 else T() for p in range(32)], nop, nop]
    controls += [C(), C('LOOP_END', loop_target=0), C('HALT')]
    return pack_context(tiles, controls, metadata=dict(
        scope='resident_execution_candidate_not_legacy_demo_or_job_commit',
        resident_revision=CONFIG['revision'], executable_words=len(tiles),
        rows=rows, cols=cols, mode=mode, trans=int(bool(trans))))
