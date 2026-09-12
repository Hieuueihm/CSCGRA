"""Generic service instruction encoder and model-ordered LSQR candidate program."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ABI=json.loads((ROOT/'config/v4_solver_program.json').read_text())
FIELDS=ABI['fields'];KINDS=ABI['kinds'];KERNELS=ABI['kernels']
OFFSETS={};offset=0
for name,width in FIELDS.items():OFFSETS[name]=offset;offset+=width
assert offset==128

def encode(kind,**fields):
    fields=dict(fields,kind=KINDS[kind] if isinstance(kind,str) else kind)
    if set(fields)-set(FIELDS):raise ValueError('unknown instruction field')
    result=0
    for name,value in fields.items():
        if not isinstance(value,int) or not 0<=value<(1<<FIELDS[name]):raise ValueError((name,value))
        result|=value<<OFFSETS[name]
    return result

def decode(word):return {name:(word>>OFFSETS[name])&((1<<width)-1) for name,width in FIELDS.items()}

def lsqr_program():
    """Return 256 words and labels; every numerical branch is executed in RTL."""
    program=[];labels={};fixups=[]
    def label(name):labels[name]=len(program)
    def emit(kind,**fields):program.append((kind,fields))
    def branch(kind,target,**fields):fixups.append((len(program),target));emit(kind,**fields)
    def kernel(name,dst=0,a=0,b=0,scalar=0,second=0,out=0,flag=0,length=1,trans=0,shift=0):
        emit('KERNEL',kernel=KERNELS[name],dst_v=dst,a_v=a,b_v=b,a_s=scalar,b_s=second,
             dst_s=out,flag_s=flag,length_mode=length,immediate=trans,shift_s=shift)
    def mov(dst,src):emit('MOV',dst_s=dst,a_s=src)
    def sqrt_energy(vector,dst,length=1):
        kernel('ENERGY',a=vector,out=18,length=length);emit('SQRT',dst_s=dst,a_s=18)
    def norm(vector,dst,normreg,length=1,flag=0):
        emit('RECIP_PREP',a_s=normreg,dst_s=24,shift_s=17)
        emit('DIV',dst_s=16,a_s=24,b_s=normreg)
        kernel('NORMALIZE',dst=dst,a=vector,scalar=16,shift=17,length=length,flag=flag)
    def div(dst,a,b):emit('DIV',dst_s=dst,a_s=a,b_s=b)
    def mul(dst,a,b):kernel('SCALAR_MUL',scalar=a,second=b,out=dst)
    def certificate():
        kernel('NARROW_X',dst=10,a=1)
        kernel('GEMV_B',dst=6,a=10,length=0)
        kernel('SUB',dst=11,a=0,b=6,length=0)
        kernel('GEMV_B',dst=12,a=11,trans=1)
        kernel('ENERGY',a=12,out=21)
        emit('CERT',dst_s=22,a_s=21,b_s=19)
        branch('BR_NONZERO','success',a_s=22)
    kernel('ZERO',dst=1)
    kernel('GEMV_B',dst=13,a=0,trans=1)
    kernel('ENERGY',a=13,out=19)
    sqrt_energy(0,1,0);branch('BR_ZERO','final_cert',a_s=1)
    norm(0,2,1,0);kernel('GEMV_B',dst=3,a=2,trans=1)
    sqrt_energy(3,2);branch('BR_ZERO','final_cert',a_s=2)
    norm(3,3,2);kernel('COPY',dst=4,a=3);mov(3,1);mov(4,2)
    label('loop')
    kernel('GEMV_B',dst=5,a=3,length=0)
    kernel('SCALE',dst=6,a=2,scalar=2,length=0)
    kernel('SUB',dst=5,a=5,b=6,length=0)
    sqrt_energy(5,5,0);branch('BR_ZERO','zero_beta',a_s=5)
    norm(5,7,5,0);kernel('GEMV_B',dst=8,a=7,trans=1)
    kernel('SCALE',dst=9,a=3,scalar=5);kernel('SUB',dst=8,a=8,b=9)
    sqrt_energy(8,6);branch('BR_ZERO','zero_alpha',a_s=6)
    norm(8,8,6,flag=23);branch('JUMP','givens')
    label('zero_beta');kernel('ZERO',dst=7,length=0);emit('SET',dst_s=6)
    label('zero_alpha');kernel('ZERO',dst=8,flag=23)
    label('givens');kernel('SCALAR_ENERGY',scalar=4,second=5,out=18)
    emit('SQRT',dst_s=7,a_s=18);branch('BR_ZERO','final_cert',a_s=7)
    div(8,4,7);div(9,5,7);mul(10,6,9);mul(24,8,6);emit('NEG',dst_s=11,a_s=24)
    mul(12,8,3);mul(13,9,3);div(14,12,7);div(15,10,7)
    kernel('SCALE',dst=9,a=4,scalar=14);kernel('ADD',dst=1,a=1,b=9)
    kernel('SCALE',dst=9,a=4,scalar=15);kernel('SUB',dst=4,a=8,b=9)
    emit('INC',dst_s=25,a_s=25)
    certificate();branch('BR_ZERO','fail',a_s=5);branch('BR_ZERO','fail',a_s=23)
    branch('BR_GE','fail',a_s=25,b_s=30)
    kernel('COPY',dst=3,a=8);kernel('COPY',dst=2,a=7,length=0)
    mov(2,6);mov(3,13);mov(4,11);branch('JUMP','loop')
    label('final_cert');certificate();branch('JUMP','fail')
    label('success');emit('SUCCESS')
    label('fail');emit('FAIL')
    for pc,target in fixups:program[pc][1]['target']=labels[target]
    words=[encode(kind,**fields) for kind,fields in program]
    if len(words)>256:raise ValueError('program capacity')
    return words+[encode('FAIL')]*(256-len(words)),labels


def export_program(directory):
    """Export reviewable numerical words plus provenance; does not load hardware."""
    import hashlib
    directory=Path(directory)
    directory.mkdir(parents=True,exist_ok=True)
    words,labels=lsqr_program()
    meaningful=labels['fail']+1
    hex_text=''.join(f'{word:032x}\n' for word in words)
    hex_path=directory/'program.hex'
    hex_path.write_text(hex_text,encoding='ascii',newline='\n')
    names={value:name for name,value in KINDS.items()}
    kernels={value:name for name,value in KERNELS.items()}
    decoded=[];lines=['LSQR generic service program',f'{meaningful} instructions; {len(words)} words including FAIL padding','']
    labels_at={pc:name for name,pc in labels.items()}
    for pc,word in enumerate(words):
        fields=decode(word)
        decoded.append(dict(pc=pc,word_hex=f'{word:032x}',kind_name=names[fields['kind']],
                            padding=pc>=meaningful,fields=fields))
        if pc>=meaningful:continue
        if pc in labels_at:lines.append(labels_at[pc]+':')
        kind=names[fields['kind']]
        if kind=='KERNEL':
            kernel=kernels[fields['kernel']]
            if kernel in ('SCALAR_MUL','SCALAR_ENERGY'):
                operands=f"s{fields['dst_s']} <- {kernel}(s{fields['a_s']},s{fields['b_s']})"
            elif kernel=='ENERGY':operands=f"s{fields['dst_s']} <- ENERGY(v{fields['a_v']})"
            else:
                operands=f"v{fields['dst_v']} <- {kernel}"
                if kernel!='ZERO':operands+=f" v{fields['a_v']}"
                if kernel in ('ADD','SUB'):operands+=f",v{fields['b_v']}"
                if kernel in ('SCALE','NORMALIZE'):operands+=f" scalar=s{fields['a_s']}"
                if kernel=='NORMALIZE':operands+=f" exponent=s{fields['shift_s']}"
                if kernel=='GEMV_B' and fields['immediate']&1:operands+=' transpose'
            if kernel not in ('SCALAR_MUL','SCALAR_ENERGY'):
                operands+=' length='+('rows','columns','immediate')[fields['length_mode']]
            if fields['flag_s']:operands+=f" nonzero->s{fields['flag_s']}"
        elif kind in ('BR_ZERO','BR_NONZERO','BR_GE','JUMP'):
            target=fields['target']
            operands=f"s{fields['a_s']},s{fields['b_s']} -> {target:03d} {labels_at.get(target,'')}"
        else:
            operands=' '.join(f'{name}={value}' for name,value in fields.items() if value and name not in ('kind','reserved'))
        lines.append(f'{pc:03d}  {kind:<12} {operands}'.rstrip())
    lines.extend(['',f'{meaningful:03d}..255  FAIL (padding)',''])
    text_path=directory/'program.txt'
    text_path.write_text('\n'.join(lines),encoding='utf-8',newline='\n')
    source_paths=[ROOT/'compiler/v4/solver_program.py',ROOT/'config/v4_solver_program.json']
    manifest=dict(schema_version=1,scope='LSQR candidate generic service program; export is not execution evidence',
                  word_count=len(words),meaningful_word_count=meaningful,word_bits=128,
                  hex_encoding='256 lines of 32 hexadecimal digits; numerical words; least-significant field first',
                  labels=labels,abi=ABI,source_sha256={path.relative_to(ROOT).as_posix():hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths},
                  image_sha256=hashlib.sha256(hex_path.read_bytes()).hexdigest(),
                  packed_little_endian_sha256=hashlib.sha256(b''.join(word.to_bytes(16,'little') for word in words)).hexdigest(),
                  disassembly_sha256=hashlib.sha256(text_path.read_bytes()).hexdigest(),instructions=decoded)
    (directory/'program.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    return manifest


def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True,help='directory for program.hex, program.json and program.txt')
    args=parser.parse_args()
    manifest=export_program(args.output)
    print(f"Exported {manifest['word_count']} words ({manifest['meaningful_word_count']} instructions) to {args.output.resolve()}")


if __name__=='__main__':main()
