"""Independent integer checks for terminal reductions on the existing PEs."""
import random
import unittest
from verification.v4 import test_stream_kernel_rtl as base

RUNS=base.RUNS

def raw_case(values, scalar=1, energy=False, cancel=0):
    n=len(values)
    frames=(n+31)//32
    mask=(1<<(n%32))-1 if n%32 else base.MASK
    context=41 if energy else 297
    expected=sum(v*v if energy else v*scalar for v in values)
    writes=[]
    for block in range(frames):
        data=values[block*32:block*32+32]
        writes.append(f'{block} {(1<<len(data))-1:x} {base.pack(data):x}')
    # Scalar success, fault and cancellation must not invalidate a vector.
    writes.append('128 1 11')
    h=[0,1,1,0,0,0,n,0,0,f'{scalar&((1<<27)-1):x}',f'{scalar&((1<<27)-1):x}',
       '0','0' if energy else 'ffffffff','11',frames,f'{mask:x}',0,f'{expected&((1<<64)-1):x}',0,cancel,
       len(writes),1,0,3,128,f'{base.pack([context]*32,64):x}',0,0,0,0,0,0,0,0]
    return '\n'.join([' '.join(map(str,h)),*writes,'128 1 2 0' if cancel==9 else '128 1 0 11'])

class TerminalComputeTests(unittest.TestCase):
    setUpClass=classmethod(base.StreamKernelRtlTests.setUpClass.__func__)
    replay=base.StreamKernelRtlTests.replay

    def test_signed_sum_energy_bound_and_masked_prefix(self):
        rng=random.Random(987001)
        cases=[]
        for n in (1,2,3,7,8,17,31,32,33,63,64,65,127,128,1023,1024):
            v=[rng.randrange(-(1<<26),1<<26) for _ in range(n)]
            cases.extend([raw_case(v,-(1<<26)),raw_case(v,energy=True)])
        cases += [raw_case([-(1<<26)]*1024,energy=True),
                  raw_case([-(1<<26),(1<<26)-1]*512,(1<<26)-1)]
        self.replay(cases)

    def test_terminal_cancel_and_restart(self):
        values=list(range(-16,17))
        self.replay([raw_case(values,7,cancel=8),raw_case(values,7),
                     raw_case(values,energy=True,cancel=9),raw_case(values,energy=True)])

    def test_parallel_round_extremes_shift_zero_and_tail(self):
        cases=[]
        for n in (1,17,31,32,33,63,64,65,1024):
            for shift in (0,1,22,44,63):
                values=([-67108864,67108863,-1,0,1]*((n+4)//5))[:n]
                cases.append(base.fixture(op=2,length=n,shift=shift,scalar=-67108864,
                                          values=values,destination=0))
        self.replay(cases)

if __name__=='__main__':
    unittest.main()
