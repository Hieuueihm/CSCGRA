"""Pure equivalence check for the analytic RANGE provider plan.

This is not an RTL acceptance test.  It compares the new closed-form planner and
common-offset reconstruction with the former first-used lane scan over legal
SLICE/REPLACE_RANGE intervals, including physical source/aux aliases.
"""
import random
import unittest

LANES = 32


def span(first, count):
    return sum(1 << lane for lane in range(first, min(LANES, first + count)))


def scan_plan(op, length, start, aux_length, source_base, aux_base, block):
    output_length = aux_length if op == 'slice' else length
    result = []
    for lane in range(LANES):
        output = block * LANES + lane
        if output >= output_length:
            continue
        if op == 'slice':
            index, address = start + output, source_base + (start + output) // LANES
        elif start <= output < start + aux_length:
            index, address = output - start, aux_base + (output - start) // LANES
        else:
            index, address = output, source_base + output // LANES
        mask = 1 << (index % LANES)
        for item in result:
            if item[0] == address:
                item[1] |= mask
                break
        else:
            result.append([address, mask])
    return [(address, mask) for address, mask in result]


def analytic_plan(op, length, start, aux_length, source_base, aux_base, block):
    output_length = aux_length if op == 'slice' else length
    block_start = block * LANES
    valid = min(LANES, max(0, output_length - block_start))
    if not valid:
        return []
    logical = []
    if op == 'slice':
        absolute = start + block_start
        offset = absolute % LANES
        first = min(valid, LANES - offset)
        logical.append((source_base + absolute // LANES, span(offset, first)))
        if valid != first:
            logical.append((source_base + absolute // LANES + 1, span(0, valid - first)))
    else:
        replacement_begin = max(block_start, start)
        replacement_end = min(block_start + valid, start + aux_length)
        replacement = max(0, replacement_end - replacement_begin)
        replacement_lane = replacement_begin - block_start if replacement else 0
        pre = replacement_lane
        post = valid - pre - replacement
        source_mask = span(0, pre) | span(replacement_lane + replacement, post)
        if replacement:
            auxiliary_index = replacement_begin - start
            auxiliary_offset = auxiliary_index % LANES
            first = min(replacement, LANES - auxiliary_offset)
            aux_first = (aux_base + auxiliary_index // LANES, span(auxiliary_offset, first))
            aux_second = (aux_base + auxiliary_index // LANES + 1, span(0, replacement - first))
        if pre:
            logical.append((source_base + block, source_mask))
            if replacement:
                logical.append(aux_first)
                if replacement != first:
                    logical.append(aux_second)
        elif replacement:
            logical.append(aux_first)
            if replacement != first:
                logical.append(aux_second)
                if post:
                    logical.append((source_base + block, source_mask))
            elif post:
                logical.append((source_base + block, source_mask))
        else:
            logical.append((source_base + block, source_mask))
    compact = []
    for address, mask in logical:
        if not mask:
            continue
        for item in compact:
            if item[0] == address:
                item[1] |= mask
                break
        else:
            compact.append([address, mask])
    assert len(compact) <= 3
    return [(address, mask) for address, mask in compact]


def reconstructed_output(op, length, start, aux_length, source_base, aux_base, block, memory):
    output_length = aux_length if op == 'slice' else length
    block_start = block * LANES
    valid = min(LANES, max(0, output_length - block_start))
    if not valid:
        return []
    if op == 'slice':
        absolute = start + block_start
        first_address, offset = source_base + absolute // LANES, absolute % LANES
        stream = memory[first_address][offset:] + memory.get(first_address + 1, [0] * LANES)
        return stream[:valid]
    replacement_begin, replacement_end = max(block_start, start), min(block_start + valid, start + aux_length)
    replacement = max(0, replacement_end - replacement_begin)
    replacement_lane = replacement_begin - block_start if replacement else 0
    output = list(memory[source_base + block])[:valid]
    if replacement:
        auxiliary_index = replacement_begin - start
        address, offset = aux_base + auxiliary_index // LANES, auxiliary_index % LANES
        stream = memory[address][offset:] + memory.get(address + 1, [0] * LANES)
        output[replacement_lane:replacement_lane + replacement] = stream[:replacement]
    return output


def scanned_output(op, length, start, aux_length, source_base, aux_base, block, memory):
    output_length = aux_length if op == 'slice' else length
    out = []
    for lane in range(LANES):
        index = block * LANES + lane
        if index >= output_length:
            break
        if op == 'slice':
            physical = start + index
            out.append(memory[source_base + physical // LANES][physical % LANES])
        elif start <= index < start + aux_length:
            physical = index - start
            out.append(memory[aux_base + physical // LANES][physical % LANES])
        else:
            out.append(memory[source_base + index // LANES][index % LANES])
    return out


class AnalyticRangePlanTests(unittest.TestCase):
    def check_case(self, op, length, start, aux_length, source_base, aux_base):
        memory = {address: [address * 131 + lane * 17 - 20000 for lane in range(LANES)]
                  for address in range(480)}
        output_length = aux_length if op == 'slice' else length
        for block in range((output_length + LANES - 1) // LANES):
            self.assertEqual(
                analytic_plan(op, length, start, aux_length, source_base, aux_base, block),
                scan_plan(op, length, start, aux_length, source_base, aux_base, block),
            )
            self.assertEqual(
                reconstructed_output(op, length, start, aux_length, source_base, aux_base, block, memory),
                scanned_output(op, length, start, aux_length, source_base, aux_base, block, memory),
            )

    def test_boundaries_full_domain_and_aliases(self):
        lengths = (1, 2, 31, 32, 33, 63, 64, 65, 95, 96, 97, 127, 128, 1023, 1024)
        for length in lengths:
            blocks = (length + 31) // 32
            source_base = 480 - blocks
            for start in sorted({0, 1, 31, 32, 33, length // 2, max(0, length - 1), length}):
                if start > length:
                    continue
                for aux_length in sorted({0, 1, 31, 32, 33, max(0, length - start), min(65, length - start)}):
                    if aux_length > length - start:
                        continue
                    aux_blocks = (max(aux_length, 1) + 31) // 32
                    for aux_base in (0, source_base, 480 - aux_blocks):
                        self.check_case('slice', length, start, aux_length, source_base, aux_base)
                        self.check_case('replace', length, start, aux_length, source_base, aux_base)

    def test_random_legal_intervals(self):
        rng = random.Random(20260909)
        for _ in range(4000):
            length = rng.randint(1, 1024)
            start = rng.randint(0, length)
            aux_length = rng.randint(0, length - start)
            source_blocks = (length + 31) // 32
            aux_blocks = (max(aux_length, 1) + 31) // 32
            source_base = rng.choice((0, rng.randint(0, 480 - source_blocks), 480 - source_blocks))
            aux_base = rng.choice((source_base, 0, rng.randint(0, 480 - aux_blocks), 480 - aux_blocks))
            self.check_case('slice', length, start, aux_length, source_base, aux_base)
            self.check_case('replace', length, start, aux_length, source_base, aux_base)


if __name__ == '__main__':
    unittest.main()
