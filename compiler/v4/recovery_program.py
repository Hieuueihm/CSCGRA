"""Revision-two generic program assembly and package export.

Complete recovery compilers are linked only after their numeric subroutines
are available. A missing QR program is an explicit error, never LSQR fallback.
"""
import hashlib
import json
from pathlib import Path
from compiler.v4.stream_program import encode_context,encode_descriptor

ROOT=Path(__file__).resolve().parents[2]
ABI_PATH=ROOT/'config/v4_program_interface.json'
ABI=json.loads(ABI_PATH.read_text())
KERNEL=json.loads((ROOT/'config/v4_kernel_interface.json').read_text())

def offsets(fields):
    result={};bit=0
    for name,width in fields.items():result[name]=(bit,width);bit+=width
    return result

def pack(fields,values):
    if values.keys()-fields.keys():raise ValueError('unknown instruction field')
    result=0
    for name,(bit,width) in offsets(fields).items():
        value=values.get(name,0)
        if not isinstance(value,int) or not 0<=value<1<<width:raise ValueError(f'{name} does not fit')
        result|=value<<bit
    return result

def unpack(fields,word):
    if not isinstance(word,int) or not 0<=word<1<<sum(fields.values()):raise ValueError('invalid word width')
    return {name:(word>>bit)&((1<<width)-1) for name,(bit,width) in offsets(fields).items()}

def encode(kind,**fields):
    name=kind if isinstance(kind,str) else next((k for k,v in ABI['kinds'].items() if v==kind),None)
    if name not in ABI['kinds'] or name=='SUCCESS':raise ValueError('unsupported program instruction')
    if set(fields)-set(ABI['allowed_fields'][name]):raise ValueError('unused instruction field')
    if fields.get('immediate',0)<0:fields['immediate']&=(1<<64)-1
    return pack(ABI['fields'],dict(fields,kind=ABI['kinds'][name]))

def decode(word):return unpack(ABI['fields'],word)

def service_immediate(**fields):return pack(ABI['service_immediate_fields'],fields)

class Assembler:
    def __init__(self):
        self.instructions=[];self.labels={};self.fixups=[];self.constants=[];self.templates=[];self.vectors=[]
    def label(self,name):
        if name in self.labels:raise ValueError('duplicate label')
        self.labels[name]=len(self.instructions)
    def emit(self,kind,**fields):self.instructions.append((kind,fields))
    def branch(self,kind,target,**fields):
        self.fixups.append((len(self.instructions),target));self.emit(kind,**fields)
    def constant(self,value):
        if not -(1<<63)<=int(value)<1<<64:raise ValueError('constant does not fit64')
        self.constants.append(int(value)&((1<<64)-1));return len(self.constants)-1
    def vector(self,name,capacity,base=None):
        if any(v['name']==name for v in self.vectors):raise ValueError('duplicate vector')
        if base is None:base=max([0,*[v['base']+(v['capacity']+31)//32 for v in self.vectors]])
        if not 1<=capacity<=1024 or not 0<=base or base+(capacity+31)//32>480:raise ValueError('vector exceeds public pool')
        self.vectors.append(dict(name=name,base=base,capacity=capacity));return len(self.vectors)-1
    def template(self,name,op,output='EACH',bind_a=0,bind_b=0,src_a='A',src_b='B',immediate=0,shift=0,mode=1):
        descriptor=encode_descriptor(inc_a=1,inc_b=1,inc_dst=1,output_kind=output,shift=shift)
        context=encode_context(op=op,mode=mode,src_a=src_a,src_b=src_b,immediate=immediate)
        self.templates.append(dict(name=name,descriptor=descriptor,bind_a=bind_a,bind_b=bind_b,contexts=[context]*32))
        return len(self.templates)-1
    def finish(self):
        for index,label in self.fixups:
            if label not in self.labels:raise ValueError('unresolved subroutine/branch: '+label)
            self.instructions[index][1]['target']=self.labels[label]
        words=[encode(kind,**fields) for kind,fields in self.instructions]
        package=dict(revision=2,program=words,labels=self.labels,constants=self.constants,templates=self.templates,vectors=self.vectors,
                     scope='generic program package; full-algorithm qualification requires actual service execution')
        validate_package(package);return package

def validate_package(package):
    if package['revision']!=2:raise ValueError('program revision mismatch')
    for key,minimum,maximum in [('program',1,1024),('templates',1,16),('vectors',1,32),('constants',0,1024)]:
        if not minimum<=len(package[key])<=maximum:raise ValueError('invalid '+key+' count')
    for word in package['program']:
        fields=decode(word)
        if fields['reserved']:raise ValueError('reserved program bits')
        name=next((k for k,v in ABI['kinds'].items() if v==fields['kind']),None)
        if name is None or name=='SUCCESS':raise ValueError('unsupported instruction')
        used={k:v for k,v in fields.items() if k!='kind' and v}
        if used.keys()-set(ABI['allowed_fields'][name]):raise ValueError('unused instruction payload')
        if name in ('CALL','JUMP','BR_ZERO','BR_NONZERO','BR_GE','BR_COMPARE') and fields['target']>=len(package['program']):raise ValueError('branch outside program')
    for vector in package['vectors']:
        if not 1<=vector['capacity']<=1024 or vector['base']<0 or vector['base']+(vector['capacity']+31)//32>480:raise ValueError('invalid vector descriptor')
    return package

def load_records(package):
    validate_package(package);records=[]
    records.extend((0,i,w) for i,w in enumerate(package['program']))
    for tid,t in enumerate(package['templates']):
        metadata=t['descriptor']|(t['bind_a']<<32)|(t['bind_b']<<64)
        records.append((1,tid*33,metadata))
        records.extend((1,tid*33+lane+1,word) for lane,word in enumerate(t['contexts']))
    records.extend((2,i,v['base']|(v['capacity']<<9)) for i,v in enumerate(package['vectors']))
    records.extend((3,i,value) for i,value in enumerate(package['constants']))
    return [(kind,index,word,int(i==len(records)-1)) for i,(kind,index,word) in enumerate(records)]

def export_package(package,directory):
    validate_package(package);directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    records=load_records(package)
    text=''.join(f'{kind:x} {index:04x} {word:032x} {last:x}\n' for kind,index,word,last in records)
    (directory/'load.txt').write_text(text)
    (directory/'program.hex').write_text(''.join(f'{w:032x}\n' for w in package['program']))
    sources=[Path(__file__),ABI_PATH,ROOT/'config/v4_kernel_interface.json',ROOT/'config/v4_stream_interface.json']
    metadata=dict(package,load_sha256=hashlib.sha256(text.encode()).hexdigest(),
                  source_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                  decoded=[decode(w) for w in package['program']])
    (directory/'package.json').write_text(json.dumps(metadata,indent=2)+'\n')
    names={v:k for k,v in ABI['kinds'].items()}
    (directory/'program.txt').write_text('\n'.join(f'{pc:04d} {names[decode(w)["kind"]]} {decode(w)}' for pc,w in enumerate(package['program']))+'\n')
    return metadata
