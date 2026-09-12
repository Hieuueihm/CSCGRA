"""Generic shared kernel: independent integers and real live Phi/B memory in Vivado."""
import hashlib
import json
from pathlib import Path
import random
import re
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl,run_rtl
ROOT=Path(__file__).resolve().parents[2]
RUNS=[]
SOURCE_EXTRAS=["verification/v4/test_stream_kernel_rtl.py","verification/v4/stream/tb_stream_kernel_copy.sv","docs/v4/architecture/RESIDENT_CHAIN.md","docs/v4/architecture/SCALAR_INSERT.md","docs/v4/architecture/RANGE_TEMPLATE.md","config/v4_kernel_interface.json","config/v4_program_interface.json","rtl/v4/include/kernel_interface.vh","rtl/v4/include/program_interface.vh","scripts/v4/xsim.py","docs/v4/architecture/STREAM_SYSTEM_CONTRACT.md","docs/v4/architecture/FACTOR_SERVICE.md","docs/v4/architecture/FACTOR_PANEL.md"]
MASK=(1<<32)-1
SOURCES=["rtl/v4/compute/stream_kernel.sv","rtl/v4/dataflow/support_service.sv",'rtl/v4/dataflow/factor_service.sv','rtl/v4/dataflow/factor_panel_service.sv','rtl/v4/memory/factor_store.sv',"rtl/v4/compute/stream_fabric.sv",
 "rtl/v4/compute/stream_array.sv","rtl/v4/compute/stream_pe.sv",
 "rtl/v4/memory/stream_vector_store.sv","rtl/v4/dataflow/operator_frame_feeder.sv","rtl/v4/dataflow/range_reader.sv",
 "rtl/v4/memory/live_operator_memory.sv","rtl/v4/memory/paired_support_store.sv",
 "rtl/v4/operator/phi_sign_generator.sv","rtl/v4/memory/phi_sign_cache.sv",
 "rtl/v4/dataflow/phi_reader.sv","rtl/v4/dataflow/support_builder.sv",
 "verification/v4/stream/tb_stream_kernel.sv"]

def pack(values,width=27):
 return sum((v&((1<<width)-1))<<(width*i) for i,v in enumerate(values))
def rounded(value,shift):
 return (-1 if value<0 else 1)*((abs(value)+(1<<(shift-1)))>>shift) if shift else value

