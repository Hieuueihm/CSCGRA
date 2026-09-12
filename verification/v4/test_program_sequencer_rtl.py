"""Generic program controller with delayed mock services; no algorithm/E2E claim."""
import hashlib,json,random,re,tempfile,unittest
from pathlib import Path
from compiler.v4 import recovery_program as asm
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
MASK64=(1<<64)-1
SOURCES=['rtl/v4/control/program_sequencer.sv','verification/v4/program/tb_program_sequencer.sv']
EXTRAS=['verification/v4/test_program_sequencer_rtl.py','compiler/v4/recovery_program.py','compiler/v4/stream_program.py','config/v4_program_interface.json','config/v4_kernel_interface.json','config/v4_stream_interface.json','rtl/v4/include/program_interface.vh','rtl/v4/include/kernel_interface.vh','rtl/v4/include/stream_interface.vh','scripts/v4/xsim.py','docs/v4/architecture/PROGRAM_PREFETCH.md']
FIELDS=asm.KERNEL['request_ports']
NAMES={v:k for k,v in asm.ABI['kinds'].items()}

def packed(fields,values):
 result=0;bit=0
 for name,width in fields.items():result|=(int(values.get(name,0))&((1<<width)-1))<<bit;bit+=width
 return result

def signed(x,width=64):return x-(1<<width) if x>>(width-1)&1 else x

def package(words,vectors=None,constants=None,binding=0):
 return dict(revision=2,program=words,constants=[] if constants is None else constants,
  templates=[dict(descriptor=7,bind_a=0,bind_b=binding,contexts=[296]*32)],
  vectors=[dict(base=0,capacity=1024),dict(base=32,capacity=1024),dict(base=64,capacity=96)] if vectors is None else vectors)

def records(pkg):
 rows=[(0,i,w) for i,w in enumerate(pkg['program'])]
 for i,t in enumerate(pkg['templates']):
  rows.append((1,i*33,t['descriptor']|(t['bind_a']<<32)|(t['bind_b']<<64)))
  rows.extend((1,i*33+j+1,w) for j,w in enumerate(t['contexts']))
 rows.extend((2,i,v['base']|(v['capacity']<<9)) for i,v in enumerate(pkg['vectors']))
 rows.extend((3,i,w&MASK64) for i,w in enumerate(pkg['constants']))
 return [[k,i,w,int(n+1==len(rows))] for n,(k,i,w) in enumerate(rows)]

class Trap(Exception):
 def __init__(self,fault,detail=0):self.fault=fault;self.detail=detail

