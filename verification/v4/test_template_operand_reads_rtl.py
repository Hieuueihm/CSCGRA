"""Template operand-read regressions for unused and scalar-bound sources."""
import hashlib
import random
import re
import unittest

from verification.v4 import test_stream_kernel_rtl as base


RUNS = base.RUNS


def b_only_fixture(values, scalar=37, cancel=0, source_missing=False):
    """MUL with A scalar-bound and B sourced from the normal B base (64)."""
    lines = base.fixture(op=0, length=len(values), scalar=scalar, values=values,
                         context=296, cancel=cancel).splitlines()
    header = lines[0].split()
    frames = (len(values) + 31) // 32
    header[11] = 'ffffffff'  # A is scalar-bound; no A vector read is valid.
    header[12] = '0'         # B remains a vector source.
    header[13] = '7'         # Both vector address increments are explicit.
    writes = int(header[20])
    reads = int(header[21])
    data_start = 1 + int(header[22])
    write_lines = lines[data_start:data_start + writes]
    read_lines = lines[data_start + writes:data_start + writes + reads]
    b_writes = []
    for block in range(frames):
        if source_missing and block + 1 == frames:
            continue
        part = values[block * 32:(block + 1) * 32]
        b_writes.append(f'{64 + block} {(1 << len(part)) - 1:x} {base.pack(part):x}')
    result = [base.rounded(scalar * value, 22) for value in values]
    fault = 5 if source_missing else 0
    header[16] = str(fault)
    header[18] = str(int(any(result)) if not fault else 0)
    expected = []
    for block in range(frames):
        part = result[block * 32:(block + 1) * 32]
        invalid = cancel or fault
        expected.append(f'{128 + block} {(1 << len(part)) - 1:x} {2 if invalid else 0} {0 if invalid else base.pack(part):x}')
    header[20] = str(writes + len(b_writes))
    return '\n'.join([' '.join(header), *lines[1:data_start], *write_lines, *b_writes, *expected])


def mixed_fixture(a_values, b_values):
    """MUL with two distinct vector sources, retaining the legacy two-read path."""
    lines = base.fixture(op=0, length=len(a_values), values=a_values,
                         context=296).splitlines()
    header = lines[0].split()
    frames = (len(a_values) + 31) // 32
    header[11] = '0'
    header[12] = '0'
    header[13] = '7'
    writes = int(header[20])
    data_start = 1 + int(header[22])
    write_lines = lines[data_start:data_start + writes]
    b_writes = []
    for block in range(frames):
        part = b_values[block * 32:(block + 1) * 32]
        b_writes.append(f'{64 + block} {(1 << len(part)) - 1:x} {base.pack(part):x}')
    result = [base.rounded(left * right, 22) for left, right in zip(a_values, b_values)]
    expected = []
    for block in range(frames):
        part = result[block * 32:(block + 1) * 32]
        expected.append(f'{128 + block} {(1 << len(part)) - 1:x} 0 {base.pack(part):x}')
    header[20] = str(writes + len(b_writes))
    header[18] = str(int(any(result)))
    return '\n'.join([' '.join(header), *lines[1:data_start], *write_lines, *b_writes, *expected])


def alias_fixture(values):
    """MUL with both operands reading the same physical vector blocks."""
    lines = base.fixture(op=0, length=len(values), values=values,
                         context=296).splitlines()
    header = lines[0].split()
    frames = (len(values) + 31) // 32
    header[11] = '0'
    header[12] = '0'
    header[13] = '7'
    # The focused TB maps this nonzero test-only pair to req_src_a/req_src_b.
    header[27] = '10'
    header[28] = '10'
    writes = int(header[20])
    data_start = 1 + int(header[22])
    write_lines = []
    for line in lines[data_start:data_start + writes]:
        fields = line.split()
        if int(fields[0]) < frames:
            fields[0] = str(10 + int(fields[0]))
        write_lines.append(' '.join(fields))
    result = [base.rounded(value * value, 22) for value in values]
    expected = []
    for block in range(frames):
        part = result[block * 32:(block + 1) * 32]
        expected.append(f'{128 + block} {(1 << len(part)) - 1:x} 0 {base.pack(part):x}')
    header[18] = str(int(any(result)))
    return '\n'.join([' '.join(header), *lines[1:data_start], *write_lines, *expected])