def fixture(op=0,length=33,rows=7,cols=3,dense=1,trans=0,r4=0,shift=22,store=0,
            scalar=1<<21,cancel=0,generation=3,destination=128,values=None,source_missing=False,context=None):
 rng=random.Random(912+rows*cols+length)
 a=values if values is not None else [rng.randrange(-1000,1001) for _ in range(length)]
 b=[rng.randrange(-1000,1001) for _ in range(length)]
 context={0:296,1:265,2:297,3:33,4:259}[op] if context is None else context
 bind_a=0;bind_b=MASK if op==0 else 0
 descriptor=5;frames=(length+31)//32;tail=(1<<(length%32))-1 if length%32 else MASK
 matrix=[];fills=[]
 if op==1:
  if dense:matrix=[[rng.randrange(-131072,131072) for _ in range(cols)] for _ in range(rows)]
  else:
   matrix=[[0]*cols for _ in range(rows)];state=0x12345678
   for col in range(cols):
    for row in range(rows):
     matrix[row][col]=4096 if state&1 else -4096
     state=(state>>1)^(0x80200003 if state&1 else 0)
  outputs=cols if trans else rows
  result=[rounded(sum((matrix[k][o] if trans else matrix[o][k])*a[k] for k in range(length)),16) for o in range(outputs)]
  if dense:
   for col in range(cols):
    for block in range((rows+31)//32):
     data=[matrix[row][col] for row in range(block*32,min(rows,block*32+32))]
     fills.append(f"{col} {block} {(1<<len(data))-1:x} {pack(data,18):x}")
 elif op==0:result=[rounded(v*scalar,22) for v in a]
 elif op==2:result=[rounded(v*scalar,shift) for v in a]
 elif op==3:
  sh={0:0,1:2,2:8}[store];result=[rounded(v,sh)<<sh for v in a]
 else:result=[(-1 if v<0 else 1)*max(0,abs(v)-scalar) for v in a]
 fault=0
 if op==3:
  sh={0:0,1:2,2:8}[store];bits={0:27,1:24,2:18}[store]
  if any(not -(1<<(bits-1))<=rounded(v,sh)<(1<<(bits-1)) for v in a):fault=4
 if any(not -(1<<26)<=v<(1<<26) for v in result):fault=4
 if op==1 and generation!=3:fault=7
 if source_missing:fault=5
 if op==0 and context==297:fault=1
 writes=[];reads=[]
 for block in range((length+31)//32):
  data=a[block*32:block*32+32]
  if source_missing and block+1==(length+31)//32:continue
  writes.append(f"{block} {(1<<len(data))-1:x} {pack(data):x}")
 for block in range((len(result)+31)//32):
  data=result[block*32:block*32+32];mask=(1<<len(data))-1
  if destination+block>=frames:writes.append(f"{destination+block} {mask:x} {pack([17]*len(data)):x}")
  reads.append(f"{destination+block} {mask:x} {2 if fault or cancel else 0} {0 if fault or cancel else pack(data):x}")
 header=f"{op} {rows} {cols} {dense} {trans} {r4} {length} {shift} {store} {scalar&((1<<27)-1):x} {scalar&((1<<27)-1):x} {bind_a:x} {bind_b:x} {descriptor:x} {frames} {tail:x} {fault} 0 {int(any(result)) if not fault else 0} {cancel} {len(writes)} {len(reads)} {len(fills)} {generation} {destination} {pack([context]*32,64):x}"
 return "\n".join([header+" 0 0 0 0 0 0 0 0",*fills,*writes,*reads])

def support_fixture(op,length=33,k=8,support=None,aux=None,flags=0,index=0,destination=128,cancel=0,values=None,source_missing=False):
 support=[] if support is None else support
 aux=[] if aux is None else aux
 values=[(-1 if i%2 else 1)*(i%7) for i in range(length)] if values is None else values
 scalar=0;count=0;result=[];fault=0
 extent=len(aux) if op==11 else k if op in (5,9) else len(support) if op==7 else 0 if op==10 else length
 if op in (11,12):
  k=0
  if flags or support:fault=1
  if index>length or index+len(aux)>length:fault=4
  result=values[index:index+len(aux)] if op==11 else values[:index]+aux+values[index+len(aux):]
  count=len(aux) if op==11 else length
 elif op==5:
  excluded=set(support) if flags&1 else set()
  result=sorted((i for i in range(length) if i not in excluded),key=lambda i:(-abs(values[i]),i))[:k]
  if flags&2:result.sort()
  count=len(result)
 elif op==9:
  result=list(dict.fromkeys(support+aux))
  if not flags&1:result.sort()
  count=len(result)
  if count>k:fault=4
 elif op==10:scalar=values[index]
 else:
  count=len(support)
  if len(set(support))!=len(support):fault=1
  if any(i<0 or i>=length for i in support):fault=1
  if not fault:
   if op==6:result=[v if i in support else 0 for i,v in enumerate(values)]
   elif op==7:result=[values[i] for i in support]
   else:
    result=[0]*length
    for i,v in zip(support,values):result[i]=v
 writes=[];reads=[]
 def put(base,data):
  for block in range((len(data)+31)//32):
   part=data[block*32:block*32+32];writes.append(f"{base+block} {(1<<len(part))-1:x} {pack(part):x}")
 put(0,values[:-1] if source_missing else values);put(96,support);put(224,aux)
 if source_missing:fault=7
 # A nonempty declared destination is prepublished to prove fault/cancel invalidation.
 if destination not in (0,96,224):put(destination,[17]*max(1,extent))
 if op==10:
  reads.append(f"{destination} 1 0 {17:x}")
 elif fault or cancel:
  for block in range((extent+31)//32):
   mask=(1<<min(32,extent-block*32))-1;reads.append(f"{destination+block} {mask:x} 2 0")
 elif result:
  for block in range((len(result)+31)//32):
   part=result[block*32:block*32+32];reads.append(f"{destination+block} {(1<<len(part))-1:x} 0 {pack(part):x}")
  for block in range((len(result)+31)//32,(extent+31)//32):reads.append(f"{destination+block} 1 2 0")
 elif extent:
  for block in range((extent+31)//32):reads.append(f"{destination+block} 1 2 0")
 else:reads.append(f"{destination} 1 0 {17:x}")
 nz=int(any(result)) if op!=10 else int(scalar!=0)
 header=f"{op} 1 1 1 0 0 {length} 0 0 0 0 0 0 5 1 ffffffff {fault} {scalar&((1<<64)-1):x} {nz} {cancel} {len(writes)} {len(reads)} 0 3 {destination} 0 {k} {0 if op>=11 else 96} 224 {len(support)} {len(aux)} {index} {flags:x} {count}"
 return "\n".join([header,*writes,*reads])

def scalar_insert_fixture(length,index,scalar,destination=128,values=None,cancel=0,source_hole=False):
 values=[(i*37)%211-105 for i in range(length)] if values is None else values
 base=support_fixture(12,length=length,aux=[scalar],index=index,destination=destination,cancel=cancel,values=values)
 lines=base.splitlines(); header=lines[0].split(); blocks=(length+31)//32
 # REPLACE_RANGE writes source, one auxiliary word, then any prepublished output.
 del lines[1+blocks]
 header[0]='21';header[3]='0';header[9]=f'{scalar&((1<<27)-1):x}';header[10]='0';header[11]='0';header[12]='0';header[13]='0'
 header[20]=str(int(header[20])-1);header[25]='0';header[26]='0';header[27]='0';header[28]='0';header[29]='0';header[30]='0';header[32]='0';header[33]=str(length)
 if source_hole:
  source=lines[1+index//32].split();source[1]=f'{int(source[1],16)&~(1<<(index%32)):x}';lines[1+index//32]=' '.join(source)
 lines[0]=' '.join(header)
 return '\n'.join(lines)
def range_template_fixture(length,offset,scalar=1<<21,destination=128,source=None,cancel=0,source_hole=False):
 """Opcode22 with a vector A view and scalar-bound B; result is MUL(A[offset:], scalar)."""
 source=[i*73-901 for i in range(offset+length)] if source is None else source
 assert len(source)>=offset+length
 result=[rounded(v*scalar,22) for v in source[offset:offset+length]]
 frames=(length+31)//32; tail=(1<<(length%32))-1 if length%32 else MASK
 writes=[]; reads=[]
 for block in range((len(source)+31)//32):
  part=source[block*32:block*32+32]; mask=(1<<len(part))-1
  if source_hole and block==offset//32: mask &= ~(1<<(offset%32))
  writes.append(f"{block} {mask:x} {pack(part):x}")
 # Prepublish destination to make any reader fault demonstrate invalidation.
 for block in range(frames):
  part=[17]*min(32,length-block*32)
  # An aliased destination is already valid source data; do not overwrite it
  # while preparing the command fixture.
  if destination+block >= (len(source)+31)//32:
   writes.append(f"{destination+block} {(1<<len(part))-1:x} {pack(part):x}")
 fault=5 if source_hole else 0
 for block in range(frames):
  part=result[block*32:block*32+32];mask=(1<<len(part))-1
  reads.append(f"{destination+block} {mask:x} {2 if fault or cancel else 0} {0 if fault or cancel else pack(part):x}")
 contexts=pack([296]*32,64)
 header=f"22 1 1 0 0 0 {length} 0 0 {scalar&((1<<27)-1):x} {scalar&((1<<27)-1):x} 0 {MASK:x} 7 {frames} {tail:x} {fault} 0 {int(any(result)) if not fault else 0} {cancel} {len(writes)} {len(reads)} 0 3 {destination} {contexts:x} 0 0 0 0 0 {offset} 0 0"
 return "\n".join([header,*writes,*reads])

def rounded_affine_fixture(length, subtract=False, scalar_y=None, destination=128,
                            c_base=96, cancel=0, alias_y_x=False,
                            source_missing=False, values=None, c_values=None):
 """Opcode23: C +/- round_S27(X*Y), packed through Cascade16."""
 rng=random.Random(2300+length+destination+int(subtract))
 x=values if values is not None else [rng.randrange(-16000,16001) for _ in range(length)]
 y=[rng.randrange(-12000,12001) for _ in range(length)] if scalar_y is None else None
 c=c_values if c_values is not None else [rng.randrange(-18000,18001) for _ in range(length)]
 if c_base==0:
  c=x
 if alias_y_x:
  y=x
 if scalar_y is not None:
  product=[rounded(v*scalar_y,22) for v in x]
 else:
  product=[rounded(a*b,22) for a,b in zip(x,y)]
 result=[cv-p if subtract else cv+p for cv,p in zip(c,product)]
 product_overflow=any(not -(1<<26)<=v<(1<<26) for v in product)
 result_overflow=any(not -(1<<26)<=v<(1<<26) for v in result)
 # Cascade must flag multiplication before C can cancel an out-of-range product.
 fault=5 if source_missing else (3 if product_overflow or result_overflow else 0)
 frames=(length+31)//32; tail=(1<<(length%32))-1 if length%32 else MASK
 writes=[]
 def put(base,data,hole=False):
  for block in range((len(data)+31)//32):
   part=data[block*32:block*32+32]; mask=(1<<len(part))-1
   if hole and block+1==(len(data)+31)//32: mask &= ~1
   writes.append(f"{base+block} {mask:x} {pack(part):x}")
 put(0,x)
 if scalar_y is None and not alias_y_x: put(64,y)
 # C may deliberately equal destination, preserving its pre-command mapping.
 put(c_base,c,hole=source_missing)
 reads=[]
 for block in range(frames):
  part=result[block*32:block*32+32]; mask=(1<<len(part))-1
  reads.append(f"{destination+block} {mask:x} {2 if fault or cancel else 0} {0 if fault or cancel else pack(part):x}")
 contexts=pack([296]*16+([291] if subtract else [290])*16,64)
 bind_b=0xffff if scalar_y is not None else 0
 scalar=0 if scalar_y is None else scalar_y
 # Marker7 requests a test-only Y=X mapping; it is canonicalized before DUT.
 marker=7 if alias_y_x else cancel
 header=f"23 1 1 0 0 0 {length} 0 0 0 {scalar&((1<<27)-1):x} 0 {bind_b:x} 7 {frames} {tail:x} {fault} 0 {int(any(result)) if not fault else 0} {marker} {len(writes)} {len(reads)} 0 3 {destination} {contexts:x} 0 0 {c_base} 0 0 0 0 0"
 return "\n".join([header,*writes,*reads])
def preserve_case(case, cancel=6):
 lines=case.splitlines(); header=lines[0].split(); header[19]=str(cancel); lines[0]=" ".join(header)
 return "\n".join(lines)
def append_read(case, block, mask, expected_fault, expected_data):
 lines=case.splitlines(); header=lines[0].split(); header[21]=str(int(header[21])+1); lines[0]=" ".join(header)
 lines.append(f"{block} {mask:x} {expected_fault} {expected_data:x}")
 return "\n".join(lines)
def nonincrementing_case(values, destination):
 # A non-incrementing two-frame destination keeps the legacy copy path.
 case=fixture(op=0,length=len(values),destination=destination,values=values)
 lines=case.splitlines(); header=lines[0].split(); header[13]="1"; header[21]="1"; lines[0]=" ".join(header)
 result=[rounded(v*(1<<21),22) for v in values]
 return "\n".join(lines[:-2]+[f"{destination} 1 0 {pack(result[32:]):x}"])
def factor_sequence(rows,cols):
 rng=random.Random(912+rows*cols+cols)
 # fixture consumes A and B vector draws before its independent dense matrix.
 for _ in range(2*cols):rng.randrange(-1000,1001)
 matrix=[[rng.randrange(-131072,131072)<<6 for _ in range(cols)] for _ in range(rows)]
 initial=fixture(op=1,rows=rows,cols=cols,length=cols).splitlines()
 h=initial[0].split();h[0]='13';h[6]=str(rows);h[17]='0';h[18]=str(int(any(v for row in matrix for v in row)));h[21]='1';h[33]=str(cols)
 fills=initial[1:1+int(h[22])];writes=initial[1+int(h[22]):1+int(h[22])+int(h[20])]
 cases=['\n'.join([' '.join(h),*fills,*writes,'128 1 0 11'])]
 def command(op,row,fixed,start,length,values=None,cancel=0,fault=0):
  result=[matrix[fixed][start+i] if row else matrix[start+i][fixed] for i in range(length)]
  if op==15 and not fault and not cancel:
   for i,v in enumerate(values):
    if row:matrix[fixed][start+i]=v
    else:matrix[start+i][fixed]=v
  writes=[];reads=[]
  if op==15:
   for b in range((length+31)//32):
    data=values[b*32:b*32+32];writes.append(f'{b} {(1<<len(data))-1:x} {pack(data):x}')
   writes.append('128 1 11')
   reads=['128 1 0 11']
  else:
   for b in range((length+31)//32):
    data=result[b*32:b*32+32];mask=(1<<len(data))-1
    writes.append(f'{128+b} {mask:x} {pack([17]*len(data)):x}')
    reads.append(f'{128+b} {mask:x} {2 if fault or cancel else 0} {0 if fault or cancel else pack(data):x}')
  header=f'{op} {rows} {cols} 1 0 0 {length} 0 0 0 0 0 0 5 1 ffffffff {fault} 0 {int(any(result if op==14 else values)) if not fault else 0} {cancel} {len(writes)} {len(reads)} 0 3 128 0 0 0 0 0 {start} {fixed} {int(row)} {length}'
  cases.append('\n'.join([header,*writes,*reads]))
 command(14,False,0,0,rows)
 command(14,True,rows-1,0,cols)
 length=rows-1 if rows>1 else 1;start=int(rows>1)
 replacement=[(i-63)*199 for i in range(length)]
 command(15,False,cols-1,start,length,replacement)
 command(14,False,cols-1,0,rows)
 command(14,True,rows-1,0,cols)
 return cases

def project_contexts():
 return pack([297,296,291]+[0]*29,64)

def _project_header(op,rows,cols,length,scalar=0,bind_a=0,bind_b=0,descriptor=5,
                    contexts=0,fault=0,nonzero=0,cancel=0,writes=(),reads=(),fills=(),
                    destination=0,support_base=0,aux_base=0,support_length=0,aux_length=0,
                    index=0,flags=0,expected_count=0,expected_scalar=None,frame_count=None,tail_mask=None,scalar_b=None):
 frames=(length+31)//32 if frame_count is None else frame_count
 tail=(1<<(length%32))-1 if length%32 else MASK
 if tail_mask is not None: tail=tail_mask
 if expected_scalar is None: expected_scalar=0
 if scalar_b is None: scalar_b=scalar
 fields=[op,rows,cols,1,0,0,length,0,0,scalar&((1<<27)-1),scalar_b&((1<<27)-1),
         bind_a,bind_b,descriptor,frames,tail,fault,expected_scalar&((1<<64)-1),nonzero,cancel,len(writes),len(reads),
         len(fills),3,destination,contexts,0,support_base,aux_base,support_length,
         aux_length,index,flags,expected_count]
 return '\n'.join([' '.join(f'{x:x}' if n in (9,10,11,12,13,15,17,25,32) else str(x) for n,x in enumerate(fields)),
                   *fills,*writes,*reads])

def _vector_writes(base,values):
 return [f'{base+block} {(1<<len(values[block*32:block*32+32]))-1:x} {pack(values[block*32:block*32+32]):x}'
         for block in range((len(values)+31)//32)]

def _vector_reads(base,values):
 return [f'{base+block} {(1<<len(values[block*32:block*32+32]))-1:x} 0 {pack(values[block*32:block*32+32]):x}'
         for block in range((len(values)+31)//32)]

def factor_range_template_sequence(rows,cols,axis,fixed,offset,length,head_only=False,patch=None,destination=192,
                                   source_hole=None,marker=6,expected_fault=0):
 """Initialize a C18 factor image, then op24 against a public S27 range."""
 assert 1<=rows<=128 and 1<=cols<=96 and 1<=length<=128
 assert (axis and 0<=fixed<rows and 0<=offset and offset+length<=cols) or (
     not axis and 0<=fixed<cols and 0<=offset and offset+length<=rows)
 raw=[[((31*r+17*c+5)%131)-65 for c in range(cols)] for r in range(rows)]
 factor=[[v<<6 for v in line] for line in raw]
 source=[((29*i+11)%257)-128 for i in range(max(rows,cols))]
 fills=[]
 for c in range(cols):
  for block in range((rows+31)//32):
   data=[raw[r][c] for r in range(block*32,min(rows,block*32+32))]
   fills.append(f"{c} {block} {(1<<len(data))-1:x} {pack(data,18):x}")
 source_writes=_vector_writes(0,source)
 if source_hole is not None:
  block=source_hole>>5
  words=source_writes[block].split()
  words[1]=f"{int(words[1],16)&~(1<<(source_hole&31)):x}"
  source_writes[block]=' '.join(words)
 init=_project_header(13,rows,cols,rows,nonzero=1,writes=source_writes,fills=fills,expected_count=cols)
 values=[factor[fixed][offset+i] for i in range(length)] if axis else [factor[offset+i][fixed] for i in range(length)]
 if patch is not None: values[0]=patch
 raw_acc=sum(values[i]*source[offset+i] for i in range(length))
 tap=values[:1] if head_only else values
 flags=(1 if axis else 0)|(2 if head_only else 0)|(4 if patch is not None else 0)
 op=_project_header(24,rows,cols,length,scalar=0 if patch is None else patch,scalar_b=0,descriptor=23,contexts=pack([297]*32,64),
                    fault=expected_fault,nonzero=0 if expected_fault else int(any(tap)),cancel=marker,
                    reads=() if expected_fault or marker==22 else _vector_reads(destination,tap),destination=destination,
                    support_length=cols,aux_length=offset,index=fixed,flags=flags,
                    expected_count=0 if expected_fault else len(tap),
                    expected_scalar=0 if expected_fault else raw_acc,frame_count=0,tail_mask=0)
 return [init,op],dict(raw=raw,factor=factor,source=source,tap=tap,raw_acc=raw_acc,flags=flags)

def factor_energy_tap_sequence(rows,cols,axis,fixed,offset,length,destination=192,
                               marker=6,expected_fault=0,raw_value=None):
 """Initialize a C18 factor image, then square one private factor range.

 The independent integer oracle deliberately has no public input vector: op25
 must request only the retained factor words.  Its response count is the tail
 (logical lanes 1..L-1) nonzero boolean, while the packed candidate and response
 nonzero cover the complete unpatched tap.
 """
 assert 1<=rows<=128 and 1<=cols<=96 and 1<=length<=128
 assert (axis and 0<=fixed<rows and 0<=offset and offset+length<=cols) or (
     not axis and 0<=fixed<cols and 0<=offset and offset+length<=rows)
 value=(lambda row,col: ((31*row+17*col+5)%131)-65) if raw_value is None else (
     raw_value if callable(raw_value) else lambda row,col: raw_value)
 raw=[[value(row,col) for col in range(cols)] for row in range(rows)]
 factor=[[value<<6 for value in line] for line in raw]
 fills=[]
 for col in range(cols):
  for block in range((rows+31)//32):
   data=[raw[row][col] for row in range(block*32,min(rows,block*32+32))]
   fills.append(f"{col} {block} {(1<<len(data))-1:x} {pack(data,18):x}")
 init=_project_header(13,rows,cols,rows,nonzero=int(any(value for line in raw for value in line)),fills=fills,expected_count=cols)
 tap=[factor[fixed][offset+i] for i in range(length)] if axis else [factor[offset+i][fixed] for i in range(length)]
 raw_acc=sum(value*value for value in tap)
 flags=1 if axis else 0
 op=_project_header(25,rows,cols,length,scalar=0,scalar_b=0,descriptor=23,
                    contexts=pack([297]*32,64),fault=expected_fault,
                    nonzero=0 if expected_fault else int(any(tap)),cancel=marker,
                    reads=() if expected_fault or marker in (22,25) else _vector_reads(destination,tap),
                    destination=destination,support_length=cols,aux_length=offset,
                    index=fixed,flags=flags,
                    expected_count=0 if expected_fault else int(any(tap[1:])),
                    expected_scalar=0 if expected_fault else raw_acc,
                    frame_count=0,tail_mask=0)
 return [init,op],dict(raw=raw,factor=factor,tap=tap,raw_acc=raw_acc,
                        tail_nonzero=int(any(tap[1:])),flags=flags)

def factor_range_readback(rows,cols,axis,fixed,factor,destination):
 """Read the private factor axis after op24 to prove its patch stayed private."""
 values=[factor[fixed][i] for i in range(cols)] if axis else [factor[i][fixed] for i in range(rows)]
 return _project_header(14,rows,cols,len(values),nonzero=int(any(values)),cancel=6,
                        writes=_vector_writes(destination,[17]*len(values)),reads=_vector_reads(destination,values),
                        destination=destination,index=fixed,flags=int(axis),expected_count=len(values))
def factor_project_update_sequence(rows=33,cols=17):
 """Exact unfused 17/scale/18 versus compact op20, including V at base zero."""
 # C18 B is imported by FACTOR_INIT as S27F22 through its existing << 6 path.
 raw=[[((19*r+11*c+7)%97-48)*137 for c in range(cols)] for r in range(rows)]
 factor=[[x<<6 for x in row] for row in raw]
 v=[(r-16)*1049+(7 if r%3==0 else -11) for r in range(rows)]
 alpha=(1<<21)+19 # +0.5 plus a noninteger S27F22 fraction
 q=[rounded(sum(factor[r][c]*v[r] for r in range(rows)),22) for c in range(cols)]
 scaled=[rounded(alpha*x,22) for x in q]
 updated=[[factor[r][c]-rounded(v[r]*scaled[c],22) for c in range(cols)] for r in range(rows)]
 if not all(-(1<<26)<=x<(1<<26) for row in updated for x in row):raise AssertionError('fixture range')
 fills=[]
 for c in range(cols):
  for block in range((rows+31)//32):
   data=[raw[r][c] for r in range(block*32,min(rows,block*32+32))]
   fills.append(f'{c} {block} {(1<<len(data))-1:x} {pack(data,18):x}')
 def init_case():
  return _project_header(13,rows,cols,rows,nonzero=1,writes=_vector_writes(0,v),fills=fills,expected_count=cols)
 def read_case(column,expect):
  return _project_header(14,rows,cols,rows,nonzero=int(any(expect)),writes=_vector_writes(192,[17]*rows),
                         reads=_vector_reads(192,expect),destination=192,index=column,expected_count=rows)
 direct_matvec=_project_header(17,rows,cols,rows,descriptor=23,contexts=pack([297]*32,64),nonzero=int(any(q)),
                               cancel=6,writes=(),reads=_vector_reads(64,q),destination=64,support_length=cols,expected_count=cols)
 # Marker 7 is testbench-only: it preserves factor state and maps support/aux
 # header fields to source A/B before presenting canonical zero metadata.
 direct_scale=_project_header(0,rows,cols,cols,scalar=alpha,bind_b=MASK,descriptor=5,contexts=pack([296]*32,64),
                              nonzero=int(any(scaled)),cancel=7,reads=_vector_reads(128,scaled),destination=128,
                              support_base=64,aux_base=0)
 direct_rank=_project_header(18,rows,cols,rows,descriptor=7,contexts=pack([296]*16+[291]*16,64),cancel=7,
                             support_base=0,aux_base=128,support_length=cols,expected_count=0)
 compact=_project_header(20,rows,cols,rows,scalar=alpha,descriptor=31,contexts=project_contexts(),cancel=6,
                         support_length=cols,expected_count=0)
 # First/middle/last columns exercise direct and compact factor readback with
 # distinct block tails. Both use the independently rounded three-stage oracle.
 picked=sorted({0,cols//2,cols-1})
 return [init_case(),direct_matvec,direct_scale,direct_rank,*[read_case(c,[updated[r][c] for r in range(rows)]) for c in picked],
         init_case(),compact,*[read_case(c,[updated[r][c] for r in range(rows)]) for c in picked]],dict(raw=raw,v=v,q=q,scaled=scaled,updated=updated,alpha=alpha)

class StreamKernelRtlTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.folder=Path(tempfile.mkdtemp(prefix="stream_kernel_",dir=ROOT/"work"))
  cls.binary=cls.folder/"kernel.xsim.json"
  cls.before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES+SOURCE_EXTRAS}
  cls.compiled=compile_rtl(cls.binary,"tb_stream_kernel",SOURCES,root=ROOT,timeout=240)
  if cls.compiled.returncode:raise AssertionError(cls.compiled.stdout+cls.compiled.stderr)
 def replay(self,fixtures):
  file=self.folder/(self._testMethodName+".txt")
  file.write_text(str(len(fixtures))+"\n"+"\n".join(fixtures)+"\n")
  result=run_rtl(self.binary,["vectors="+file.as_posix()]+(["request_stalls=1","require_overlap=1"] if "pipeline_tails" in self._testMethodName else []),root=ROOT,timeout=600)
  self.assertEqual(result.returncode,0,result.stdout+result.stderr)
  match=re.search(r"PASS stream_kernel cycles=(\d+) checks=(\d+) commands=(\d+) stalls=(\d+)",result.stdout)
  self.assertIsNotNone(match,result.stdout)
  cycles,checks,count,stalls=map(int,match.groups());self.assertEqual(count,len(fixtures));self.assertGreater(stalls,0)
  record=dict(test=self.id(),status="PASS",cycles=cycles,comparisons=checks,commands_executed=count,stalls=stalls,
   comparison_kind="exact_S27_outputs_live_matrix_integer_oracle_and_transaction_protocol",
   commands=self.compiled.commands+result.commands,stdout=result.stdout,vectors_sha256=hashlib.sha256(file.read_bytes()).hexdigest())
  self.assertEqual(self.before,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES+SOURCE_EXTRAS})
  record["source_sha256"]=self.before
  RUNS.append(record);(self.folder/(self._testMethodName+".json")).write_text(json.dumps(record,indent=2)+"\n")
 def test_vector_bind_normalize_store_soft_and_alias(self):
  cases=[fixture(op=op,length=n,destination=0 if n==33 else 128,scalar=37 if op==4 else 1<<21) for op in (0,2,3,4) for n in (1,33,1024)]
  cases += [fixture(op=2,length=33,shift=sh,scalar=3,values=list(range(-16,17))) for sh in (0,1,2,6,27)]
  cases += [fixture(op=3,length=4,store=1,values=[-33554432,33554428,-3,3]),fixture(op=3,length=4,store=2,values=[-33554432,33554176,-128,128]),fixture(op=3,length=1,store=1,values=[67108863]),fixture(op=2,length=1,shift=0,scalar=67108863,values=[2])]
  self.replay(cases)
 def test_factor_init_write_read_real_B_and_private_lifetime(self):
  self.replay([case for m,n in [(1,1),(33,17),(128,96)] for case in factor_sequence(m,n)])
 def test_factor_candidate_fault_cancel_and_staged_write_fault(self):
  sequences=[]
  for mode in (1,2,4):
   seq=factor_sequence(128,96);bad=seq[1].splitlines();h=bad[0].split();h[19]=str(mode);h[16]='6' if mode==4 else '0'
   bad[0]=' '.join(h)
   for i in range(-int(h[21]),0):
    fields=bad[i].split();fields[2]='2';fields[3]='0';bad[i]=' '.join(fields)
   sequences.extend([seq[0],'\n'.join(bad)])
  seq=factor_sequence(128,96);bad=seq[3].splitlines();h=bad[0].split();h[16]='7';h[18]='0';h[20]=str(int(h[20])-1)
  bad[0]=' '.join(h);bad=[line for i,line in enumerate(bad) if i==0 or not line.startswith('3 ')]
  sequences.extend([seq[0],'\n'.join(bad)])
  self.replay(sequences)
 def test_factor_project_update_fractional_base0_chain_readback_and_fault_cancel(self):
  cases,oracle=factor_project_update_sequence()
  # The fixture reaches each required round boundary: accumulated dot, alpha
  # scale, and rank-one product. A fused update would not reproduce all three.
  self.assertTrue(any(x != rounded(oracle['alpha']*sum(oracle['raw'][r][c]*64*oracle['v'][r] for r in range(33)),44)
                      for c,x in enumerate(oracle['scaled'])))
  self.assertTrue(any(oracle['updated'][r][c] != (oracle['raw'][r][c]<<6)
                      for r in range(33) for c in range(17)))
  # Bad compact metadata is rejected after a valid private image; a preserved
  # command with marker 10 then drives the real panel/fabric cancellation path.
  invalid=cases[8].splitlines();fields=invalid[0].split();fields[25]='0';fields[16]='1';invalid[0]=' '.join(fields)
  cancelled=cases[8].splitlines();fields=cancelled[0].split();fields[19]='10';cancelled[0]=' '.join(fields)
  self.replay(cases+[cases[0],'\n'.join(invalid),cases[0],'\n'.join(cancelled)])
 def test_live_matrices_all_layouts_and_tails(self):
  self.replay([fixture(op=1,rows=m,cols=n,dense=d,trans=t,r4=r,length=m if t else n) for m,n in ((1,1),(7,3),(33,17)) for d in (0,1) for t in (0,1) for r in (0,1)])
 def test_maximum_live_matrices(self):
  self.replay([fixture(op=1,rows=128,cols=96 if d else 1024,dense=d,trans=t,r4=r,length=128 if t else 96 if d else 1024) for d in (0,1) for t in (0,1) for r in (0,1)])
 def test_range_transport_unaligned_alias_and_tails(self):
  cases=[]
  for n,start,size in [(1,0,1),(33,1,32),(65,31,33),(97,32,65),(1024,1,1023),(1024,1024,0)]:
   for op in (11,12):
    cases.append(support_fixture(op,length=n,index=start,aux=[i-29 for i in range(size)],values=[i-511 for i in range(n)],destination=0 if start%2 else 128))
  cases.append(support_fixture(12,length=65,index=17,aux=[-9]*33,destination=224))
  self.replay(cases)
 def test_range_transport_faults_cancel_and_empty(self):
  self.replay([support_fixture(11,length=33,index=0,aux=[1],flags=1),support_fixture(12,length=33,index=0,aux=[1],support=[0]),support_fixture(11,length=33,index=34,aux=[]),support_fixture(12,length=33,index=32,aux=[1,2]),
   support_fixture(11,length=65,index=0,aux=[0]*65,source_missing=True),
   support_fixture(12,length=65,index=0,aux=[],source_missing=True),
   support_fixture(11,length=33,index=33,aux=[]),support_fixture(12,length=65,index=1,aux=[0]*33,cancel=1),
   support_fixture(12,length=65,index=31,aux=[0]*33,cancel=2)])
 def test_support_rank_masks_and_union(self):
  self.replay([support_fixture(5),support_fixture(5,flags=1,support=[6,13,20]),support_fixture(5,flags=2),support_fixture(5,length=8,k=8,flags=1,support=list(range(8))),support_fixture(9,length=64,k=8,support=[8,2,6],aux=[6,3,2]),support_fixture(9,length=64,k=8,flags=1,support=[8,2,6],aux=[6,3,2]),support_fixture(9,length=64,k=2,support=[8,2,6],aux=[6,3,2])])
 def test_support_gather_scatter_alias_and_pick(self):
  cases=[support_fixture(op,length=65,support=[64,2,33,0],values=list(range(-32,33)),destination=0 if op in (6,7) else 128) for op in (6,7)]
  cases += [support_fixture(8,length=65,support=[64,2,33,0],values=[-7,13,9,11]),support_fixture(10,length=33,index=7),support_fixture(7,length=33,support=[]),support_fixture(6,length=33,support=[]),support_fixture(8,length=33,support=[],values=[])]
  self.replay(cases)
 def test_support_faults_cancel_and_maximum(self):
  self.replay([support_fixture(6,length=65,support=[0,32,64],source_missing=True),support_fixture(10,length=33,index=1),support_fixture(5,length=1,k=1,values=[-(1<<26)]),support_fixture(7,support=[1,1]),support_fixture(8,support=[1,1],values=[7,9]),support_fixture(5,length=1024,k=96),support_fixture(5,length=65,k=16,cancel=1),support_fixture(8,length=65,support=[64,2,33,0],values=[-7,13,9,11],cancel=2)])
 def test_external_command_validation_and_reset(self):
  inert=fixture().splitlines();header=inert[0].split();header[0]="16";header[16]="1";inert[0]=" ".join(header)
  for i in range(-int(header[21]),0):
   fields=inert[i].split();fields[2]="0";fields[3]=format(pack([17]*int(fields[1],16).bit_count()),"x");inert[i]=" ".join(fields)
  self.replay(["\n".join(inert),fixture(source_missing=True),fixture(context=297),fixture(op=1,rows=33,cols=17,length=17,destination=0),fixture(op=1,rows=33,cols=17,length=33,trans=1,r4=1,destination=0),fixture(op=0,length=33,cancel=3)])
 def test_pipeline_tails_cache_epoch_and_pending_fault(self):
  cases=[fixture(op=1,rows=35,cols=n,dense=d,trans=0,r4=1,length=n) for n in (1,7,8,9,25,31,33,65) for d in (0,1)]
  for values in ([1]*65,[-17]*65):
   lines=fixture(op=1,rows=33,cols=65,dense=0,length=65,values=values).splitlines()
   h=lines[0].split();h[19]='6';lines[0]=' '.join(h);cases.append('\n'.join(lines))
  for d in (0,1):
   lines=fixture(op=1,rows=33,cols=17,dense=d,length=17).splitlines();h=lines[0].split();h[19]='5';h[16]='7';lines[0]=' '.join(h)
   for i in range(-int(h[21]),0):
    f=lines[i].split();f[2]='2';f[3]='0';lines[i]=' '.join(f)
   cases.append('\n'.join(lines))
   lines=fixture(op=1,rows=33,cols=17,dense=d,length=17).splitlines();h=lines[0].split();h[19]='6';lines[0]=' '.join(h);cases.append('\n'.join(lines))
  self.replay(cases)
 def test_range_template_unaligned_scalar_bound_alias_and_faults(self):
  values=[i*41-1007 for i in range(1024)]
  cases=[range_template_fixture(n,start,destination=128+((n+start)%5)*32,source=values)
         for n,start in ((1,0),(31,1),(32,31),(33,31),(64,32),(96,33),(128,95),(1024,0))]
  cases += [range_template_fixture(33,32,destination=0,source=values),
            range_template_fixture(33,31,destination=320,source=values,source_hole=True),
            range_template_fixture(65,31,destination=352,source=values,cancel=1)]
  self.replay(cases)
 def test_scalar_insert_virtual_provider_alias_tails_and_cancel(self):
  values=[(i*71)%503-251 for i in range(96)]
  # The virtual provider must bypass RAM when an entire output block is the
  # replacement lane.  Invalidating that lane proves no source request is made;
  # preceding blocks still compare through the ordinary host readback oracle.
  self.replay([
   scalar_insert_fixture(1,0,0,destination=96,source_hole=True),
   scalar_insert_fixture(1,0,-17,destination=128,source_hole=True),
   scalar_insert_fixture(33,0,-17,destination=160),
   scalar_insert_fixture(33,32,-19,destination=192,source_hole=True),
   scalar_insert_fixture(65,64,0,destination=256,source_hole=True),
   scalar_insert_fixture(96,95,31<<21,destination=0,values=values,source_hole=True),
   scalar_insert_fixture(65,32,0,destination=320,cancel=1),
  ])
 def test_rounded_affine_cascade_add_sub_scalar_tails_alias_and_preflight(self):
  cases=[]
  for length in (1,17,32,33,1024):
   cases.append(rounded_affine_fixture(length,destination=128+(length%5)*32))
   cases.append(rounded_affine_fixture(length,subtract=True,destination=256+(length%3)*32))
  # Scalar B exercises the lower-half binding, signed tie direction, and tail17.
  cases += [
   rounded_affine_fixture(17,scalar_y=(1<<21),destination=352,
                           values=[1 if i%2==0 else -3 for i in range(17)]),
   rounded_affine_fixture(33,scalar_y=-(1<<21),destination=384),
   rounded_affine_fixture(65,destination=0,c_base=0),
   rounded_affine_fixture(33,destination=416,alias_y_x=True),
   rounded_affine_fixture(33,destination=448,c_base=96,source_missing=True),
   # The multiply fault wins even though C would bring the final sum into range.
   rounded_affine_fixture(1,scalar_y=(1<<22)+1,destination=352,
                           values=[(1<<26)-1],c_values=[-16]),
   # High cascade ADD and SUB overflow independently of the low multiply.
   rounded_affine_fixture(1,scalar_y=(1<<22),destination=384,
                           values=[1],c_values=[(1<<26)-1]),
   rounded_affine_fixture(1,subtract=True,scalar_y=(1<<22),destination=416,
                           values=[1],c_values=[-(1<<26)]),
  ]
  self.replay(cases)
 def test_factor_range_template_axes_offsets_patches_and_raw_acc(self):
  cases=[]
  # Column/full/patch with fixed index distinct from offset rotates factor banks.
  for args in [
   (65,17,False,7,5,33,False,1<<22,192),
   (65,65,True,11,7,31,True,None,224),
   (128,96,False,65,0,128,False,-(1<<22),256),
   (2,1,True,1,0,1,True,None,288),
   # Lane one is nonzero in the fixture; PATCH_FIRST still replaces it with zero.
   (2,1,False,0,1,1,False,0,304),
  ]:
   seq,_=factor_range_template_sequence(*args); cases.extend(seq)
  self.replay(cases)
 def test_factor_range_template_boundaries_alias_and_private_readback(self):
  cases=[]
  # Boundary lengths 2/32/96 cover exact and unaligned tail masks.  The final
  # full tap aliases source and destination, then reads the untouched factor.
  for args,read_destination in [
   ((65,17,False,3,31,2,False,None,320),448),
   ((96,64,True,5,0,32,False,3,352),416),
   ((128,96,False,5,31,96,False,-(1<<26),0),384),
  ]:
   seq,oracle=factor_range_template_sequence(*args)
   cases.extend(seq)
   rows,cols,axis,fixed,*_=args
   cases.append(factor_range_readback(rows,cols,axis,fixed,oracle['factor'],read_destination))
  self.replay(cases)
 def test_factor_range_template_preflight_and_factor_mask_faults(self):
  cases=[]
  # Selected source lane 32 is absent in an offset31/L33 two-block view.
  seq,_=factor_range_template_sequence(65,17,False,3,31,33,False,None,384,
                                       source_hole=32,expected_fault=7)
  cases.extend(seq)
  # A bad panel response mask is identity-fatal before head candidate/raw data.
  seq,_=factor_range_template_sequence(65,17,False,3,0,33,True,1<<22,416,
                                       marker=21,expected_fault=6)
  cases.extend(seq)
  self.replay(cases)
 def test_resident_remap_alias_mixed_extents_and_cancel(self):
  full=[(i%97)-48 for i in range(1024)]
  alias=[(i*29)%211-105 for i in range(65)]
  mixed=[(i*17)%127-63 for i in range(33)]
  first=fixture(op=0,length=1024,destination=128,values=full)
  second=preserve_case(fixture(op=0,length=65,destination=0,values=alias))
  third=preserve_case(fixture(op=0,length=33,destination=256,values=mixed))
  cancelled=preserve_case(fixture(op=0,length=65,destination=320,values=[i-17 for i in range(65)],cancel=1),cancel=16)
  first_result=[rounded(v*(1<<21),22) for v in full]
  cancelled=append_read(cancelled,128,(1<<32)-1,0,pack(first_result[:32]))
  tail=preserve_case(fixture(op=0,length=1,destination=352,values=[-73]))
  fallback=preserve_case(nonincrementing_case([i-19 for i in range(33)],400))
  self.replay([first,second,third,cancelled,tail,fallback])
 def test_legacy_copy_parameter_tail_and_alias(self):
  binary=self.folder/"kernel_copy.xsim.json"
  sources=SOURCES+["verification/v4/stream/tb_stream_kernel_copy.sv"]
  compiled=compile_rtl(binary,"tb_stream_kernel_copy",sources,root=ROOT,timeout=240)
  self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
  cases=[fixture(op=0,length=33,destination=128,values=[i-16 for i in range(33)]),
         fixture(op=0,length=65,destination=0,values=[i-32 for i in range(65)])]
  file=self.folder/(self._testMethodName+".txt")
  file.write_text(str(len(cases))+"\n"+"\n".join(cases)+"\n")
  result=run_rtl(binary,["vectors="+file.as_posix()],root=ROOT,timeout=600)
  self.assertEqual(result.returncode,0,result.stdout+result.stderr)
  match=re.search(r"PASS stream_kernel cycles=(\d+) checks=(\d+) commands=(\d+) stalls=(\d+)",result.stdout)
  self.assertIsNotNone(match,result.stdout)
  cycles,checks,count,stalls=map(int,match.groups());self.assertEqual(count,len(cases));self.assertGreater(stalls,0)
  self.assertEqual(self.before,{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES+SOURCE_EXTRAS})
  record=dict(test=self.id(),status="PASS",mode="legacy_copy_parameter_false",cycles=cycles,comparisons=checks,
   commands_executed=count,stalls=stalls,comparison_kind="exact_S27_legacy_copy_writeback",commands=compiled.commands+result.commands,
   stdout=result.stdout,vectors_sha256=hashlib.sha256(file.read_bytes()).hexdigest(),source_sha256=self.before)
  RUNS.append(record);(self.folder/(self._testMethodName+".json")).write_text(json.dumps(record,indent=2)+"\n")
 def test_matrix_fault_and_cancel_invalidate_destination(self):
  self.replay([fixture(op=1,rows=33,cols=17,length=17,generation=4),fixture(op=1,rows=33,cols=17,length=17,cancel=1),fixture(op=1,rows=33,cols=17,length=17,cancel=2),fixture(op=0,length=33,cancel=2)])
if __name__=="__main__":unittest.main()
