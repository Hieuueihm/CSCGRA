"""Explicit opcode16: existing PE lane0 result without any vector-memory grant."""
import random
import unittest
from verification.v4 import test_stream_kernel_rtl as base

RUNS=base.RUNS

def fixture(op=2,a=0,b=0,srca=0,srcb=1,imm=0,binda=1,bindb=1,cancel=0,change=None):
    context=op|32|(srca<<6)|(srcb<<8)|((imm&((1<<27)-1))<<10)
    va=(a,b,imm,0)[srca]
    vb=(a,b,imm,0)[srcb]
    value={1:lambda:va,2:lambda:va+vb,3:lambda:va-vb,8:lambda:base.rounded(va*vb,22)}.get(op,lambda:0)()
    fault=0 if -(1<<26)<=value<(1<<26) else 3
    contexts=[context]+[993]*31
    h=[16,1,1,0,0,0,1,0,0,f'{a&((1<<27)-1):x}',f'{b&((1<<27)-1):x}',
       f'{binda:x}',f'{bindb:x}','0',1,'1',fault,f'{value&((1<<64)-1):x}',int(value!=0),cancel,
       1,1,0,3,128,f'{base.pack(contexts,64):x}',0,15,27,0,0,0,0,0]
    if change:
        for index,v in change.items():h[index]=v
        h[16]=1
    return '\n'.join([' '.join(map(str,h)),'128 1 11','128 1 0 11'])

class ScalarTemplateTests(unittest.TestCase):
    setUpClass=classmethod(base.StreamKernelRtlTests.setUpClass.__func__)
    replay=base.StreamKernelRtlTests.replay

    def test_exact_arithmetic_extremes_and_no_pool_access(self):
        cases=[]
        rng=random.Random(163277)
        extremes=[-(1<<26),-4194304,-3,-1,0,1,3,4194304,(1<<26)-1]
        for op in (1,2,3,8):
            cases.extend(fixture(op,a,b) for a in extremes for b in extremes)
            cases.extend(fixture(op,rng.randrange(-(1<<26),1<<26),rng.randrange(-(1<<26),1<<26)) for _ in range(32))
        self.replay(cases)

    def test_immediates_source_selection_and_cancel(self):
        cases=[fixture(op,a=-17,b=31,srca=sa,srcb=sb,imm=-7)
               for op in (1,2,3,8) for sa in range(4) for sb in range(4)]
        cases += [fixture(1,srca=2,srcb=1,imm=-67108864,binda=0,bindb=0),
                  fixture(3,a=-13,b=5,cancel=1),fixture(3,a=-13,b=5)]
        # Code6 is the existing TB's no-reset continuation, not cancellation.
        # Populate scratch masks via a real vector command before scalar CALL.
        cases += [base.fixture(op=0,length=33),fixture(8,a=-17,b=4194304,cancel=6)]
        self.replay(cases)

    def test_malformed_command_and_preserved_destination(self):
        # Reserved/shape controls are explicit; descriptor addresses are ignored.
        changes=[{6:2},{14:2},{15:'3'},{13:'8'},{13:'20'}, {3:1},{4:1},{5:1},
                 {7:1},{8:1},{26:1},{29:1},{30:1},{31:1},{32:1},
                 {11:'0'},{12:'0'},{25:f'{base.pack([265]+[993]*31,64):x}'},
                 {25:f'{base.pack([297]+[993]*31,64):x}'},
                 {25:f'{base.pack([(1<<63)|289]+[993]*31,64):x}'}]
        self.replay([fixture(a=17,b=3,change=change) for change in changes])

if __name__=='__main__':unittest.main()