def immediate_zero_fixture(length=65, immediate=37):
    """MOV immediate with a ZERO B operand: neither vector source is read."""
    lines = base.fixture(op=0, length=length, values=[11] * length,
                         context=296).splitlines()
    header = lines[0].split()
    context = 1 | (2 << 6) | (3 << 8) | (immediate << 10)  # MOV IMM, ZERO
    header[11] = '0'
    header[12] = '0'
    header[25] = f'{base.pack([context] * 32, 64):x}'
    header[18] = '1' if immediate else '0'
    writes = int(header[20])
    data_start = 1 + int(header[22])
    write_lines = lines[data_start:data_start + writes]
    frames = (length + 31) // 32
    expected = []
    for block in range(frames):
        part = [immediate] * min(32, length - block * 32)
        expected.append(f'{128 + block} {(1 << len(part)) - 1:x} 0 {base.pack(part):x}')
    return '\n'.join([' '.join(header), *lines[1:data_start], *write_lines, *expected])


class TemplateOperandReadTests(unittest.TestCase):
    setUpClass = classmethod(base.StreamKernelRtlTests.setUpClass.__func__)

    def replay(self, fixtures, expected_reads=None):
        """Run with injected RAM stalls and check actual RUN-state read traffic."""
        file = self.folder / (self._testMethodName + '.txt')
        file.write_text(str(len(fixtures)) + '\n' + '\n'.join(fixtures) + '\n')
        result = base.run_rtl(self.binary,
                              ['vectors=' + file.as_posix(), 'request_stalls=1'],
                              root=base.ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        match = re.search(r'PASS stream_kernel cycles=(\d+) checks=(\d+) commands=(\d+) stalls=(\d+)',
                          result.stdout)
        self.assertIsNotNone(match, result.stdout)
        _, _, commands, stalls = map(int, match.groups())
        self.assertEqual(commands, len(fixtures))
        self.assertGreater(stalls, 0)
        reads = [int(value) for value in re.findall(r'TEMPLATE_READS case=\d+ reads=(\d+)', result.stdout)]
        self.assertEqual(len(reads), len(fixtures), result.stdout)
        if expected_reads is not None:
            self.assertEqual(reads, expected_reads, result.stdout)
        self.assertEqual(
            self.before,
            {path: hashlib.sha256((base.ROOT / path).read_bytes()).hexdigest()
             for path in base.SOURCES + base.SOURCE_EXTRAS},
        )

    def test_operand_reads_a_only_b_only_mixed_alias_and_outputs(self):
        rng = random.Random(331907)
        values = [rng.randrange(-100000, 100001) for _ in range(65)]
        # The established fixture binds B to a scalar: only A can be read.
        a_only = base.fixture(op=0, length=65, scalar=37, values=values, context=296)
        # This fixture binds A and leaves B vector-backed: only B can be read.
        b_only = b_only_fixture(values)
        # Both vector operands retain the old two-source result and validation.
        mixed = mixed_fixture(values, list(reversed(values)))
        # This is a physical source alias, not merely equal-valued operands.
        alias = alias_fixture(values)
        self.replay([a_only, b_only, mixed, alias, immediate_zero_fixture()],
                    expected_reads=[3, 3, 6, 3, 0])

    def test_unused_source_cancel_and_malformed_context(self):
        values = [17, -9, 3, -1, 0, 11, -7]
        bad = base.fixture(op=0, length=len(values), scalar=7, values=values, context=297)
        self.replay([b_only_fixture(values, cancel=1),
                     b_only_fixture(values, source_missing=True), bad])

    def test_normalize_prefetch_lengths_under_stalls(self):
        lengths = (33, 63, 64, 65, 127, 128, 1024)
        cases = [base.fixture(op=2, length=length, shift=6, scalar=3,
                              values=[(index * 7919) % 100001 - 50000 for index in range(length)])
                 for length in lengths]
        self.replay(cases, expected_reads=[(length + 31) // 32 for length in lengths])

if __name__ == '__main__':
    unittest.main()
