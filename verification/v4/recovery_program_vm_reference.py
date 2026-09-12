"""Instruction interpreter for compiler schedule tests, not an RTL cycle model."""
import math
import numpy as np
from compiler.v4.recovery_program import ABI, decode, unpack
from compiler.v4.stream_program import decode_context, decode_descriptor, validate_context, validate_descriptor
from models.v4.fixed import Arithmetic, Format
from compiler.v4.recovery_emit import PROFILE


def execute(package,matrix,measurement,limit=100000,*,debug_vectors=None):
    ar=Arithmetic(PROFILE);sf=PROFILE.state
    matrix=ar.quantize(matrix,PROFILE.coefficient)
    memory=[None]*15360;rf=[0]*32;stack=[];pc=0;trace=[]
    vectors=package['vectors'];m,n=matrix.shape;bmatrix=None;factors=None
    def read(v,size):
        if size>vectors[v]['capacity']:raise AssertionError('read exceeds descriptor capacity')
        base=vectors[v]['base']*32;values=memory[base:base+size]
        if any(x is None for x in values):raise AssertionError(f'uninitialized vector {v} read')
        return np.array(values,dtype=object)
    def write(v,values,clear_extent=None):
        if len(values)>vectors[v]['capacity']:raise AssertionError('write exceeds descriptor capacity')
        if clear_extent is None:clear_extent=len(values)
        if not 0<=clear_extent<=vectors[v]['capacity']:raise AssertionError('clear exceeds descriptor capacity')
        base=vectors[v]['base']*32
        published=((clear_extent+31)//32)*32
        memory[base:base+published]=[None]*published
        memory[base:base+len(values)]=[int(x) for x in values]
    def element(v,index):
        if not 0<=index<vectors[v]['capacity']:raise AssertionError('element outside descriptor')
        value=memory[vectors[v]['base']*32+index]
        if value is None:raise AssertionError(f'uninitialized vector {v} element {index}')
        return int(value)
    y=ar.rescale(ar.quantize(measurement,PROFILE.data),PROFILE.data.frac,sf)
    write(package['measurement_vector'],y)
    def kernel(f):
        nonlocal factors
        q=unpack(ABI['service_immediate_fields'],f['immediate']);op=f['kernel'];a=f['a_v'];b=f['b_v'];d=f['dst_v']
        length=[m,n,q['length'],rf[q['length']&31]][f['length_mode']]
        scalar_a,scalar_b=rf[f['a_s']],rf[f['b_s']]
        template=package['templates'][q['template']];out=None;value=0;count=0;clear_extent=None
        # Validate the loaded primitive contract even for specialized transport.
        # Otherwise an arithmetic-only VM could conceal unusable PE contexts.
        contexts=template['contexts']
        if op in (17,18,19,20):
            # Specialized factor operations are still guarded by canonical
            # loaded images. Opcode20 alone admits compact kind3 metadata.
            expected_descriptor={17:23,18:7,19:0,20:31}[op]
            common_bad=(template['descriptor']!=expected_descriptor or template['bind_a'] or template['bind_b'] or
                        q['transpose'] or q['r4'] or q['store_mode'] or q['flags'] or
                        q['k_s'] or q['support_v'] or q['aux_v'] or f['b_s'] or
                        f['shift_s'] or f['dst_s'] or f['flag_s'] or not q['dense'])
            if common_bad:
                raise AssertionError('factor panel unused payload or descriptor')
            if op==17:
                if f['a_s'] or any(c!=297 for c in contexts):
                    raise AssertionError('FACTOR_MATVEC requires 32 direct MAC contexts')
            elif op==18:
                if f['a_s'] or any(c!=296 for c in contexts[:16]) or any(c!=291 for c in contexts[16:]):
                    raise AssertionError('FACTOR_RANK1 requires direct MUL16/SUB16 contexts')
            elif op==19:
                if (length!=m or q['aux_length_s'] or f['a_v'] or f['b_v'] or f['dst_v'] or
                        f['a_s'] or any(contexts)):
                    raise AssertionError('FACTOR_EXTEND requires descriptor0, zero contexts and no pool operands')
            else:
                if (f['b_v'] or f['dst_v'] or
                        contexts[:3] != [297,296,291] or any(contexts[3:])):
                    raise AssertionError('FACTOR_PROJECT_UPDATE requires compact MAC/MUL/SUB phase image')
        if op==21:
            if (template['descriptor'] or template['bind_a'] or template['bind_b'] or any(contexts) or
                    f['b_v'] or f['b_s'] or f['dst_s'] or f['flag_s'] or f['target'] or f['shift_s'] or
                    q['dense'] or q['transpose'] or q['r4'] or q['store_mode'] or q['flags'] or q['k_s'] or
                    q['support_v'] or q['aux_v'] or q['support_length_s'] or q['aux_length_s']):
                raise AssertionError('SCALAR_INSERT requires canonical inert template and unused fields')
            if not -(1<<26)<=scalar_a<(1<<26):
                raise ArithmeticError('numeric_fault')
        if op==23:
            scalar_b_bound=template['bind_b']==0xffff
            if (template['descriptor']!=7 or template['bind_a']!=0 or
                    template['bind_b'] not in (0,0xffff) or
                    q['dense'] or q['transpose'] or q['r4'] or q['store_mode'] or q['flags'] or
                    q['k_s'] or q['support_v'] or q['support_length_s'] or q['index_s'] or
                    f['a_s'] or f['dst_s'] or f['flag_s'] or f['target'] or f['shift_s'] or
                    length<1 or rf[q['aux_length_s']]!=0 or
                    q['aux_v'] >= len(vectors)):
                raise AssertionError('ROUNDED_AFFINE canonical payload')
            if scalar_b_bound:
                if f['b_v']!=0 or not -(1<<26)<=scalar_b<(1<<26):
                    raise ArithmeticError('numeric_fault')
            elif f['b_s']:
                raise AssertionError('ROUNDED_AFFINE vector B has scalar payload')
            upper=contexts[16]
            if upper not in (290,291):
                raise AssertionError('ROUNDED_AFFINE upper operation')
            for lane,context in enumerate(contexts):
                if lane<16:
                    if context!=296:raise AssertionError('ROUNDED_AFFINE MUL context')
                elif context!=upper:raise AssertionError('ROUNDED_AFFINE mixed upper context')
        if op in (1,2):
            expected=265 if op==1 else 297
            if any(c&1023!=expected for c in contexts):raise AssertionError('GEMV/NORMALIZE requires its loaded MAC mode')
        if op==3 and any((c&31)!=1 or ((c>>6)&3)!=0 for c in contexts):raise AssertionError('STORE requires loaded MOV A')
        if op==4 and any((c&991)!=259 for c in contexts):raise AssertionError('SOFT requires loaded SUB A B')
        if op in (0,16):
            desc=template['descriptor'];raw=[]
            a_offset=b_offset=0
            if op==22:
                if (not 1<=length<=1024 or desc&7!=7 or f['target'] or
                        any(q[key] for key in ('dense','transpose','r4','store_mode','flags','support_v','aux_v')) or
                        any(rf[index] for index in (f['shift_s'],q['k_s'],q['support_length_s']))):
                    raise AssertionError('RANGE_TEMPLATE canonical payload or descriptor')
                a_offset,b_offset=rf[q['index_s']],rf[q['aux_length_s']]
                if not (0<=a_offset<=1023 and 0<=b_offset<=1023):
                    raise AssertionError('RANGE_TEMPLATE offset outside unsigned11 range')
                needs=[None,None]
                for i in range(length):
                    lane=i%32;ctx=contexts[lane];opcode=ctx&31
                    selectors=[ctx>>6&3]+([] if opcode==1 else [ctx>>8&3])
                    for selector in selectors:
                        if selector < 2 and not ((template['bind_a'] if selector==0 else template['bind_b'])>>lane&1):
                            needs[selector]=i if needs[selector] is None else max(needs[selector],i)
                for selector,(offset,need,vector) in enumerate(((a_offset,needs[0],a),(b_offset,needs[1],b))):
                    if need is None:
                        if offset:raise AssertionError('RANGE_TEMPLATE unused RAM offset')
                    elif offset+need>=vectors[vector]['capacity']:
                        raise AssertionError('RANGE_TEMPLATE selected source exceeds descriptor capacity')
            if op==16:
                ctx=contexts[0]
                if length!=1 or desc&~7 or not (ctx>>5&1) or (ctx&31) not in (1,2,3,8):raise AssertionError('SCALAR_TEMPLATE context or length')
                if any(q[k] for k in ('dense','transpose','r4','store_mode','flags')) or any(rf[q[k]] for k in ('k_s','support_length_s','aux_length_s','index_s')) or rf[f['shift_s']]:raise AssertionError('SCALAR_TEMPLATE unused payload')
                for selector in [ctx>>6&3]+([] if (ctx&31)==1 else [ctx>>8&3]):
                    if selector<2 and not ((template['bind_a'] if selector==0 else template['bind_b'])&1):raise AssertionError('SCALAR_TEMPLATE unbound operand')
                for binding,scalar in ((template['bind_a'],scalar_a),(template['bind_b'],scalar_b)):
                    if binding and not -(1<<26)<=scalar<(1<<26):raise ArithmeticError('numeric_fault')
            for i in range(length):
                lane=i%32;ctx=template['contexts'][lane];opcode=ctx&31;imm=(ctx>>10)&((1<<27)-1)
                if imm&(1<<26):imm-=1<<27
                def source(selector):
                    if selector==2:return imm
                    if selector==3:return 0
                    binding=template['bind_a'] if selector==0 else template['bind_b']
                    if binding>>lane&1:return scalar_a if selector==0 else scalar_b
                    index=((a_offset if selector==0 else b_offset)+i) if op==22 else (i if desc>>selector&1 else lane)
                    return element(a if selector==0 else b,index)
                x=source(ctx>>6&3);z=0 if opcode==1 else source(ctx>>8&3)
                raw.append(x if opcode==1 else int(ar.add(x,z,sf)) if opcode==2 else int(ar.sub(x,z,sf)) if opcode==3 else int(ar.mul(x,z,sf,sf,sf)) if opcode==8 else x*z)
            if op==16:value=int(raw[0])
            elif (desc>>3&3)==2:value=sum(raw)
            else:out=raw
        elif op==22:
            # RANGE_TEMPLATE is intentionally modeled independently from the
            # legacy TEMPLATE shortcut: it must support every loaded template
            # output/mode while addressing only its selected source lanes.
            desc=validate_descriptor(template['descriptor'])
            if (not 1<=length<=1024 or desc['inc_a']!=1 or desc['inc_b']!=1 or desc['inc_dst']!=1 or f['target'] or
                    any(q[key] for key in ('dense','transpose','r4','store_mode','flags','support_v','aux_v')) or
                    any(rf[index] for index in (f['shift_s'],q['k_s'],q['support_length_s']))):
                raise AssertionError('RANGE_TEMPLATE canonical payload or descriptor')
            a_offset,b_offset=rf[q['index_s']],rf[q['aux_length_s']]
            if not (0<=a_offset<=1023 and 0<=b_offset<=1023):
                raise AssertionError('RANGE_TEMPLATE offset outside unsigned11 range')
            output=desc['output_kind']; active=[];needs=[None,None]
            for i in range(length):
                lane=i%32;ctx=decode_context(contexts[lane]);validate_context(contexts[lane],template['descriptor'])
                opcode=ctx['op']; selectors=[ctx['src_a']]+([] if opcode==1 else [ctx['src_b']])
                if output==0 and opcode not in (1,2,3,8):raise AssertionError('RANGE_TEMPLATE EACH context')
                if output in (1,2) and opcode!=9:raise AssertionError('RANGE_TEMPLATE accumulator context')
                if output!=1 and desc['shift']:raise AssertionError('RANGE_TEMPLATE shift only LAST_ACC')
                for selector in selectors:
                    if selector<2 and not ((template['bind_a'] if selector==0 else template['bind_b'])>>lane&1):
                        needs[selector]=i if needs[selector] is None else max(needs[selector],i)
                active.append(ctx)
            for offset,need,vector in ((a_offset,needs[0],a),(b_offset,needs[1],b)):
                if need is None:
                    if offset:raise AssertionError('RANGE_TEMPLATE unused RAM offset')
                elif offset+need>=vectors[vector]['capacity']:
                    raise AssertionError('RANGE_TEMPLATE selected source exceeds descriptor capacity')
            def checked(value):
                if not -(1<<26)<=int(value)<(1<<26):raise ArithmeticError('numeric_fault')
                return int(value)
            def acc_add(total,term):
                value=int(total)+int(term)
                if not -(1<<63)<=value<(1<<63):raise ArithmeticError('accumulator_overflow')
                return value
            lane_acc=[0]*32;each=[];total=0
            for i,ctx in enumerate(active):
                lane=i%32
                def source(selector):
                    if selector==2:return int(ctx['immediate'])
                    if selector==3:return 0
                    binding=template['bind_a'] if selector==0 else template['bind_b']
                    scalar=scalar_a if selector==0 else scalar_b
                    if binding>>lane&1:
                        return checked(scalar)
                    return element(a if selector==0 else b,(a_offset if selector==0 else b_offset)+i)
                x=source(ctx['src_a']); z=0 if ctx['op']==1 else source(ctx['src_b'])
                if ctx['op']==1: value_i=checked(x)
                elif ctx['op']==2:value_i=checked(x+z)
                elif ctx['op']==3:value_i=checked(x-z)
                elif ctx['op']==8:
                    if ctx['mode']==0 and not -(1<<17)<=z<(1<<17):raise ArithmeticError('coefficient_overflow')
                    value_i=checked(ar.round_shift(x*z,16 if ctx['mode']==0 else 22))
                else:
                    if ctx['mode']==0 and not -(1<<17)<=z<(1<<17):raise ArithmeticError('coefficient_overflow')
                    product=x*z;lane_acc[lane]=acc_add(lane_acc[lane],product);total=acc_add(total,product);value_i=product
                if output==0:each.append(value_i)
            if output==0:out=each
            elif output==1:
                out=[checked(ar.round_shift(lane_acc[lane],desc['shift'])) for lane in range(min(length,32))]
                count=len(out)
            else:
                value=total
        elif op==1:
            operator=bmatrix if q['dense'] else matrix
            if operator is None:raise AssertionError('dense B not built')
            out=ar.matvec(operator.T if q['transpose'] else operator,read(a,length),PROFILE.coefficient,sf,sf)
        elif op==2:
            out=[ar.clip(ar.round_shift(int(x)*scalar_a,rf[f['shift_s']]),sf) for x in read(a,length)]
        elif op==3:
            fmt=Format(24,20) if q['store_mode']==1 else PROFILE.data
            out=ar.rescale(ar.rescale(read(a,length),sf.frac,fmt),fmt.frac,sf)
        elif op==4:
            out=[max(int(x)-scalar_a,0) if x>=0 else min(int(x)+scalar_a,0) for x in read(a,length)]
        elif op==5:
            source=read(a,length);excluded=set(read(q['support_v'],rf[q['support_length_s']])) if q['flags']&1 else set()
            chosen=sorted((i for i in range(length) if i not in excluded),key=lambda i:(-abs(source[i]),i))[:rf[q['k_s']]]
            out=sorted(chosen) if q['flags']&2 else chosen;count=len(out)
            clear_extent=rf[q['k_s']]
        elif op in (6,7,8):
            support=[int(x) for x in read(q['support_v'],rf[q['support_length_s']])]
            out=[0]*length
            if op==7:out=[int(read(a,i+1)[i]) for i in support]
            elif op==6:
                source=read(a,length)
                for index in support:out[index]=int(source[index])
            else:
                for index,x in zip(support,read(a,len(support))):out[index]=int(x)
            count=len(support)
            if op==6:clear_extent=length
        elif op==9:
            left=list(read(q['support_v'],rf[q['support_length_s']]));right=list(read(q['aux_v'],rf[q['aux_length_s']]))
            out=list(dict.fromkeys(left+right))
            if not q['flags']&1:out.sort()
            if len(out)>rf[q['k_s']]:raise ArithmeticError('support_overflow')
            count=len(out)
            clear_extent=rf[q['k_s']]
        elif op==10:
            if not 0<=rf[q['index_s']]<length:raise AssertionError('PICK index outside domain')
            value=element(a,rf[q['index_s']])
        elif op in (11,12):
            start=rf[q['index_s']];size=rf[q['aux_length_s']]
            if not 0<=start<=start+size<=length:raise AssertionError('range transport bounds')
            source=list(read(a,length))
            if op==11:out=source[start:start+size]
            else:out=source;out[start:start+size]=list(read(q['aux_v'],size))
        elif op==25:
            # Control/capacity reference for the feature10 private factor
            # square reduction.  Arithmetic is deliberately shared with the
            # primary VM; independent integer sums are asserted by its tests.
            if (template['descriptor']!=23 or template['bind_a'] or template['bind_b'] or
                    any(context!=297 for context in contexts) or not q['dense'] or
                    q['transpose'] or q['r4'] or q['store_mode'] or q['k_s'] or
                    q['support_v'] or q['aux_v'] or f['a_v'] or f['b_v'] or
                    f['a_s'] or f['b_s'] or f['shift_s'] or f['target']!=1 or
                    not f['dst_s'] or not f['flag_s'] or f['dst_s']==f['flag_s'] or
                    not 1<=length<=128 or q['flags']&~1):
                raise AssertionError('FACTOR_ENERGY_TAP canonical payload')
            if factors is None:raise AssertionError('FACTOR_ENERGY_TAP without factors')
            support=rf[q['support_length_s']];index=rf[q['index_s']];offset=rf[q['aux_length_s']]
            row=bool(q['flags']&1)
            if (not 1<=support<=96 or factors.shape!=(m,support) or index<0 or offset<0 or
                    (row and (index>=m or offset+length>support)) or
                    (not row and (index>=support or offset+length>m))):
                raise AssertionError('FACTOR_ENERGY_TAP factor range')
            factor_values=[int(factors[index,offset+i] if row else factors[offset+i,index])
                           for i in range(length)]
            value=sum(item*item for item in factor_values)
            if not -(1<<63)<=value<(1<<63):raise ArithmeticError('accumulator_overflow')
            out=factor_values
            count=int(any(item!=0 for item in factor_values[1:]))
        elif op==24:
            # Feature9 factor source plus raw SUM_ACC and candidate tap.  The
            # reference interpreter shares Arithmetic with the primary VM but
            # independently checks command control, capacity, and tap shape.
            if (template['descriptor']!=23 or template['bind_a'] or template['bind_b'] or
                    any(context!=297 for context in contexts) or not q['dense'] or
                    q['transpose'] or q['r4'] or q['store_mode'] or q['k_s'] or
                    q['support_v'] or q['aux_v'] or f['b_v'] or f['b_s'] or
                    f['shift_s'] or f['flag_s'] or f['target'] or not f['dst_s'] or
                    not 1<=length<=128 or q['flags']&~7):
                raise AssertionError('FACTOR_RANGE_TEMPLATE canonical payload')
            patch=bool(q['flags']&4);row=bool(q['flags']&1);head=bool(q['flags']&2)
            if not patch and f['a_s']!=0:raise AssertionError('FACTOR_RANGE_TEMPLATE unpatched scalar A')
            if patch and not -(1<<26)<=scalar_a<(1<<26):raise ArithmeticError('numeric_fault')
            if factors is None:raise AssertionError('FACTOR_RANGE_TEMPLATE without factors')
            support=rf[q['support_length_s']];index=rf[q['index_s']];offset=rf[q['aux_length_s']]
            if (not 1<=support<=96 or factors.shape!=(m,support) or index<0 or offset<0 or
                    (row and (index>=m or offset+length>support)) or
                    (not row and (index>=support or offset+length>m))):
                raise AssertionError('FACTOR_RANGE_TEMPLATE factor range')
            if offset+length>vectors[a]['capacity']:raise AssertionError('FACTOR_RANGE_TEMPLATE source capacity')
            source=[element(a,offset+i) for i in range(length)]
            factor_values=[int(factors[index,offset+i] if row else factors[offset+i,index]) for i in range(length)]
            if patch:factor_values[0]=int(scalar_a)
            value=sum(x*y for x,y in zip(factor_values,source))
            if not -(1<<63)<=value<(1<<63):raise ArithmeticError('accumulator_overflow')
            out=[factor_values[0]] if head else factor_values
            count=len(out)
        elif op==21:
            index=rf[q['index_s']]
            if not 0<=index<length:raise AssertionError('SCALAR_INSERT index outside domain')
            out=[scalar_a if i==index else element(a,i) for i in range(length)]
            count=length
        elif op==23:
            c=read(q['aux_v'],length)
            x=read(a,length)
            y=[scalar_b]*length if template['bind_b'] else read(b,length)
            subtract=contexts[16]==291
            out=[]
            for c_value,x_value,y_value in zip(c,x,y):
                product=int(ar.mul(int(x_value),int(y_value),sf,sf,sf))
                out.append(int(ar.sub(int(c_value),product,sf) if subtract else
                               ar.add(int(c_value),product,sf)))
        elif op==13:
            if bmatrix is None:raise AssertionError('factor INIT without B')
            factors=np.asarray([[int(x)<<6 for x in row] for row in bmatrix],dtype=object)
            count=factors.shape[1]
        elif op==19:
            if bmatrix is None or factors is None:raise AssertionError('factor EXTEND without current B/prefix')
            support=rf[q['support_length_s']];old_support=rf[q['index_s']]
            if (not q['dense'] or q['flags'] or q['aux_length_s'] or length!=m or not 1<=old_support<support<=96 or factors.shape!=(m,old_support) or bmatrix.shape!=(m,support)):
                raise AssertionError('invalid FACTOR_EXTEND command')
            suffix=np.asarray([[int(x)<<6 for x in row] for row in bmatrix[:,old_support:support]],dtype=object)
            factors=np.concatenate((factors,suffix),axis=1);count=support
        elif op in (14,15):
            if factors is None:raise AssertionError('factor uninitialized')
            fixed=rf[q['index_s']];start=rf[q['aux_length_s']]
            coords=[(fixed,start+i) if q['flags']&1 else (start+i,fixed) for i in range(length)]
            if op==14:out=[int(factors[r,c]) for r,c in coords]
            else:
                for (r,c),x in zip(coords,read(a,length)):factors[r,c]=int(x)
            count=length
        elif op in (17,18,20):
            # The resident operation preserves all three serial QR boundaries:
            # ACC64 dot/round22, alpha multiply/round22, then product/round22
            # and checked S27 subtraction.  Q never enters the public pool.
            if factors is None:raise AssertionError('factor uninitialized')
            support=rf[q['support_length_s']];row_start=rf[q['aux_length_s']];col_start=rf[q['index_s']]
            if (not q['dense'] or q['flags'] or not 1<=support<=96 or not 1<=length<=128 or
                    not 0<=row_start<m or row_start+length>m or not 0<=col_start<support or
                    factors.shape != (m,support)):
                raise AssertionError('invalid factor panel command')
            column_count=support-col_start
            left=read(a,length)
            if op==17:
                out=[]
                for column in range(col_start,support):
                    acc=sum(int(factors[row_start+row,column])*int(left[row]) for row in range(length))
                    if not -(1<<63)<=acc<1<<63:raise ArithmeticError('numeric_fault')
                    out.append(int(ar.clip(ar.round_shift(acc,22),sf)))
                count=column_count
            elif op==18:
                right=read(b,column_count)
                updates=[]
                for row in range(length):
                    for offset in range(column_count):
                        product=int(ar.clip(ar.round_shift(int(left[row])*int(right[offset]),22),sf))
                        updates.append((row_start+row,col_start+offset,
                                        int(ar.sub(int(factors[row_start+row,col_start+offset]),product,sf))))
                for row,column,value in updates:factors[row,column]=value
                count=0
            else:
                if not -(1<<26)<=scalar_a<(1<<26):raise ArithmeticError('numeric_fault')
                q_values=[]
                for column in range(col_start,support):
                    acc=sum(int(factors[row_start+row,column])*int(left[row]) for row in range(length))
                    if not -(1<<63)<=acc<1<<63:raise ArithmeticError('numeric_fault')
                    q_values.append(int(ar.clip(ar.round_shift(acc,22),sf)))
                scaled=[int(ar.mul(value,scalar_a,sf,sf,sf)) for value in q_values]
                updates=[]
                for row in range(length):
                    for offset,value in enumerate(scaled):
                        product=int(ar.clip(ar.round_shift(int(left[row])*value,22),sf))
                        updates.append((row_start+row,col_start+offset,
                                        int(ar.sub(int(factors[row_start+row,col_start+offset]),product,sf))))
                for row,column,value in updates:factors[row,column]=value
                count=0
        else:raise NotImplementedError(op)
        if not -(1<<63)<=value<1<<63:raise ArithmeticError('numeric_fault')
        if any(ar.events.values()):raise ArithmeticError('numeric_fault')
        if out is not None:write(d,out,clear_extent);nonzero=any(out)
        else:nonzero=value!=0
        if f['dst_s']:rf[f['dst_s']]=value
        if f['flag_s']:rf[f['flag_s']]=count if f['target']&1 else int(nonzero)
    status=None
    for _ in range(limit):
        f=decode(package['program'][pc]);kind=f['kind'];next_pc=pc+1;trace.append(pc)
        x,z=rf[f['a_s']],rf[f['b_s']];dest=f['dst_s'];imm=f['immediate']
        if kind==1:kernel(f)
        elif kind==2:rf[dest]=ar.ratio(x,z,-10 if imm==246 else 0,sf)
        elif kind==3:
            if x<0:raise ArithmeticError('numeric_fault')
            root=math.isqrt(x);rf[dest]=ar.clip(root+int(x-root*root>root),sf)
        elif kind==4:rf[dest]=imm-(1<<64) if imm>>63 else imm
        elif kind==5:rf[dest]=x
        elif kind==6:rf[dest]=-x
        elif kind==7:
            if not 0<x<(1<<26):raise ArithmeticError('numeric_fault')
            rf[dest]=1<<int(x).bit_length();rf[f['shift_s']]=int(x).bit_length()
        elif kind==8:
            if x==0:next_pc=f['target']
        elif kind==9:
            if x!=0:next_pc=f['target']
        elif kind==10:next_pc=f['target']
        elif kind==11:rf[dest]=int(x*package['constants'][imm&1023]<=z*package['constants'][imm>>10&1023])
        elif kind==12:rf[dest]=x+1
        elif kind==13:
            if x>=z:next_pc=f['target']
        elif kind==16:stack.append(pc+1);next_pc=f['target']
        elif kind==17:next_pc=stack.pop()
        elif kind==18:rf[dest]=package['constants'][x+imm]
        elif kind==19:
            if [x==z,x!=z,x<z,x<=z,x>z,x>=z][imm]:next_pc=f['target']
        elif kind==20:status=next(k for k,v in ABI['statuses'].items() if v==imm);break
        elif kind==21:
            support=[int(i) for i in read(f['a_v'],x)]
            if len(set(support))!=len(support) or any(i<0 or i>=n for i in support):raise AssertionError('invalid BUILD support')
            bmatrix=matrix[:,support].copy()
            # Only the opt-in reuse profile retains a private prefix across BUILD.
            if not package.get('qr_reuse_enabled'):factors=None
        elif kind==22:rf[dest]=x+z
        elif kind==23:rf[dest]=x-z
        elif kind==24:rf[dest]=ar.clip(ar.round_shift(x,22),sf)
        else:raise NotImplementedError(kind)
        if any(ar.events.values()):raise ArithmeticError('numeric_fault')
        rf[0]=0;pc=next_pc
    else:raise AssertionError('program watchdog')
    result=dict(x=read(f['dst_v'],n),residual=read(f['a_v'],m),support=list(read(f['b_v'],rf[29])),
                status=status.lower(),outer=rf[26],inner=rf[25],trace=trace,scalar_registers=list(rf))
    if debug_vectors is not None:
        if not isinstance(debug_vectors, dict):raise ValueError('debug_vectors must map names to lengths')
        by_name={entry['name']:index for index,entry in enumerate(vectors)}
        snapshot={}
        for name,length in debug_vectors.items():
            if name not in by_name:raise AssertionError('unknown debug vector '+str(name))
            if length == 'support':length=rf[28]
            if not isinstance(length,int) or length<0:raise ValueError('invalid debug vector length')
            snapshot[name]=list(read(by_name[name],length))
        result['debug_vectors']=snapshot
        result['debug_factors']=(None if factors is None else [[int(value) for value in row] for row in factors])
    return result