def simulate(pkg,replies=(),limit=10000,cancel=0):
 rf=[0]*32;pc=0;stack=[];trace=[];events=[];tag=100;status=0;fault=detail=0;handles=(0,1 if len(pkg['vectors'])>1 else 0,2 if len(pkg['vectors'])>2 else 0)
 try:
  while True:
   if len(trace)>=limit:raise Trap(8)
   w=asm.decode(pkg['program'][pc]);kind=NAMES.get(w['kind']);imm=w['immediate'];a=rf[w['a_s']];b=rf[w['b_s']];dst=w['dst_s'];next_pc=pc+1
   if w['reserved'] or kind is None or any(v and k not in asm.ABI['allowed_fields'][kind] for k,v in w.items() if k not in ('kind','reserved')):raise Trap(3)
   if kind in ('SET','MOV','NEG','INC','ADD64','SUB64','RECIP_PREP','CONST_LOAD','CERT','DIV','SQRT','RESCALE') and dst==0:raise Trap(3)
   if kind=='SET':rf[dst]=signed(imm)
   elif kind=='MOV':rf[dst]=a
   elif kind in ('NEG','INC','ADD64','SUB64'):
    value=-a if kind=='NEG' else a+1 if kind=='INC' else a+b if kind=='ADD64' else a-b
    if not -(1<<63)<=value<(1<<63):raise Trap(4)
    rf[dst]=value
   elif kind=='RECIP_PREP':
    if not 0<a<(1<<26) or w['shift_s'] in (0,dst):raise Trap(4)
    rf[dst]=1<<a.bit_length();rf[w['shift_s']]=a.bit_length()
   elif kind=='CONST_LOAD':
    if a<0 or not 0<=a+imm<len(pkg['constants']):raise Trap(3)
    rf[dst]=signed(pkg['constants'][a+imm]&MASK64)
   elif kind=='CERT':
    ia=imm&1023;ib=imm>>10&1023
    if imm>>20 or ia>=len(pkg['constants']) or ib>=len(pkg['constants']) or a<0 or b<0:raise Trap(3)
    if cancel==3:break
    rf[dst]=int(a*(pkg['constants'][ia]&MASK64)<=b*(pkg['constants'][ib]&MASK64))
   elif kind in ('BR_ZERO','BR_NONZERO','BR_GE','BR_COMPARE'):
    cond=a==0 if kind=='BR_ZERO' else a!=0 if kind=='BR_NONZERO' else a>=b if kind=='BR_GE' else (a==b,a!=b,a<b,a<=b,a>b,a>=b)[imm] if imm<6 else None
    if cond is None:raise Trap(3)
    if cond:next_pc=w['target']
   elif kind=='JUMP':next_pc=w['target']
   elif kind=='CALL':
    if len(stack)==4 or pc+1>=len(pkg['program']):raise Trap(9)
    stack.append(pc+1);next_pc=w['target']
   elif kind=='RET':
    if not stack:raise Trap(9)
    next_pc=stack.pop()
   elif kind in ('KERNEL','DIV','SQRT','RESCALE','BUILD_B'):
    response=dict(data=0,fault=0,detail=0,count=0,nz=0,corrupt=0);response.update(replies[len(events)] if len(events)<len(replies) else {})
    if kind=='KERNEL':
     ii=asm.unpack(asm.ABI['service_immediate_fields'],imm);t=pkg['templates'][ii['template']];v=pkg['vectors'];length=33 if w['length_mode']==0 else 1024 if w['length_mode']==1 else ii['length'] if w['length_mode']==2 else rf[ii['length']]
     values=dict(op=w['kernel'],contexts=packed({str(i):64 for i in range(32)},{str(i):x for i,x in enumerate(t['contexts'])}),descriptor=t['descriptor'],src_a=v[w['a_v']]['base'],src_b=v[w['b_v']]['base'],dst=v[w['dst_v']]['base'],length=length,rows=33,cols=rf[ii['support_length_s']] if ii['dense'] else 1024,matrix_dense=ii['dense'],trans=ii['transpose'],r4=ii['r4'],scalar_a=a,scalar_b=b,scalar_bind_a=t['bind_a'],scalar_bind_b=t['bind_b'],shift=rf[w['shift_s']],k=rf[ii['k_s']],scale=4096,key=0x1234,generation=3,job=7,tag=tag,fmt=1,frame_count=(length+31)//32,tail_mask=(1<<(length%32))-1 if length%32 else (1<<32)-1,store_mode=ii['store_mode'],support_base=v[ii['support_v']]['base'],aux_base=v[ii['aux_v']]['base'],support_length=rf[ii['support_length_s']],aux_length=rf[ii['aux_length_s']],index=rf[ii['index_s']],flags=ii['flags'])
     if w['kernel']==21:
      # Canonical unused operands are literal-zero request buses, even when
      # descriptor zero is a legal nonzero-base public vector.
      values.update(src_b=0,support_base=0,aux_base=0)
     if w['kernel']==22:
      # Only the support/auxiliary *metadata* is unused.  Source B remains
      # the normal loaded-template B operand at its independent raw base.
      values.update(support_base=0,aux_base=0)
     
     if ii['reserved'] or not 0<length<=1024 or not 0<=rf[w['shift_s']]<=63:raise Trap(3)
     source_need=0 if w['kernel']==9 else rf[ii['support_length_s']] if w['kernel']==8 else (values['rows'] if ii['transpose'] else values['cols']) if w['kernel']==1 else length
     output_need=values['cols'] if w['kernel']==1 and ii['transpose'] else values['rows'] if w['kernel']==1 else rf[ii['k_s']] if w['kernel'] in (5,9) else rf[ii['support_length_s']] if w['kernel']==7 else 0 if w['kernel']==10 else rf[ii['aux_length_s']] if w['kernel']==11 else length
     if w['kernel'] in (13,14,15):
      if w['kernel'] in (13,14):source_need=0
      if w['kernel'] in (13,15):output_need=0
      start=values['aux_length'];axis=values['index'];row=bool(ii['flags']&1)
      if not ii['dense'] or not 1<=values['cols']<=96 or length>128 or ii['flags']&254 or ii['transpose'] or ii['r4'] or ii['store_mode'] or values['k']:raise Trap(3)
      if w['kernel']==13:
       if length!=33 or start or axis or ii['flags']:raise Trap(3)
      elif axis>=(33 if row else values['cols']) or start+length>(values['cols'] if row else 33):raise Trap(3)
     if w['kernel']==19:
      source_need=output_need=0
      if (not ii['dense'] or not 1<=values['cols']<=96 or length!=values['rows'] or
          not 0<values['index']<values['cols'] or values['aux_length'] or ii['flags'] or
          ii['transpose'] or ii['r4'] or ii['store_mode'] or values['k'] or values['shift'] or
          t['descriptor'] or t['bind_a'] or t['bind_b'] or any(t['contexts']) or
          any(w[field] for field in ('a_v','b_v','dst_v','a_s','b_s','dst_s','flag_s','target')) or
          any(ii[field] for field in ('support_v','aux_v','k_s'))):raise Trap(3)
     if w['kernel']==20:
      source_need=length;output_need=0
      compact=[297,296,291]+[0]*29
      if (not ii['dense'] or not 1<=values['cols']<=96 or not 1<=length<=128 or
          values['aux_length']>=values['rows'] or values['aux_length']+length>values['rows'] or values['index']>=values['cols'] or
          ii['flags'] or ii['transpose'] or ii['r4'] or ii['store_mode'] or values['k'] or values['shift'] or
          t['descriptor']!=31 or t['bind_a'] or t['bind_b'] or t['contexts']!=compact or
          w['b_v'] or w['dst_v'] or w['b_s'] or w['dst_s'] or w['flag_s'] or w['target'] or
          any(ii[field] for field in ('support_v','aux_v','k_s')) or not -(1<<26)<=a<(1<<26)):raise Trap(3)
     if w['kernel']==21:
      if (t['descriptor'] or t['bind_a'] or t['bind_b'] or any(t['contexts']) or
          not -(1<<26)<=a<(1<<26) or w['b_v'] or ii['support_v'] or ii['aux_v'] or
          w['b_s'] or w['dst_s'] or w['flag_s'] or ii['dense'] or ii['transpose'] or
          ii['r4'] or ii['store_mode'] or ii['flags'] or rf[ii['k_s']] or
          rf[ii['support_length_s']] or rf[ii['aux_length_s']] or rf[w['shift_s']] or
          w['target'] or length==0 or rf[ii['index_s']]<0 or rf[ii['index_s']]>=length):raise Trap(3)
     if w['kernel']!=20 and t['descriptor']>>3&3==3:raise Trap(3)
     if w['kernel'] in (11,12):
      start=rf[ii['index_s']];size=rf[ii['aux_length_s']]
      if not 0<=start<=1024 or not 0<=size<=1024 or start+size>length or ii['flags'] or rf[ii['k_s']] or rf[ii['support_length_s']] or v[ii['support_v']]['base']!=0:raise Trap(3)
      if w['kernel']==12 and v[ii['aux_v']]['capacity']<size:raise Trap(3)
     if w['kernel']==0:
      need=[0,0]
      for element in range(length):
       lane=element%32;cw=t['contexts'][lane];selectors=[cw>>6&3]+([] if cw&31==1 else [cw>>8&3])
       for channel in (0,1):
        if channel in selectors and not ((t['bind_a'] if channel==0 else t['bind_b'])>>lane&1):
         need[channel]=max(need[channel],element+1 if (t['descriptor']>>channel)&1 else lane+1)
       source_need=need[0]
      if v[w['b_v']]['capacity']<need[1]:raise Trap(3)
     if w['kernel']==22:
      # Model the sequencer's selected-lane capacity proof independently of
      # raw transport.  `index` and `aux_length` are A/B offsets here.
      need=[0,0]
      for element in range(length):
       lane=element%32;cw=t['contexts'][lane];selectors=[cw>>6&3]+([] if cw&31==1 else [cw>>8&3])
       for channel in (0,1):
        if channel in selectors and not ((t['bind_a'] if channel==0 else t['bind_b'])>>lane&1):
         need[channel]=max(need[channel],element+1 if (t['descriptor']>>channel)&1 else lane+1)
      a_offset=rf[ii['index_s']];b_offset=rf[ii['aux_length_s']]
      if (ii['dense'] or ii['transpose'] or ii['r4'] or ii['store_mode'] or ii['flags'] or values['k'] or
          ii['support_v'] or ii['aux_v'] or values['support_length'] or values['shift'] or w['target'] or
          t['descriptor']&7!=7 or not 0<=a_offset<=1023 or not 0<=b_offset<=1023 or
          (need[0]==0 and a_offset!=0) or (need[1]==0 and b_offset!=0) or
          (need[0] and a_offset+need[0]>v[w['a_v']]['capacity']) or
          (need[1] and b_offset+need[1]>v[w['b_v']]['capacity'])):raise Trap(3)
      source_need=0
      output_need=0 if (t['descriptor']>>3&3)==2 else min(length,32) if (t['descriptor']>>3&3)==1 else length
     if w['kernel']==16:
      cw=t['contexts'][0];selectors=[cw>>6&3]+([] if cw&31==1 else [cw>>8&3])
      if length!=1 or t['descriptor']&~7 or not (cw>>5&1) or cw&31 not in (1,2,3,8):raise Trap(3)
      if any(channel<2 and not ((t['bind_a'] if channel==0 else t['bind_b'])&1) for channel in selectors):raise Trap(3)
      if any(ii[k] for k in ('dense','transpose','r4','store_mode','flags')) or any(rf[ii[k]] for k in ('k_s','support_length_s','aux_length_s','index_s')) or rf[w['shift_s']]:raise Trap(3)
      if any(binding and not -(1<<26)<=value<(1<<26) for binding,value in ((t['bind_a'],a),(t['bind_b'],b))):raise Trap(3)
      source_need=output_need=0
     if v[w['a_v']]['capacity']<source_need or v[w['dst_v']]['capacity']<output_need:raise Trap(3)
     payload=packed(FIELDS,values);service=1
    elif kind in ('DIV','SQRT','RESCALE'):
     if kind=='DIV' and imm not in (0,246):raise Trap(3)
     payload=packed(dict(op=2,a=64,b=64,frac=8,job=16,tag=16,fmt=8),dict(op=0 if kind=='DIV' else 2 if kind=='RESCALE' else 1,a=a,b=b,frac=imm if kind=='DIV' else 44,job=7,tag=tag,fmt=1));service=2
    else:
     if a<=0 or a>96 or pkg['vectors'][w['a_v']]['capacity']<a:raise Trap(3)
     payload=packed(dict(base=9,count=11,job=16,tag=16,fmt=8),dict(base=pkg['vectors'][w['a_v']]['base'],count=a,job=7,tag=tag,fmt=1));service=3
    events.append(f"{service} {payload:x} {response['data']&MASK64:x} {response['fault']} {response['detail']} {response['count']} {response['nz']} {response['corrupt']}")
    if cancel==2:break
    if response['corrupt']:raise Trap(5)
    if response['fault']:raise Trap({1:6,2:7,3:11}[service],response['detail'] if service==1 else response['fault'])
    if kind=='KERNEL':
     if dst:rf[dst]=signed(response['data']&MASK64)
     if w['flag_s']:rf[w['flag_s']]=response['count'] if w['target']&1 else response['nz']
    elif service==2:rf[dst]=signed(response['data']&((1<<27)-1),27)
    tag=(tag+1)&65535
   elif kind in ('HALT_STATUS','FAIL'):
    status=imm&255
    if kind=='HALT_STATUS' and imm>>8:raise Trap(3)
    if kind=='HALT_STATUS':handles=(w['dst_v'],w['a_v'],w['b_v'])
    trace.append(pc);break
   elif kind=='SUCCESS':raise Trap(3)
   elif kind!='NOP':raise AssertionError(kind)
   trace.append(pc)
   if not 0<=next_pc<len(pkg['program']):raise Trap(3)
   pc=next_pc
 except Trap as error:fault,detail,status=error.fault,error.detail,8
 return dict(rf=rf,trace=trace,events=events,fault=fault,detail=detail,status=status,handles=handles)

def scenario(pkg,replies=(),limit=10000,cancel=0,load_mutator=None,revision=2,count_override=None):
 recs=records(pkg);model=simulate(pkg,replies,limit,cancel) if not load_mutator and revision==2 and count_override is None and cancel!=1 else dict(events=[],fault=0,detail=0,status=0)
 load_fault=int(bool(load_mutator or revision!=2 or count_override is not None))
 if load_mutator:load_mutator(recs)
 counts=[len(pkg['program']),len(pkg['templates']),len(pkg['vectors']),len(pkg['constants'])]
 if count_override is not None:counts[count_override[0]]=count_override[1]
 header=[revision,*counts,len(recs),len(model['events']),limit,load_fault,model['fault'],model['detail'],model['status'],cancel]
 text=' '.join(map(str,header))+'\n'+'\n'.join(f'{k} {i} {w:x} {last}' for k,i,w,last in recs)+'\n'+'\n'.join(model['events'])
 return text,model if not load_fault and not cancel else None,pkg

E=asm.encode
HALT=lambda **kw:E('HALT_STATUS',**kw)

class ProgramSequencerRtlTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.folder=Path(tempfile.mkdtemp(prefix='program_sequencer_',dir=ROOT/'work'));cls.binary=cls.folder/'program.xsim.json'
  cls.before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES+EXTRAS}
  cls.compiled=compile_rtl(cls.binary,'tb_program_sequencer',SOURCES,root=ROOT)
  if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
  cls.baseline_binary=cls.folder/'program_baseline.xsim.json'
  cls.baseline_compiled=compile_rtl(cls.baseline_binary,'tb_program_sequencer',SOURCES,root=ROOT,parameters={'RETIRE_TIME_FETCH':0})
  if cls.baseline_compiled.returncode:raise AssertionError(cls.baseline_compiled.stdout+cls.baseline_compiled.stderr)
 def replay(self,items):
  path=self.folder/(self._testMethodName+'.txt');path.write_text(str(len(items))+'\n'+'\n'.join(x[0] for x in items)+'\n')
  result=run_rtl(self.binary,['vectors='+path.as_posix()],root=ROOT,timeout=300)
  self.assertEqual(result.returncode,0,result.stdout+result.stderr)
  match=re.search(r'PASS program_sequencer cycles=(\d+) checks=(\d+) cases=(\d+)',result.stdout);self.assertIsNotNone(match,result.stdout)
  cycles,checks,count=map(int,match.groups());self.assertEqual(count,len(items));comparisons=checks
  traces={i:[] for i in range(len(items))};regs={i:{} for i in range(len(items))}
  for case,pc,word in re.findall(r'RET case=(\d+) pc=(\d+) word=([0-9a-f]+)',result.stdout):traces[int(case)].append(int(pc))
  for case,index,data in re.findall(r'RF case=(\d+) index=(\d+) data=([0-9a-f]+)',result.stdout):regs[int(case)][int(index)]=signed(int(data,16))
  for i,(_,model,pkg) in enumerate(items):
   if model is None:continue
   self.assertEqual(traces[i],model['trace'],f'case{i} trace');self.assertEqual(regs[i],dict(enumerate(model['rf'])),f'case{i} RF');comparisons+=32+len(model['trace'])
   done=re.search(rf'DONE case={i} out=(\d+)/(\d+) residual=(\d+)/(\d+) support=(\d+)/(\d+) count=(\d+)',result.stdout);self.assertIsNotNone(done)
   expect=[]
   for handle in model['handles']:expect.extend((pkg['vectors'][handle]['base'],pkg['vectors'][handle]['capacity']))
   expect.append(model['rf'][29]&2047);self.assertEqual(list(map(int,done.groups())),expect);comparisons+=7
  self.assertEqual(self.before,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES+EXTRAS})
  record=dict(test=self.id(),status='PASS',cycles=cycles,comparisons=comparisons,cases=count,commands=self.compiled.commands+result.commands,stdout=result.stdout,source_sha256=self.before,vectors_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),scope='controller_only_mock_services')
  RUNS.append(record);(self.folder/(self._testMethodName+'.json')).write_text(json.dumps(record,indent=2)+'\n')
 def replay_cycle_pair(self,items):
  """Run the identical loaded images with and without retire-time fetch."""
  path=self.folder/(self._testMethodName+'.txt');path.write_text(str(len(items))+'\n'+'\n'.join(x[0] for x in items)+'\n')
  candidate=run_rtl(self.binary,['vectors='+path.as_posix()],root=ROOT,timeout=300)
  baseline=run_rtl(self.baseline_binary,['vectors='+path.as_posix()],root=ROOT,timeout=300)
  self.assertEqual(candidate.returncode,0,candidate.stdout+candidate.stderr)
  self.assertEqual(baseline.returncode,0,baseline.stdout+baseline.stderr)
  parse=lambda result: re.search(r'PASS program_sequencer cycles=(\d+) checks=(\d+) cases=(\d+)',result.stdout)
  got,old=parse(candidate),parse(baseline)
  self.assertIsNotNone(got,candidate.stdout);self.assertIsNotNone(old,baseline.stdout)
  candidate_cycles,candidate_checks,candidate_cases=map(int,got.groups())
  baseline_cycles,baseline_checks,baseline_cases=map(int,old.groups())
  self.assertEqual((candidate_checks,candidate_cases),(baseline_checks,baseline_cases))
  traces=lambda result:[(int(case),int(pc),word) for case,pc,word in re.findall(r'RET case=(\d+) pc=(\d+) word=([0-9a-f]+)',result.stdout)]
  self.assertEqual(traces(candidate),traces(baseline))
  registers=lambda result:[(int(case),int(index),data) for case,index,data in re.findall(r'RF case=(\d+) index=(\d+) data=([0-9a-f]+)',result.stdout)]
  self.assertEqual(registers(candidate),registers(baseline))
  done=lambda result:[tuple(map(int,row)) for row in re.findall(r'DONE case=\d+ out=(\d+)/(\d+) residual=(\d+)/(\d+) support=(\d+)/(\d+) count=(\d+)',result.stdout)]
  self.assertEqual(done(candidate),done(baseline))
  self.assertLess(candidate_cycles,baseline_cycles)
  record=dict(test=self.id(),status='PASS',candidate_cycles=candidate_cycles,baseline_cycles=baseline_cycles,
      eliminated_cycles=baseline_cycles-candidate_cycles,cases=candidate_cases,comparisons=candidate_checks,
      commands=self.compiled.commands+self.baseline_compiled.commands+candidate.commands+baseline.commands,
      stdout=dict(candidate=candidate.stdout,baseline=baseline.stdout),source_sha256=self.before,
      vectors_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),scope='controller_only_prefetch_cycle_pair')
  RUNS.append(record);(self.folder/(self._testMethodName+'.json')).write_text(json.dumps(record,indent=2)+'\n')
 def test_retire_time_fetch_control_hazards_and_cycle_delta(self):
  """Resolved branch/call/return and service successors keep traces while saving FETCH gaps."""
  linear=[E('SET',dst_s=1,immediate=1),E('INC',dst_s=1,a_s=1),E('INC',dst_s=1,a_s=1),HALT()]
  control=[E('SET',dst_s=1,immediate=0),E('BR_ZERO',a_s=1,target=4),E('FAIL',immediate=8),E('NOP'),
           E('CALL',target=8),E('INC',dst_s=1,a_s=1),E('JUMP',target=10),E('NOP'),
           E('SET',dst_s=2,immediate=7),E('RET'),HALT()]
  service=[E('SET',dst_s=1,immediate=9),E('DIV',dst_s=2,a_s=1,b_s=1,immediate=246),E('INC',dst_s=3,a_s=2),HALT()]
  cancel=[E('SET',dst_s=1,immediate=1),E('KERNEL',kernel=0,dst_v=2,a_v=0,b_v=1,length_mode=2,
          immediate=asm.service_immediate(length=1)),HALT()]
  self.replay_cycle_pair([scenario(package(linear)),scenario(package(control)),
      scenario(package(service),[dict(data=1)]),scenario(package(cancel,vectors=[dict(base=0,capacity=1),dict(base=1,capacity=1),dict(base=2,capacity=1)]),[dict(data=1)],cancel=2)])
 def test_scalar_template_bound_request_fault_cancel_and_illegal_modes(self):
  from compiler.v4.stream_program import encode_context
  def make(op='MUL',left=7,right=-9,**change):
   fields=dict(length=1);fields.update(change.pop('immediate',{}))
   words=[E('SET',dst_s=1,immediate=left),E('SET',dst_s=2,immediate=right),E('KERNEL',kernel=16,dst_s=3,a_s=1,b_s=2,flag_s=4,length_mode=2,immediate=asm.service_immediate(**fields)),HALT()]
   pkg=package(words,vectors=[dict(base=479,capacity=1)])
   template=dict(descriptor=7,bind_a=1,bind_b=1,contexts=[encode_context(op=op,mode=1,src_a='A',src_b='B')]*32)
   template.update(change);pkg['templates']=[template];return pkg
  cases=[]
  for op in ('MOV','ADD','SUB','MUL'):
   for value in (-(1<<26),(1<<26)-1):cases.append(scenario(make(op,left=value),[dict(data=value,nz=1)]))
  cases += [scenario(make(),[dict(data=-17,nz=1)],cancel=2),scenario(make(),[dict(fault=3,detail=4)]),scenario(make(),[dict(corrupt=1)])]
  bad=[make(bind_a=0),make(bind_b=0),make('MAC',descriptor=23),make('MAC',descriptor=15),make(immediate=dict(length=2)),make(immediate=dict(flags=1)),make(immediate=dict(r4=1)),make(immediate=dict(transpose=1)),make(immediate=dict(store_mode=1)),make(left=1<<26)]
  cases += [scenario(pkg) for pkg in bad]
  self.replay(cases)
 def test_loader_order_revision_reserved_capacity_and_cancel(self):
  base=package([HALT()],vectors=[dict(base=479,capacity=1)])
  mutate=[lambda r:r[0].__setitem__(1,1),lambda r:r[0].__setitem__(2,r[0][2]|(1<<127)),lambda r:r[0].__setitem__(3,1),lambda r:r[0].__setitem__(2,31),lambda r:r[1].__setitem__(2,1<<96),lambda r:r[2].__setitem__(2,1<<37),lambda r:r[-1].__setitem__(2,479|(64<<9)),lambda r:r[-1].__setitem__(3,0)]
  cases=[scenario(base),scenario(base,revision=1),scenario(base,cancel=1)]+[scenario(base,load_mutator=f) for f in mutate]
  cases += [scenario(base,count_override=x) for x in ((0,0),(0,1025),(1,0),(1,17),(2,0),(2,33),(3,1025))]
  self.replay(cases)
 def test_branches_stack_watchdog_signed_rf_and_constants(self):
  words=[E('SET',dst_s=1,immediate=-3),E('SET',dst_s=2,immediate=2),E('BR_COMPARE',a_s=1,b_s=2,immediate=2,target=4),E('FAIL',immediate=8),E('CALL',target=9),E('INC',dst_s=1,a_s=1),E('BR_GE',a_s=1,b_s=2,target=8),E('JUMP',target=5),HALT(),E('CONST_LOAD',dst_s=3,a_s=2,immediate=1),E('NEG',dst_s=4,a_s=3),E('ADD64',dst_s=5,a_s=1,b_s=4),E('SUB64',dst_s=6,a_s=5,b_s=2),E('RET')]
  cases=[scenario(package(words,constants=[7,8,9,-17])),scenario(package([E('SET',dst_s=1,immediate=0),E('BR_ZERO',a_s=1,target=4),E('FAIL',immediate=8),E('NOP'),E('SET',dst_s=1,immediate=1),E('BR_NONZERO',a_s=1,target=7),E('FAIL',immediate=8),HALT()]))]
  cases += [scenario(package([E('RET')])),scenario(package([E('CALL',target=0),HALT()])),scenario(package([E('JUMP',target=0)]),limit=7)]
  for kind,value,other in [('NEG',-(1<<63),0),('INC',(1<<63)-1,0),('ADD64',(1<<63)-1,1),('SUB64',-(1<<63),1)]:
   cases.append(scenario(package([E('SET',dst_s=1,immediate=value),E('SET',dst_s=2,immediate=other),E(kind,dst_s=3,a_s=1,**({'b_s':2} if kind in ('ADD64','SUB64') else {})),HALT()])))
  cases += [scenario(package([E('NOP')|(1<<5),HALT()])),scenario(package([E('SET',dst_s=0,immediate=1),HALT()])),scenario(package([E('CONST_LOAD',dst_s=1,a_s=0),HALT()]))]
  self.replay(cases)
 def test_exact_unsigned128_certificate_and_reciprocal_prepare(self):
  rng=random.Random(552);cases=[]
  tuples=[((1<<62)-1,1<<62,(1<<63)+1,(1<<63)-1),(1<<62,(1<<62)-1,(1<<63)-1,(1<<63)+1),(0,0,MASK64,MASK64)]
  tuples += [(rng.randrange(1<<63),rng.randrange(1<<63),rng.randrange(1<<64),rng.randrange(1<<64)) for _ in range(12)]
  for a,b,ca,cb in tuples:
   cases.append(scenario(package([E('SET',dst_s=1,immediate=a),E('SET',dst_s=2,immediate=b),E('CERT',dst_s=3,a_s=1,b_s=2,immediate=1<<10),HALT()],constants=[ca,cb])))
  cases.append(scenario(package([E('SET',dst_s=1,immediate=17),E('RECIP_PREP',dst_s=2,a_s=1,shift_s=3),HALT()])))
  cases.append(scenario(package([E('SET',dst_s=1,immediate=17),E('CERT',dst_s=2,a_s=1,b_s=1),HALT()],constants=[1]),cancel=3))
  self.replay(cases)
 def test_mock_services_identity_faults_and_scalar_bind_capacity(self):
  imm=asm.service_immediate(length=33)
  words=[E('SET',dst_s=1,immediate=7),E('SET',dst_s=3,immediate=2),E('KERNEL',kernel=0,dst_v=2,a_v=0,b_v=1,dst_s=10,a_s=1,b_s=1,flag_s=29,target=1,length_mode=2,immediate=imm),E('DIV',dst_s=11,a_s=10,b_s=1,immediate=246),E('BUILD_B',a_v=0,a_s=3),E('SQRT',dst_s=12,a_s=10),HALT(dst_v=2,a_v=0,b_v=1)]
  base=package(words,vectors=[dict(base=0,capacity=33),dict(base=10,capacity=1),dict(base=20,capacity=33)],binding=(1<<32)-1)
  replies=[dict(data=123,count=7,nz=1),dict(data=-42),{},dict(data=999)]
  cases=[scenario(base,replies),scenario(base,replies,cancel=2)]
  for step in (0,1,2):
   for response in (dict(corrupt=1),dict(fault=3,detail=4)):
    altered=[dict(x) for x in replies];altered[step].update(response);cases.append(scenario(base,altered))
  self.replay(cases)
 def test_maximum_image_and_signed_comparison_predicates(self):
  big=package([E('SET',dst_s=1,immediate=1023),E('CONST_LOAD',dst_s=2,a_s=1)]+[E('NOP')]*1021+[HALT()],vectors=[dict(base=i,capacity=1) for i in range(32)],constants=list(range(1024)))
  big['templates']=[dict(big['templates'][0]) for _ in range(16)]
  cases=[scenario(big,limit=2000)]
  for predicate in range(6):
   for a,b in [(-3,2),(2,2)]:
    cases.append(scenario(package([E('SET',dst_s=1,immediate=a),E('SET',dst_s=2,immediate=b),E('BR_COMPARE',a_s=1,b_s=2,immediate=predicate,target=5),E('SET',dst_s=3,immediate=11),E('JUMP',target=6),E('SET',dst_s=3,immediate=22),HALT()])))
  cases.append(scenario(package([E('CALL',target=4),HALT(),E('NOP'),E('NOP'),E('CALL',target=7),E('RET'),E('NOP'),E('CALL',target=10),E('RET'),E('NOP'),E('CALL',target=13),E('RET'),E('NOP'),E('SET',dst_s=9,immediate=99),E('RET')])))
  self.replay(cases)
 def test_runtime_payload_and_capacity_faults(self):
  words=[E('KERNEL',kernel=0,dst_v=2,a_v=0,b_v=1,length_mode=2,immediate=asm.service_immediate(length=33)),HALT()]
  small=[dict(base=0,capacity=33),dict(base=10,capacity=1),dict(base=20,capacity=33)]
  cases=[scenario(package(words,vectors=small))]
  bad_a=[dict(x) for x in small];bad_a[0]['capacity']=32
  cases.append(scenario(package(words,vectors=bad_a,binding=(1<<32)-1)))
  bad_d=[dict(x) for x in small];bad_d[2]['capacity']=32
  cases.append(scenario(package(words,vectors=bad_d,binding=(1<<32)-1)))
  cases += [scenario(package([E('DIV',dst_s=1,immediate=1),HALT()])),scenario(package([HALT(immediate=256)])),scenario(package([E('SET',dst_s=1,immediate=97),E('BUILD_B',a_s=1),HALT()]))]
  for kind,a,b in [('ADD64',-(1<<63),-1),('SUB64',(1<<63)-1,-1)]:cases.append(scenario(package([E('SET',dst_s=1,immediate=a),E('SET',dst_s=2,immediate=b),E(kind,dst_s=3,a_s=1,b_s=2),HALT()])))
  self.replay(cases)
 def test_union_packed_capacity_and_single_descriptor_stop(self):
  imm=asm.service_immediate(k_s=1,support_v=3,aux_v=4,support_length_s=2,aux_length_s=3)
  words=[E('SET',dst_s=1,immediate=96),E('SET',dst_s=2,immediate=80),E('SET',dst_s=3,immediate=16),E('KERNEL',kernel=9,dst_v=2,a_v=0,b_v=0,flag_s=29,target=1,length_mode=1,immediate=imm),HALT(dst_v=2,a_v=0,b_v=3)]
  vectors=[dict(base=0,capacity=1),dict(base=1,capacity=1),dict(base=2,capacity=96),dict(base=5,capacity=96),dict(base=8,capacity=96)]
  self.replay([scenario(package(words,vectors=vectors),[dict(count=88)]),scenario(package([E('FAIL',immediate=3)],vectors=[dict(base=17,capacity=33)]))])
 def test_rescale_request_identity_fault_cancel_and_reserved_fields(self):
  words=[E('SET',dst_s=1,immediate=-(1<<47)),E('RESCALE',dst_s=2,a_s=1),HALT()]
  cases=[scenario(package(words),[dict(data=-(1<<25))]),scenario(package(words),[dict(data=3)],cancel=2)]
  for reply in [dict(fault=4),dict(corrupt=1)]:cases.append(scenario(package(words),[reply]))
  cases.append(scenario(package([E('RESCALE',dst_s=0),HALT()])))
  bad=E('RESCALE',dst_s=1)|1<<asm.offsets(asm.ABI['fields'])['b_s'][0]
  cases.append(scenario(package([bad,HALT()])))
  self.replay(cases)
 def test_slice_replace_capacities_empty_endpoint_and_range_rejection(self):
  cases=[]
  for op in (11,12):
   for n,start,size,capacity in [(1024,31,33,33),(1024,1024,0,1),(1024,1023,2,2),(33,32,2,2),(33,0,33,32)]:
    vectors=[dict(base=0,capacity=n),dict(base=32,capacity=capacity),dict(base=64,capacity=n if op==12 else max(1,size))]
    imm=asm.service_immediate(length=n,index_s=1,aux_length_s=2,aux_v=1)
    words=[E('SET',dst_s=1,immediate=start),E('SET',dst_s=2,immediate=size),E('KERNEL',kernel=op,a_v=0,b_v=0,dst_v=2,length_mode=2,immediate=imm),HALT(dst_v=2,a_v=0,b_v=1)]
    cases.append(scenario(package(words,vectors=vectors),[dict(count=size)]))
  self.replay(cases)
 def test_factor_modes_coordinates_and_only_required_vector_capacity(self):
  cases=[]
  for op,size,index,start,flags,cap in [(13,33,0,0,0,1),(14,32,16,1,0,32),(15,17,32,0,1,17),
      (14,33,16,1,0,33),(15,18,32,0,1,18),(14,1,17,0,0,1),(13,32,0,0,0,1),(14,1,0,0,2,1),
      (14,33,0,0,0,32),(15,33,0,0,0,32)]:
   vectors=[dict(base=0,capacity=1),dict(base=1,capacity=cap if op==15 else 1),dict(base=5,capacity=cap if op==14 else 1)]
   imm=asm.service_immediate(length=size,dense=1,support_length_s=28,index_s=1,aux_length_s=2,flags=flags)
   words=[E('SET',dst_s=28,immediate=17),E('SET',dst_s=1,immediate=index),E('SET',dst_s=2,immediate=start),E('KERNEL',kernel=op,a_v=1,dst_v=2,length_mode=2,immediate=imm),HALT()]
   cases.append(scenario(package(words,vectors=vectors),[dict(count=17 if op==13 else size)]))
  self.replay(cases)
 def test_factor_project_update_compact_phase_zero_alpha_and_rejections(self):
  """Feature-5 compact context remains covered alongside the new opcode-21 cases."""
  def make(*,alpha_register=0,alpha_value=0,descriptor=31,contexts=None,bind_a=0,bind_b=0,kernel=20):
   fields=dict(dense=1,template=1,support_length_s=28,index_s=1,aux_length_s=2,length=33)
   words=[E('SET',dst_s=28,immediate=9),E('SET',dst_s=1,immediate=1),E('SET',dst_s=2,immediate=0)]
   if alpha_register:words.append(E('SET',dst_s=alpha_register,immediate=alpha_value))
   words += [E('KERNEL',kernel=kernel,a_v=1,a_s=alpha_register,length_mode=2,immediate=asm.service_immediate(**fields)),HALT()]
   pkg=package(words,vectors=[dict(base=0,capacity=1),dict(base=1,capacity=33)])
   pkg['templates']=[dict(descriptor=7,bind_a=0,bind_b=0,contexts=[296]*32),
                     dict(descriptor=descriptor,bind_a=bind_a,bind_b=bind_b,contexts=[297,296,291]+[0]*29 if contexts is None else contexts)]
   return pkg
  cases=[scenario(make(),[dict(count=0,nz=0)])] # R0 alpha=0 is legal and produces no public candidate.
  cases += [scenario(make(alpha_register=3,alpha_value=1<<26)),
            scenario(make(bind_a=1),load_mutator=lambda records: records),
            scenario(make(contexts=[297,296,291|(1<<37)]+[0]*29),load_mutator=lambda records: records),
            scenario(make(kernel=0))]
  self.replay(cases)
 def test_scalar_insert_inert_template_scalar_fit_and_rejections(self):
  """Opcode 21 accepts an inert nonzero template and rejects before KREQ on every malformed form."""
  def make(*,length=1,index=0,scalar_register=0,scalar_value=0,descriptor=0,contexts=None,
           bind_a=0,bind_b=0,unused_base=0,**change):
   fields=dict(length=length,index_s=1,template=1)
   fields.update(change.pop('immediate',{}))
   words=[E('SET',dst_s=1,immediate=index)]
   if scalar_register:words.append(E('SET',dst_s=scalar_register,immediate=scalar_value))
   kernel_fields=dict(kernel=21,a_v=1,b_v=0,dst_v=2,a_s=scalar_register,length_mode=2,
                      immediate=asm.service_immediate(**fields))
   kernel_fields.update(change)
   words += [E('KERNEL',**kernel_fields),HALT(dst_v=2,a_v=1,b_v=0)]
   # Keep malformed length=1025 as an execution-validation case: descriptor
   # capacities themselves stay loader-legal so it cannot be misclassified.
   capacity=min(length,1024)
   vectors=[dict(base=unused_base,capacity=1),dict(base=73,capacity=capacity),dict(base=211,capacity=capacity)]
   pkg=package(words,vectors=vectors)
   pkg['templates']=[dict(descriptor=7,bind_a=0,bind_b=0,contexts=[296]*32),
                     dict(descriptor=descriptor,bind_a=bind_a,bind_b=bind_b,
                          contexts=[0]*32 if contexts is None else contexts)]
   return pkg
  valid=[scenario(make(),[dict(count=1,nz=0)]),
         # Descriptor zero is canonically unused, not required to be based at
         # physical address zero.  This holds the program-side ABI boundary.
         scenario(make(unused_base=47),[dict(count=1,nz=0)]),
         scenario(make(length=1024,index=1023,scalar_register=2,scalar_value=(1<<26)-1),[dict(count=1024,nz=1)]),
         scenario(make(length=1024,index=0,scalar_register=2,scalar_value=-(1<<26)),[dict(count=1024,nz=1)])]
  bad=[make(index=-1),make(length=1024,index=1024),make(length=1025),
       make(scalar_register=2,scalar_value=1<<26),make(scalar_register=2,scalar_value=-(1<<26)-1),
       make(descriptor=1),make(contexts=[1]+[0]*31),make(bind_a=1),make(bind_b=1),
       make(b_v=1),make(b_s=2),make(dst_s=2),make(flag_s=2),make(target=1),
       make(immediate=dict(dense=1)),make(immediate=dict(flags=1)),make(immediate=dict(support_v=1)),
       make(immediate=dict(aux_v=1)),make(scalar_register=2,scalar_value=1,immediate=dict(k_s=2)),
       make(scalar_register=2,scalar_value=1,immediate=dict(support_length_s=2)),
       make(scalar_register=2,scalar_value=1,immediate=dict(aux_length_s=2)),
       make(scalar_register=2,scalar_value=1,shift_s=2)]
  # Inert-template descriptor, context, and bind corruption is rejected by
  # the image loader itself.  The remaining cases must fail in EXEC before
  # issuing KREQ, so they receive no mock response.
  rejected=[scenario(pkg,load_mutator=(lambda rows:rows) if 5<=n<=8 else None)
            for n,pkg in enumerate(bad)]
  # The reference controller model rejects before creating a mock kernel event;
  # a spurious RTL dispatch would then wait forever because the test provides no response.
  self.assertTrue(all(model is None or not model['events'] for _,model,_ in rejected))
  self.replay(valid+rejected)
 def test_range_template_offsets_selected_masks_capacity_and_canonical_fields(self):
  """Opcode22 proves request offsets/capacities before the transport implementation consumes it."""
  from compiler.v4.stream_program import encode_context
  def make(*,length=33,a_offset=0,b_offset=0,a_capacity=1024,b_capacity=1024,dst_capacity=None,
           descriptor=7,contexts=None,bind_a=0,bind_b=0,register3=0,**change):
   fields=dict(length=length,index_s=1,aux_length_s=2,template=1)
   fields.update(change.pop('immediate',{}))
   words=[E('SET',dst_s=1,immediate=a_offset),E('SET',dst_s=2,immediate=b_offset)]
   if register3:words.append(E('SET',dst_s=3,immediate=register3))
   kernel_fields=dict(kernel=22,a_v=0,b_v=1,dst_v=2,length_mode=2,immediate=asm.service_immediate(**fields))
   kernel_fields.update(change)
   words += [E('KERNEL',**kernel_fields),HALT(dst_v=2,a_v=0,b_v=1)]
   if dst_capacity is None:dst_capacity=length
   pkg=package(words,vectors=[dict(base=0,capacity=a_capacity),dict(base=64,capacity=b_capacity),dict(base=128,capacity=dst_capacity)])
   template=dict(descriptor=descriptor,bind_a=bind_a,bind_b=bind_b,contexts=[296]*32 if contexts is None else contexts)
   pkg['templates']=[pkg['templates'][0],template]
   return pkg
  valid=[]
  for length,a_offset,b_offset in ((1,0,0),(31,1,31),(32,31,32),(33,32,33),(64,33,95),(96,95,1),(128,1,95),(1024,0,0)):
   valid.append(scenario(make(length=length,a_offset=a_offset,b_offset=b_offset),[dict(count=length,nz=1)]))
  # MOV(IMM) selects neither packed source: both offsets must then be zero.
  unused=[encode_context(op='MOV',mode=1,src_a='IMM',immediate=7)]*32
  valid.append(scenario(make(length=33,a_capacity=1,b_capacity=1,contexts=unused),[dict(count=33,nz=1)]))
  # Canonical scalar fields constrain their resolved RF values, not the RF
  # index encoding: a nonzero register index containing zero is legal.
  valid.append(scenario(make(immediate=dict(k_s=3,support_length_s=3),shift_s=3),[dict(count=33,nz=1)]))
  # Bound A is not read from public storage and must use offset0; unbound B
  # remains independently offset/capacity checked.
  valid.append(scenario(make(a_offset=0,b_offset=33,a_capacity=1,bind_a=(1<<32)-1),[dict(count=33,nz=1)]))
  acc_contexts=[297]*32
  # Public output capacity follows the loaded descriptor rather than L.
  valid += [scenario(make(length=64,dst_capacity=1,descriptor=7|(2<<3),contexts=acc_contexts),[dict(count=0,nz=1)]),
            scenario(make(length=1024,dst_capacity=1,descriptor=7|(2<<3),contexts=acc_contexts),[dict(count=0,nz=1)]),
            scenario(make(length=64,dst_capacity=32,descriptor=7|(1<<3),contexts=acc_contexts),[dict(count=32,nz=1)]),
            scenario(make(length=31,dst_capacity=31,descriptor=7|(1<<3),contexts=acc_contexts),[dict(count=31,nz=1)])]
  # The capacity proof follows the highest selected packed position, not L:
  # at L=1024 only lane0 needs element992, so offset1 remains legal; lane31
  # needs element1023 and makes that same offset overflow the public domain.
  only_a0=[encode_context(op='MOV',mode=1,src_a='A')]+unused[1:]
  only_a31=unused[:31]+[encode_context(op='MOV',mode=1,src_a='A')]
  valid.append(scenario(make(length=1024,a_offset=1,b_offset=0,contexts=only_a0),[dict(count=1024,nz=1)]))
  bad=[make(a_offset=-1),make(a_offset=1<<63),make(a_offset=1024),make(b_offset=-1),make(b_offset=1<<63),make(b_offset=1024),
       make(length=33,a_offset=1,a_capacity=33),make(length=33,b_offset=1,b_capacity=33),
       make(length=33,dst_capacity=32),make(descriptor=6),make(contexts=unused,a_offset=1),make(contexts=unused,b_offset=1),
       make(a_offset=1,a_capacity=1,bind_a=(1<<32)-1),
       make(immediate=dict(dense=1)),make(immediate=dict(transpose=1)),make(immediate=dict(r4=1)),
       make(immediate=dict(store_mode=1)),make(immediate=dict(flags=1)),make(immediate=dict(k_s=3),register3=1),
       make(immediate=dict(support_v=1)),make(immediate=dict(aux_v=1)),make(immediate=dict(support_length_s=3),register3=1),
        make(length=1024,a_offset=1,b_offset=0,contexts=only_a31),
       make(length=64,dst_capacity=31,descriptor=7|(1<<3),contexts=acc_contexts),
       make(shift_s=3,register3=1),make(target=1)]
  rejected=[scenario(pkg) for pkg in bad]
  # Reserved descriptor/context bits are rejected by the ordered image loader,
  # before an opcode22 request can be exposed.
  rejected += [scenario(make(descriptor=7|(1<<11)),load_mutator=lambda rows:rows),
               scenario(make(contexts=[296|(1<<37)]+[296]*31),load_mutator=lambda rows:rows)]
  self.assertTrue(all(model is None or not model['events'] for _,model,_ in rejected))
  self.replay(valid+rejected)
 def test_factor_extend_canonical_template_and_rejections(self):
  def make(*,descriptor=0,contexts=None,bind_a=0,bind_b=0,**change):
   fields=dict(dense=1,template=1,support_length_s=28,index_s=1,aux_length_s=2)
   fields.update(change.pop('immediate',{}))
   words=[E('SET',dst_s=28,immediate=4),E('SET',dst_s=1,immediate=2),
          E('KERNEL',kernel=19,length_mode=0,immediate=asm.service_immediate(**fields),**change),HALT()]
   pkg=package(words,vectors=[dict(base=0,capacity=1)])
   pkg['templates']=[dict(descriptor=7,bind_a=0,bind_b=0,contexts=[296]*32),
                     dict(descriptor=descriptor,bind_a=bind_a,bind_b=bind_b,contexts=[0]*32 if contexts is None else contexts)]
   return pkg
  cases=[scenario(make(),[dict(count=4)])]
  cases += [scenario(make(descriptor=1),load_mutator=lambda records: records),scenario(make(contexts=[1]+[0]*31),load_mutator=lambda records: records),
            scenario(make(immediate=dict(flags=1))),scenario(make(immediate=dict(aux_length_s=1))),
            scenario(make(a_s=1)),scenario(make(flag_s=1)),scenario(make(target=1)),
            scenario(make(immediate=dict(template=0)))]
  self.replay(cases)
if __name__=='__main__':unittest.main()
