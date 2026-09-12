"""Address planning for the existing live Phi and paired dense-B memories."""


def _shape(rows, columns, dense):
    if type(rows) is not int or not 1 <= rows <= 128:
        raise ValueError('rows must be 1..128')
    if type(dense) is not bool:
        raise ValueError('dense must be boolean')
    if type(columns) is not int or not 1 <= columns <= (96 if dense else 1024):
        raise ValueError('columns outside the physical memory shape')


def layout_descriptor(rows, columns, dense=False):
    if type(dense) is not bool:
        raise ValueError('dense must be boolean')
    if dense and columns is None:
        _shape(rows, 1, True)
    else:
        _shape(rows, columns, dense)
    return dict(storage='paired_dense_b' if dense else 'compact_phi_sign', rows=rows,
                columns=columns, width_source='runtime_support' if columns is None else 'static',
                layout_fixed_by_rtl=True, logical_banks=32 if dense else 8,
                physical_memories=16 if dense else 8,
                logical_word_bits=18 if dense else 32,
                bank_formula='(row+column)%32' if dense else 'column%8',
                address_formula='row*ceil(S/32)+column//32' if dense else 'column//8*ceil(M/32)+row//32',
                bit_formula=None if dense else 'row%32',
                physical_port_formula='logical_bank//16' if dense else None,
                physical_address_formula='port*512+logical_address' if dense else 'logical_address',
                transpose_repacking=False)


def coefficient_address(rows, columns, row, column, dense=False):
    _shape(rows, columns, dense)
    if type(row) is not int or type(column) is not int or not (0 <= row < rows and 0 <= column < columns):
        raise ValueError('coefficient outside matrix')
    if dense:
        bank = (row + column) % 32
        address = row * ((columns + 31) // 32) + column // 32
        return dict(bank=bank, address=address, bit=None, memory=bank % 16,
                    port=bank // 16, physical_address=(bank // 16) * 512 + address)
    bank = column % 8
    address = (column // 8) * ((rows + 31) // 32) + row // 32
    return dict(bank=bank, address=address, bit=row % 32, memory=bank,
                port=0, physical_address=address)


def frame_plan(rows, columns, *, r4, transpose=False, dense=False,
               output_base=0, reduction_base=0, step=0):
    _shape(rows, columns, dense)
    if type(r4) is not bool or type(transpose) is not bool:
        raise ValueError('r4 and transpose must be boolean')
    outputs, reductions = (columns, rows) if transpose else (rows, columns)
    if any(type(value) is not int for value in (output_base, reduction_base, step)):
        raise ValueError('frame coordinates must be integers')
    if not 0 <= output_base < outputs or not 0 <= reduction_base < reductions:
        raise ValueError('frame base outside shape')
    if output_base % (8 if r4 else 32) or (r4 and reduction_base % 32):
        raise ValueError('misaligned frame base')
    if not 0 <= step < 8 or (not r4 and step != 0):
        raise ValueError('invalid R1/R4 step')
    lanes = []
    requests = {}
    mask = 0
    for lane in range(32):
        output = output_base + (lane // 4 if r4 else lane)
        reduction = reduction_base + (8 * (lane % 4) + step if r4 else 0)
        if output >= outputs or reduction >= reductions:
            continue
        row, column = (reduction, output) if transpose else (output, reduction)
        address = coefficient_address(rows, columns, row, column, dense)
        pass_index = (lane % 4 if r4 else lane // 8) if not dense and r4 != transpose else 0
        key = (pass_index, address['bank'])
        if key in requests and requests[key]['address'] != address['address']:
            raise ValueError('two addresses target the same bank in one feeder pass')
        if key not in requests:
            requests[key] = dict(pass_index=pass_index, **address, lanes=[])
        requests[key]['lanes'].append(lane)
        lanes.append(dict(lane=lane, output=output, reduction=reduction, row=row, column=column,
                          pass_index=pass_index, **address))
        mask |= 1 << lane
    passes = sorted({key[0] for key in requests})
    return dict(r4=r4, transpose=transpose, dense=dense, output_base=output_base,
                reduction_base=reduction_base, step=step, lane_mask=mask, lanes=lanes,
                requests=list(requests.values()), active_passes=len(passes),
                scope='Logical feeder bank passes; runtime tile-cache coalescing and stalls excluded')


def frame_schedule(rows, columns, *, r4, transpose=False, dense=False):
    _shape(rows, columns, dense)
    if type(r4) is not bool or type(transpose) is not bool:
        raise ValueError('r4 and transpose must be boolean')
    outputs, reductions = (columns, rows) if transpose else (rows, columns)
    for output in range(0, outputs, 8 if r4 else 32):
        for reduction in range(0, reductions, 32 if r4 else 1):
            for step in range(min(8, reductions - reduction) if r4 else 1):
                yield frame_plan(rows, columns, r4=r4, transpose=transpose, dense=dense,
                                 output_base=output, reduction_base=reduction, step=step)
