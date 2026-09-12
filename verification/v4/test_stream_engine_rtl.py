"""Loaded stream programs on real paired RAM and32 PEs; no host control after START."""
import hashlib,json,re,tempfile,unittest
from pathlib import Path
from compiler.v4.stream_program import build_package,export_package,decode_context,decode_descriptor,decode_program
from models.v4.fixed import Arithmetic
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
IMAGES=[]
MASK=(1<<32)-1

def packed(values):
    return sum((int(v)&((1<<27)-1))<<(27*i) for i,v in enumerate(values))

def template(op='MOV',kind='EACH',mode=1,shift=0,inc_a=1,inc_b=1,inc_dst=1,contexts=None):
    return dict(descriptor=dict(inc_a=inc_a,inc_b=inc_b,inc_dst=inc_dst,output_kind=kind,shift=shift),
                contexts=contexts or [dict(op=op,mode=mode,src_a='A',src_b='B') for _ in range(32)])

def call(a=0,b=64,d=128,n=1,tail=MASK,t=0):
    return dict(kind='CALL',template=t,src_a=a,src_b=b,dst=d,frame_count=n,tail_mask=tail)

def package(calls,templates):
    return build_package([*calls,dict(kind='HALT')],templates)

def oracle(pkg,writes):
    memory={};valid={};scalar=0
    for block,mask,values in writes:
        memory.setdefault(block,[0]*32)
        for lane in range(32):
            if mask>>lane&1:memory[block][lane]=values[lane]
        valid[block]=valid.get(block,0)|mask
    for word in pkg['program']:
        c=decode_program(word)
        if c['kind']==2:break
        t=pkg['templates'][c['template']];d=decode_descriptor(t['descriptor']);acc=[0]*32;scratch=[]
        for frame in range(c['frame_count']):
            mask=c['tail_mask'] if frame==c['frame_count']-1 else MASK
            aa=memory.get(c['src_a']+(frame if d['inc_a'] else 0),[0]*32)
            bb=memory.get(c['src_b']+(frame if d['inc_b'] else 0),[0]*32)
            values=[0]*32
            for lane,ctx in enumerate(t['contexts']):
                if not mask>>lane&1:continue
                q=decode_context(ctx);sources=[aa[lane],bb[lane],q['immediate'],0]
                a,b=sources[q['src_a']],sources[q['src_b']]
                if q['op']==1:v=a
                elif q['op']==2:v=a+b
                elif q['op']==3:v=a-b
                elif q['op']==8:v=Arithmetic.round_shift(a*b,22 if q['mode'] else 16)
                elif q['op']==9:acc[lane]+=a*b;v=0
                else:raise AssertionError(q)
                values[lane]=int(v)
            scratch.append((mask,values))
        if d['output_kind']==2:
            scalar=sum(acc);continue
        if d['output_kind']==1:
            scratch=[(MASK if c['frame_count']>1 else c['tail_mask'],[int(Arithmetic.round_shift(v,d['shift'])) for v in acc])]
        for frame,(mask,values) in enumerate(scratch):
            block=c['dst']+(frame if d['inc_dst'] and d['output_kind']==0 else 0)
            memory.setdefault(block,[0]*32)
            for lane in range(32):
                if mask>>lane&1:memory[block][lane]=values[lane]
            if frame==0 or d['inc_dst']:valid[block]=mask
            else:valid[block]|=mask
    return memory,valid,scalar

class StreamEngineRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory=Path(tempfile.mkdtemp(prefix='stream_engine_',dir=ROOT/'work'))
        cls.binary=cls.directory/'engine.xsim.json'
        cls.sources=['rtl/v4/control/stream_engine.sv','rtl/v4/compute/stream_kernel.sv','rtl/v4/dataflow/support_service.sv','rtl/v4/dataflow/factor_service.sv','rtl/v4/dataflow/factor_panel_service.sv','rtl/v4/memory/factor_store.sv','rtl/v4/dataflow/operator_frame_feeder.sv','rtl/v4/dataflow/range_reader.sv','rtl/v4/control/stream_program_control.sv',
                     'rtl/v4/memory/stream_vector_store.sv','rtl/v4/compute/stream_fabric.sv',
                     'rtl/v4/compute/stream_array.sv','rtl/v4/compute/stream_pe.sv','verification/v4/stream/tb_stream_engine.sv']
        cls.provenance_sources=cls.sources+['config/v4_kernel_interface.json','config/v4_program_interface.json',
            'rtl/v4/include/kernel_interface.vh','rtl/v4/include/program_interface.vh',
            'docs/v4/architecture/FACTOR_PANEL.md','verification/v4/test_stream_engine_rtl.py']
        cls.hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in cls.provenance_sources}
        cls.compiled=compile_rtl(cls.binary,'tb_stream_engine',cls.sources,root=ROOT)
        if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
        cls.serial=0
    def replay(self,pkg,writes,blocks,*,fault=0,detail=0,cancel=0,invalid=(),malformed=False,stall=1,inject=0):
        path=self.directory/f'case{self.serial}';type(self).serial+=1
        baseline=package([call(a=400,b=401,d=450)],[template()])
        baseline_writes=[(400,MASK,[i-16 for i in range(32)])]
        allwrites=baseline_writes+writes
        memory,valid,scalar=oracle(pkg,allwrites)
        for phase,(p,w,readblocks) in enumerate([(baseline,baseline_writes,[450]),(pkg,writes,blocks+[450])]):
            folder=path/str(phase);meta=export_package(p,folder);IMAGES.append(meta)
            if malformed and phase:
                lines=(folder/'templates.hex').read_text().splitlines();lines[-1]=f'{int(lines[-1],16)|(1<<63):016x}'
                (folder/'templates.hex').write_text('\n'.join(lines)+'\n')
            mem,vm,sc=oracle(p,baseline_writes if not phase else allwrites)
            if phase:mem[450]=list(range(-16,16));vm[450]=MASK
            f=fault if phase else 0;de=detail if phase else 0;cm=cancel if phase else 0
            reads=[];recovery=[]
            for block in readblocks:
                bad=phase and (block in invalid or (cm and block!=450))
                mask=MASK if bad else vm.get(block,MASK)
                masked=[v if mask>>lane&1 else 0 for lane,v in enumerate(mem[block])]
                reads.append(f'{block} {mask:08x} {2 if bad else 0} {0 if bad else packed(masked):0216x}')
                recovery_mask=vm.get(block,MASK)
                recovery_data=[v if recovery_mask>>lane&1 else 0 for lane,v in enumerate(mem[block])]
                recovery.append(f'{block} {recovery_mask:08x} 0 {packed(recovery_data):0216x}')
            (folder/'writes.txt').write_text(''.join(f'{b} {m:08x} {packed(v):0216x}\n' for b,m,v in w))
            (folder/'reads.txt').write_text('\n'.join(reads)+'\n')
            (folder/'recovery.txt').write_text('\n'.join(recovery)+'\n')
            (folder/'meta.txt').write_text(f'{len(p["program"])} {len(p["templates"])} {len(w)} {len(reads)} {f} {de} {0 if f else sc&((1<<64)-1):016x} {cm} {stall} {1 if malformed and phase else 0} {inject if phase else 0}\n')
        result=run_rtl(self.binary,[f'DIR={path.as_posix()}'],root=ROOT,timeout=180)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        m=re.search(r'PASS stream_engine cycles=(\d+) checks=(\d+) jobs=(\d+) endpoint_stalls=(\d+)',result.stdout)
        self.assertIsNotNone(m,result.stdout)
        cycles,checks,jobs,stalls=map(int,m.groups())
        self.assertEqual(self.hashes,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in self.provenance_sources})
        record=dict(test=self.id(),case=str(path),status='PASS',cycles=cycles,comparisons=checks,
                    comparison_kind='exact_loaded_program_integer_results_and_transaction_protocol',jobs=jobs,endpoint_stalls=stalls,
                    source_sha256=self.hashes,commands=self.compiled.commands+result.commands,stdout=result.stdout)
        RUNS.append(record);(path/'evidence.json').write_text(json.dumps(record,indent=2)+'\n')
    def test_saved_full1024_add_dot_image_unstalled(self):
        source=json.loads((ROOT/'reports/v4/stream_program_example/input.json').read_text())
        saved=json.loads((ROOT/'reports/v4/stream_program_example/package.json').read_text())
        p=build_package(source['program'],source['templates'])
        self.assertEqual(p['program'],saved['program']);self.assertEqual(p['templates'],saved['templates'])
        writes=[(b,MASK,[1<<22 if b<32 else 2<<22]*32) for b in range(64)]
        self.replay(p,writes,list(range(64,96)),stall=0)
        self.assertEqual(IMAGES[-1]['image_sha256'],saved['image_sha256'])
    def test_selected_operands_partial_publication_and_identity_faults(self):
        contexts=[];ma=mb=0
        for lane in range(32):
            sa,sb=[('IMM','ZERO'),('B','A'),('A','IMM'),('ZERO','B')][lane%4]
            contexts.append(dict(op='ADD',mode=1,src_a=sa,src_b=sb,immediate=-17))
            if 'A' in (sa,sb):ma|=1<<lane
            if 'B' in (sa,sb):mb|=1<<lane
        p=package([call()],[template(contexts=contexts)])
        writes=[(0,ma,list(range(32))),(64,mb,[3*i for i in range(32)])]
        self.replay(p,writes,[128])
        for mode in (1,2):self.replay(p,writes,[128],fault=5,detail=6,invalid=[128],inject=mode)
    def test_full_n_mixed_contexts_alias_and_last_write(self):
        writes=[(b,MASK,[(b+3)*17+i-80 for i in range(32)]) for b in range(96)]
        mixed=[dict(op=['MOV','ADD','SUB','MUL'][i%4],mode=1,src_a='A',src_b='B') for i in range(32)]
        p=package([call(a=0,b=64,d=0,n=32,tail=0x3fffffff),call(a=0,b=64,d=200,n=3,tail=7,t=1)],
                  [template(contexts=mixed),template('ADD',inc_dst=0)])
        self.replay(p,writes,list(range(32))+[200])
    def test_mac_last_and_dot_masked_prefix(self):
        writes=[(b,MASK,[(-1 if i%3==0 else 1)*(i+1)*(b+1) for i in range(32)]) for b in range(96)]
        for mode in (0,1):
            p=package([call(n=32,tail=1),call(n=3,tail=3,t=1)],
                      [template('MAC','LAST_ACC',mode=mode,shift=12),template('MAC','SUM_ACC',mode=mode)])
            self.replay(p,writes,[128])
    def test_source_validity_numeric_faults_and_malformed_load(self):
        p=package([call(n=2)],[template('ADD')]);w=[(0,MASK,[1]*32),(64,MASK,[2]*32),(128,MASK,[3]*32),(129,MASK,[3]*32)]
        self.replay(p,w,[128,129],fault=5,detail=5,invalid=[128,129])
        p=package([call()],[template('ADD')]);w=[(0,MASK,[(1<<26)-1]*32),(64,MASK,[1]*32),(128,MASK,[3]*32)]
        self.replay(p,w,[128],fault=5,detail=3,invalid=[128])
        p=package([call()],[template('MAC','LAST_ACC',mode=1)]);w=[(0,MASK,[1<<20]*32),(64,MASK,[1<<20]*32),(128,MASK,[3]*32)]
        self.replay(p,w,[128],fault=5,detail=4,invalid=[128])
        self.replay(package([call()],[template()]),[(0,MASK,[1]*32)],[128],malformed=True)
    def test_cancel_run_and_copy_invalidate_destination(self):
        w=[(b,MASK,[b+i for i in range(32)]) for b in range(96)]
        w += [(b,MASK,[7]*32) for b in range(128,160)]
        p=package([call(n=32)],[template('ADD')])
        for cancel in (1,2):self.replay(p,w,list(range(128,160)),cancel=cancel)
if __name__=='__main__':unittest.main()
