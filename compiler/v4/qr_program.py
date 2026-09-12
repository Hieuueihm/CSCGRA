"""Loaded Householder QR subroutine; all numeric work uses generic services.

Retained factors contain beta on the diagonal and normalized reflector tails
below it. The initial solve plus a bounded number of correction solves use the
same factors. Only a stored-X normal certificate permits RET.
"""
from fractions import Fraction
from compiler.v4.stream_program import encode_context


def emit_qr(p,prefix,*,rhs_vector='Y',result_vector='PX',support_register=28,
            failure_label,rank_label=None,max_refinements=2,residual_vector=None,
            schedule_compact=False, scalar_template=False, panel_min_columns=0, resident_project=False, scalar_insert=False, stream_scalar_insert=False, range_template=False, factor_range_template=False, factor_energy_tap=False, initial_qty_vector=None):
    if support_register!=28:raise ValueError('QR ABI support register is R28')
    if not isinstance(max_refinements,int) or not 0<=max_refinements<=2:raise ValueError('QR correction bound0..2')
    if not isinstance(panel_min_columns,int) or not 0<=panel_min_columns<=96:raise ValueError('panel minimum must be0..96')
    if resident_project and not panel_min_columns:raise ValueError('resident project requires reachable panel schedule')
    if factor_range_template and not range_template:raise ValueError('factor range template requires QR view schedule')
    if factor_energy_tap and not range_template:raise ValueError('factor energy tap requires QR view schedule')
    if p.a.vectors[p.v[result_vector]]['capacity']<96:raise ValueError('QR result capacity96 required')
    if initial_qty_vector is not None and p.a.vectors[p.v[initial_qty_vector]]['capacity']<p.m:raise ValueError('QR QTy cache capacityM required')
    rank_label=rank_label or failure_label;a=p.a
    keys=['V','A','W','P','Y','R','D','T','ONE','SC']
    # Do not allocate a descriptor in legacy schedules: this keeps their
    # program/vector image byte-identical when panel code is disabled.
    if panel_min_columns and not resident_project:keys.append('Q')
    names={key:prefix+'_'+key for key in keys}
    for key in names:p.vec(names[key],96 if key in ('D','T') else 1 if key in ('ONE','SC') else 128)
    v=lambda key:names[key]
    label=lambda key:prefix+'_'+key
    def branch(kind,key,**kw):p.branch(kind,label(key),**kw)
    def mov(dst,src):a.emit('MOV',dst_s=dst,a_s=src)
    def sub64(dst,left,right):a.emit('SUB64',dst_s=dst,a_s=left,b_s=right)
    def k(op,dst,src=None,length=None,shift=0,**kw):
        p.call(op,v(dst),v(src or dst),length=length,**kw)
        if shift:a.instructions[-1][1]['shift_s']=shift
    def pick(dst,src,index=0):k('PICK',src,length=p.m if src=='Y' else (28,) if src=='T' else 1,out=dst,index_s=index)
    def scalar(dst,reg):p.op('scalar',v(dst),length=1,scalar=reg)
    def state_sub(dst,left,right):
        if scalar_template:
            p.scalar_template('SUB',dst,left,right)
        else:
            scalar('SC',left);scalar('P',right);p.op('sub',v('SC'),v('SC'),v('P'),length=1);pick(dst,'SC')
    def slice_(dst,src,domain,start,count):
        k('SLICE',dst,src,domain,index_s=start,aux_length_s=count)
    def replace(dst,src,domain,packed,start,count):
        k('REPLACE_RANGE',dst,src,domain,aux_v=p.v[v(packed)],index_s=start,aux_length_s=count)
    def factor(op,dst,length,index,start,row=False):
        k(op,dst,length=length,dense=1,support_length_s=28,index_s=index,aux_length_s=start,flags=int(row))
    def factor_range(dst,src,length,index,offset,flags,scalar_register=0,out=0):
        # Op24 has a factor-private source and a public A range.  Its external
        # template is MAC/SUM_ACC, while the kernel internally remaps the tap.
        p.call('FACTOR_RANGE_TEMPLATE',v(dst),v(src),length=length,
               template='factor_range_template',out=out,sa=scalar_register,
               dense=1,support_length_s=28,index_s=index,
               aux_length_s=offset,flags=flags)
    def factor_energy(dst,length,index,offset,out,flag):
        # Op25 consumes factor lanes twice.  X is descriptor zero and is never
        # read; both source fields therefore remain canonical raw zero.
        p.call('FACTOR_ENERGY_TAP',v(dst),'X','X',length=length,
               template='factor_energy_tap',out=out,flag=flag,count=True,
               dense=1,support_length_s=28,index_s=index,
               aux_length_s=offset)
    if scalar_insert or stream_scalar_insert:
        # Opcode21 uses an inert loaded entry; the scalar value is carried by RF.
        p.t['scalar_insert']=len(a.templates)
        a.templates.append(dict(name='scalar_insert',descriptor=0,bind_a=0,bind_b=0,contexts=[0]*32))
    if factor_range_template:
        p.t['factor_range_template']=a.template('factor_range_template','MAC','SUM_ACC',src_a='A',src_b='B',mode=1)
    if factor_energy_tap:
        p.t['factor_energy_tap']=a.template('factor_energy_tap','MAC','SUM_ACC',src_a='A',src_b='B',mode=1)
    if panel_min_columns:
        if resident_project:
            # Descriptor31/kind3 is a feature5-only packed phase image.  It
            # is consumed only by FACTOR_PROJECT_UPDATE, never by TEMPLATE.
            # No public Q descriptor or ordinary panel templates are loaded.
            p.t['factor_project_update']=len(a.templates)
            a.templates.append(dict(name='factor_project_update', descriptor=31, bind_a=0, bind_b=0,
                                    contexts=[encode_context(op='MAC',mode=1,src_a='A',src_b='B'),
                                              encode_context(op='MUL',mode=1,src_a='A',src_b='B'),
                                              encode_context(op='SUB',mode=1,src_a='A',src_b='B')]+[0]*29))
        else:
            # Panel services consume ordinary loaded, direct A/B contexts.
            # The rank-update image is split across the existing arrays.
            p.t['factor_matvec']=a.template('factor_matvec','MAC','SUM_ACC',src_a='A',src_b='B',mode=1)
            rank=p.t['factor_rank1']=a.template('factor_rank1','MUL','EACH',src_a='A',src_b='B',mode=1)
            mul_context=a.templates[rank]['contexts'][0]
            sub_context=encode_context(op='SUB',mode=1,src_a='A',src_b='B')
            a.templates[rank]['contexts']=[mul_context]*16+[sub_context]*16
    def panel_update():
        # The resident phase keeps q private.  Its three explicit arithmetic
        # boundaries match MATVEC -> SCALE -> RANK1 exactly.
        if resident_project:
            p.call('FACTOR_PROJECT_UPDATE','X',v('V'),'X',length=(2,),template='factor_project_update',
                   dense=1,sa=8,support_length_s=28,index_s=3,aux_length_s=1)
        else:
            p.call('FACTOR_MATVEC',v('Q'),v('V'),length=(2,),template='factor_matvec',dense=1,
                   support_length_s=28,index_s=3,aux_length_s=1)
            p.scale_op(v('Q'),v('Q'),8,(12,))
            p.call('FACTOR_RANK1',v('Q'),v('V'),v('Q'),length=(2,),template='factor_rank1',dense=1,
                   support_length_s=28,index_s=3,aux_length_s=1)
    def stream_insert(dst,src,domain,scalar_register,index_register):
        p.call('SCALAR_INSERT',v(dst),v(src),length=domain,template='scalar_insert',
               sa=scalar_register,index_s=index_register)
    def range_call(dst,left,right,length,template,out=0,a_offset=0,b_offset=0):
        p.call('RANGE_TEMPLATE',v(dst),v(left),v(right),length=length,template=template,
               out=out,index_s=a_offset,aux_length_s=b_offset)
    def apply():
        p.op('dot',v('W'),v('V'),v('W'),length=(2,),out=11)
        a.emit('RESCALE',dst_s=11,a_s=11)
        if scalar_template:
            p.scalar_template('MUL',12,8,11)
        else:
            scalar('SC',8);p.scale_op(v('SC'),v('SC'),11,1);pick(12,'SC')
        p.scale_op(v('P'),v('V'),12,(2,));p.op('sub',v('W'),v('W'),v('P'),length=(2,))
    def dense_mv(dst,src,transpose):
        p.call('GEMV',dst,src,length=p.m if transpose else (28,),template='gemv',dense=1,transpose=int(transpose),support_length_s=28)
    tolerance=Fraction(str(p.policy.ls_normal_rtol))
    if not 0<tolerance<1:raise ValueError('QR certificate tolerance must lie in(0,1)')
    c_left=a.constant(tolerance.denominator**2);c_right=a.constant(tolerance.numerator**2)
    a.label(prefix)
    p.set(25,0);p.set(15,0);p.branch('BR_ZERO',failure_label,a_s=28)
    p.set(12,p.m);p.branch('BR_COMPARE',rank_label,a_s=28,b_s=12,immediate=4)
    p.set(12,96);p.branch('BR_COMPARE',rank_label,a_s=28,b_s=12,immediate=4)
    p.set(15,1<<22);scalar('ONE',15)
    p.op('zero',v('T'),length=(28,))
    if not schedule_compact:p.op('zero',v('D'),length=(28,))
    factor('FACTOR_INIT','A',p.m,0,0)
    p.set(1,0)
    a.label(label('factor'))
    p.set(12,p.m);sub64(2,12,1);mov(4,1);p.inc(4)
    if factor_energy_tap:
        # Full unpatched tap, raw factor-square energy and an exact tail-zero
        # flag replace FACTOR_READ plus two public ENERGY passes.  R10 is
        # scratch until reciprocal preparation below.
        factor_energy('A',(2,),1,1,11,10)
        pick(5,'A');p.set(15,1);sub64(12,2,15)
        branch('BR_ZERO','tail_zero',a_s=10)
        a.emit('SQRT',dst_s=6,a_s=11)
    else:
        factor('FACTOR_READ','A',(2,),1,1)
        pick(5,'A');p.set(15,1);sub64(12,2,15)
        branch('BR_ZERO','tail_zero',a_s=12)
        slice_('W','A',(2,),15,12);p.energy(v('W'),11,(12,));branch('BR_ZERO','tail_zero',a_s=11)
        p.energy(v('A'),11,(2,));a.emit('SQRT',dst_s=6,a_s=11)
    branch('BR_COMPARE','beta_ready',a_s=5,b_s=0,immediate=2)
    a.emit('NEG',dst_s=6,a_s=6)
    a.label(label('beta_ready'))
    state_sub(7,5,6);state_sub(11,6,5);p.div(8,11,6)
    mov(9,7);branch('BR_COMPARE','abs_ready',a_s=9,b_s=0,immediate=5);a.emit('NEG',dst_s=9,a_s=9)
    a.label(label('abs_ready'));p.set(10,1<<26)
    branch('BR_COMPARE','recip_regular',a_s=9,b_s=10,immediate=1)
    p.set(10,1<<27);p.set(9,27);branch('JUMP','recip_div')
    a.label(label('recip_regular'));a.emit('RECIP_PREP',dst_s=10,a_s=9,shift_s=9)
    a.label(label('recip_div'));p.div(10,10,7)
    if factor_energy_tap:
        # The op25 candidate is the full unpatched factor range; keep the
        # legacy packed-tail input to NORMALIZE after the tail-zero branch.
        slice_('W','A',(2,),15,12)
    k('NORMALIZE','V','W',(12,),sa=10,shift=9,template='dot')
    # Shift the packed tail right by one using a cleared full active vector.
    # A is already valid. Its head is overwritten by ONE below, while every
    # tail element is replaced now; clearing A first has no observable value.
    if not schedule_compact:p.op('zero',v('A'),length=(2,))
    replace('V','A',(2,),'V',15,12)
    if stream_scalar_insert:
        p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
    else:replace('V','V',(2,),'ONE',0,15)
    branch('JUMP','reflector_ready')
    a.label(label('tail_zero'));mov(6,5);p.set(8,0)
    p.op('zero',v('V'),length=(2,))
    if stream_scalar_insert:
        p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
    else:replace('V','V',(2,),'ONE',0,15)
    a.label(label('reflector_ready'));p.branch('BR_ZERO',rank_label,a_s=6)
    if stream_scalar_insert:
        stream_insert('T','T',(28,),8,1);stream_insert('A','V',(2,),6,0)
    else:
        scalar('SC',8);replace('T','T',(28,),'SC',1,15)
        scalar('SC',6);replace('A','V',(2,),'SC',0,15)
    factor('FACTOR_WRITE','A',(2,),1,1)
    mov(3,4);branch('BR_ZERO','factor_next',a_s=8)
    if panel_min_columns:
        # The bound is compile-time selected by the caller.  At runtime only
        # wide trailing rectangles enter the generic panel service; narrow
        # tails retain the existing serial sequence and its exact schedule.
        p.set(13,panel_min_columns)
        a.label(label('columns'));branch('BR_GE','factor_next',a_s=3,b_s=28)
        sub64(12,28,3);branch('BR_COMPARE','panel_columns',a_s=12,b_s=13,immediate=5)
        factor('FACTOR_READ','W',(2,),3,1);apply();factor('FACTOR_WRITE','W',(2,),3,1)
        p.inc(3);branch('JUMP','columns')
        a.label(label('panel_columns'));panel_update();branch('JUMP','factor_next')
    else:
        a.label(label('columns'));branch('BR_GE','factor_next',a_s=3,b_s=28)
        factor('FACTOR_READ','W',(2,),3,1);apply();factor('FACTOR_WRITE','W',(2,),3,1)
        p.inc(3);branch('JUMP','columns')
    a.label(label('factor_next'));p.inc(1);branch('BR_COMPARE','factor',a_s=1,b_s=28,immediate=2)
    dense_mv(v('W'),rhs_vector,True);p.energy(v('W'),13,(28,))
    p.op('copy',v('Y'),rhs_vector,length=p.m);branch('CALL','solve')
    # Capture the initial Q^T RHS before residual corrections can overwrite Y.
    if initial_qty_vector is not None:p.op('copy',initial_qty_vector,v('Y'),length=p.m)
    p.set(25,1)
    p.call('STORE',result_vector,v('D'),length=(28,),store_mode=1)
    a.label(label('certificate'))
    dense_mv(v('W'),result_vector,False);p.op('sub',v('R'),rhs_vector,v('W'),length=p.m)
    dense_mv(v('W'),v('R'),True);p.energy(v('W'),14,(28,))
    a.emit('CERT',dst_s=15,a_s=14,b_s=13,immediate=c_left|(c_right<<10))
    branch('BR_NONZERO','success',a_s=15);p.set(15,max_refinements+1)
    p.branch('BR_GE',failure_label,a_s=25,b_s=15)
    p.op('copy',v('Y'),v('R'),length=p.m);branch('CALL','solve')
    p.op('add',v('D'),result_vector,v('D'),length=(28,));p.call('STORE',result_vector,v('D'),length=(28,),store_mode=1)
    p.inc(25);branch('JUMP','certificate')
    a.label(label('success'))
    if residual_vector is not None:p.op('copy',residual_vector,v('R'),length=p.m)
    p.set(15,1);a.emit('RET')
    # Apply retained reflectors to the supplied RHS, then triangular backsolve.
    a.label(label('solve'));p.set(1,0)
    a.label(label('qt'))
    p.set(12,p.m);sub64(2,12,1);pick(8,'T',1);branch('BR_ZERO','qt_next',a_s=8)
    if factor_range_template:
        p.set(15,1<<22)
        factor_range('V','Y',(2,),1,1,4,scalar_register=15,out=11)
    else:
        factor('FACTOR_READ','V',(2,),1,1)
        if stream_scalar_insert:
            p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
        else:
            p.set(15,1);replace('V','V',(2,),'ONE',0,15)
    if factor_range_template:
        # Op24 supplied the same raw dot in R11.  Keep the established
        # rescale/tau/product/subtract order after replacing only the source
        # read, head patch, and range MAC.
        a.emit('RESCALE',dst_s=11,a_s=11)
        if scalar_template:p.scalar_template('MUL',12,8,11)
        else:scalar('SC',8);p.scale_op(v('SC'),v('SC'),11,1);pick(12,'SC')
        p.scale_op(v('P'),v('V'),12,(2,))
        range_call('W','Y','P',(2,),'sub',a_offset=1)
        replace('Y','Y',p.m,'W',1,2)
    elif range_template:
        range_call('W','V','Y',(2,),'dot',out=11,b_offset=1)
        a.emit('RESCALE',dst_s=11,a_s=11)
        if scalar_template:p.scalar_template('MUL',12,8,11)
        else:scalar('SC',8);p.scale_op(v('SC'),v('SC'),11,1);pick(12,'SC')
        p.scale_op(v('P'),v('V'),12,(2,))
        range_call('W','Y','P',(2,),'sub',a_offset=1)
        replace('Y','Y',p.m,'W',1,2)
    else:
        slice_('W','Y',p.m,1,2);apply();replace('Y','Y',p.m,'W',1,2)
    a.label(label('qt_next'));p.inc(1);branch('BR_COMPARE','qt',a_s=1,b_s=28,immediate=2)
    p.op('zero',v('D'),length=(28,));p.set(15,1);sub64(1,28,15)
    a.label(label('back'))
    sub64(2,28,1);mov(4,1);p.inc(4);p.set(15,1);sub64(12,2,15)
    if factor_range_template:
        p.set(11,0);branch('BR_ZERO','back_l1',a_s=12)
        factor_range('A','D',(2,),1,1,3,out=11)
        p.call('PICK',v('A'),v('A'),length=1,out=7,index_s=0)
        a.emit('RESCALE',dst_s=11,a_s=11);branch('JUMP','dot_ready')
        a.label(label('back_l1'));factor('FACTOR_READ','A',(2,),1,1,True);pick(7,'A')
        branch('JUMP','dot_ready')
    else:
        factor('FACTOR_READ','A',(2,),1,1,True);pick(7,'A')
        p.set(11,0);branch('BR_ZERO','dot_ready',a_s=12)
    if factor_range_template:
        pass
    elif range_template:
        range_call('W','A','D',(2,),'dot',out=11,b_offset=1)
    elif schedule_compact:
        # D[k] is still exactly zero in backward substitution. Including the
        # leading diag*0 term preserves every sum and the sole round22, and
        # avoids slicing the factor row a second time.
        slice_('P','D',(28,),1,2)
        p.op('dot',v('W'),v('A'),v('P'),length=(2,),out=11)
    else:
        slice_('W','A',(2,),15,12);slice_('P','D',(28,),4,12)
        p.op('dot',v('W'),v('W'),v('P'),length=(12,),out=11)
    if not factor_range_template:a.emit('RESCALE',dst_s=11,a_s=11)
    a.label(label('dot_ready'));pick(5,'Y',1);state_sub(5,5,11);p.div(5,5,7)
    if scalar_insert:
        p.call('SCALAR_INSERT',v('D'),v('D'),length=(28,),template='scalar_insert',sa=5,index_s=1)
    else:
        scalar('SC',5);replace('D','D',(28,),'SC',1,15)
    branch('BR_ZERO','solve_done',a_s=1);sub64(1,1,15);branch('JUMP','back')
    a.label(label('solve_done'));a.emit('RET')
    return dict(entry=prefix,result_vector=result_vector,residual_vector=residual_vector,
                certificate_rtol=str(p.policy.ls_normal_rtol),max_refinements=max_refinements,
                scratch_vectors=names,clobber_registers=list(range(1,16))+[25],preserve_registers=list(range(16,25))+list(range(26,32)))


def emit_qr_reuse(p,prefix,*,rhs_vector='Y',result_vector='PX',support_register=28,
                  old_count_register=24,tau_vector='RU_T',qty_vector='RU_QTY',
                  failure_label,rank_label=None,max_refinements=2,
                  residual_vector=None,schedule_compact=False,
                  scalar_template=False,panel_min_columns=0,resident_project=False,scalar_insert=False,stream_scalar_insert=False,range_template=False,factor_range_template=False,factor_energy_tap=False,
                  full_solve_label='qr_solve',workspace_prefix='qr'):
    """Extend an already certified factor prefix without retaining a factor copy.

    FACTOR_EXTEND has already imported the B suffix before this subroutine.  The
    caller owns the ordered-prefix and immutable-job/RHS proof; this subroutine
    only performs the exact reflector arithmetic on the retained private image.
    """
    if support_register!=28:raise ValueError('QR ABI support register is R28')
    if not isinstance(max_refinements,int) or not 0<=max_refinements<=2:raise ValueError('QR correction bound0..2')
    if not isinstance(panel_min_columns,int) or not 0<=panel_min_columns<=96:raise ValueError('panel minimum must be0..96')
    if resident_project and 'factor_project_update' not in p.t:raise ValueError('resident phase template absent')
    if factor_range_template and 'factor_range_template' not in p.t:raise ValueError('factor range template absent')
    if factor_energy_tap and 'factor_energy_tap' not in p.t:raise ValueError('factor energy tap template absent')
    rank_label=rank_label or failure_label;a=p.a
    names={key:workspace_prefix+'_'+key for key in ('V','A','W','P','Y','R','D','T','ONE','SC')}
    if panel_min_columns and not resident_project:names['Q']=workspace_prefix+'_Q'
    for name in (*names.values(),tau_vector,qty_vector):
        if name not in p.v:raise ValueError('reuse QR vector is absent: '+name)
    v=lambda key:names[key]
    label=lambda key:prefix+'_'+key
    def branch(kind,key,**kw):p.branch(kind,label(key),**kw)
    def mov(dst,src):a.emit('MOV',dst_s=dst,a_s=src)
    def sub64(dst,left,right):a.emit('SUB64',dst_s=dst,a_s=left,b_s=right)
    def k(op,dst,src=None,length=None,shift=0,**kw):
        p.call(op,v(dst),v(src or dst),length=length,**kw)
        if shift:p.a.instructions[-1][1]['shift_s']=shift
    def factor(op,dst,length,index,start,row=False):
        k(op,dst,length=length,dense=1,support_length_s=support_register,
          index_s=index,aux_length_s=start,flags=int(row))
    def factor_range(dst,src,length,index,offset,flags,scalar_register=0,out=0):
        p.call('FACTOR_RANGE_TEMPLATE',v(dst),v(src),length=length,
               template='factor_range_template',out=out,sa=scalar_register,
               dense=1,support_length_s=support_register,index_s=index,
               aux_length_s=offset,flags=flags)
    def factor_energy(dst,length,index,offset,out,flag):
        p.call('FACTOR_ENERGY_TAP',v(dst),'X','X',length=length,
               template='factor_energy_tap',out=out,flag=flag,count=True,
               dense=1,support_length_s=support_register,index_s=index,
               aux_length_s=offset)
    def scalar(dst,reg):p.op('scalar',v(dst),length=1,scalar=reg)
    def state_sub(dst,left,right):
        if scalar_template:p.scalar_template('SUB',dst,left,right)
        else:
            scalar('SC',left);scalar('P',right)
            p.op('sub',v('SC'),v('SC'),v('P'),length=1)
            p.call('PICK',v('SC'),v('SC'),length=1,out=dst,index_s=0)
    def slice_(dst,src,domain,start,count):
        k('SLICE',dst,src,domain,index_s=start,aux_length_s=count)
    def replace(dst,src,domain,packed,start,count):
        k('REPLACE_RANGE',dst,src,domain,aux_v=p.v[v(packed)],index_s=start,aux_length_s=count)
    def reflector_apply():
        p.op('dot',v('W'),v('V'),v('W'),length=(2,),out=11)
        a.emit('RESCALE',dst_s=11,a_s=11)
        if scalar_template:
            p.scalar_template('MUL',12,8,11)
        else:
            scalar('SC',8);p.scale_op(v('SC'),v('SC'),11,1)
            p.call('PICK',v('SC'),v('SC'),length=1,out=12,index_s=0)
        p.scale_op(v('P'),v('V'),12,(2,));p.op('sub',v('W'),v('W'),v('P'),length=(2,))
    def dense_mv(dst,src,transpose):
        p.call('GEMV',dst,src,length=p.m if transpose else (support_register,),template='gemv',dense=1,transpose=int(transpose),support_length_s=support_register)
    def stream_insert(dst,src,domain,scalar_register,index_register):
        p.call('SCALAR_INSERT',v(dst),v(src),length=domain,template='scalar_insert',
               sa=scalar_register,index_s=index_register)
    def range_call(dst,left,right,length,template,out=0,a_offset=0,b_offset=0):
        p.call('RANGE_TEMPLATE',v(dst),v(left),v(right),length=length,template=template,
               out=out,index_s=a_offset,aux_length_s=b_offset)
    tolerance=Fraction(str(p.policy.ls_normal_rtol))
    c_left=a.constant(tolerance.denominator**2);c_right=a.constant(tolerance.numerator**2)
    a.label(prefix)
    # The cache keeps tau explicitly.  Copy it into the QR workspace before
    # appending so only suffix positions are overwritten.
    p.op('zero',v('T'),length=(support_register,))
    # COPY publishes only its requested mask.  On a shared 32-lane word that
    # would invalidate the zeroed suffix after old S, so insert the prefix
    # into the already-published new-S domain instead.
    p.call('REPLACE_RANGE',v('T'),v('T'),length=(support_register,),
           aux_v=p.v[tau_vector],index_s=0,aux_length_s=old_count_register)
    p.set(1,0)
    a.label(label('old_reflector'))
    p.branch('BR_GE',label('old_reflector_done'),a_s=1,b_s=old_count_register)
    p.set(12,p.m);sub64(2,12,1)
    factor('FACTOR_READ','V',(2,),1,1)
    if stream_scalar_insert:
        p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
    else:
        p.set(15,1);replace('V','V',(2,),'ONE',0,15)
    p.call('PICK',v('SC'),tau_vector,length=(old_count_register,),out=8,index_s=1)
    p.branch('BR_ZERO',label('old_reflector_next'),a_s=8)
    mov(3,old_count_register)
    a.label(label('old_columns'))
    p.branch('BR_GE',label('old_reflector_next'),a_s=3,b_s=support_register)
    factor('FACTOR_READ','W',(2,),3,1);reflector_apply();factor('FACTOR_WRITE','W',(2,),3,1)
    p.inc(3);p.branch('JUMP',label('old_columns'))
    a.label(label('old_reflector_next'));p.inc(1);p.branch('JUMP',label('old_reflector'))
    a.label(label('old_reflector_done'))
    # Construct reflectors only for the imported suffix.  This is the same
    # integer sequence as emit_qr's factor loop, starting at old S.
    mov(1,old_count_register)
    a.label(label('factor'))
    p.set(12,p.m);sub64(2,12,1);mov(4,1);p.inc(4)
    if factor_energy_tap:
        factor_energy('A',(2,),1,1,11,10)
        p.call('PICK',v('SC'),v('A'),length=(2,),out=5,index_s=0)
        p.set(15,1);sub64(12,2,15)
        p.branch('BR_ZERO',label('tail_zero'),a_s=10)
        a.emit('SQRT',dst_s=6,a_s=11)
    else:
        factor('FACTOR_READ','A',(2,),1,1)
        p.call('PICK',v('SC'),v('A'),length=(2,),out=5,index_s=0)
        p.set(15,1);sub64(12,2,15)
        p.branch('BR_ZERO',label('tail_zero'),a_s=12)
        slice_('W','A',(2,),15,12);p.energy(v('W'),11,(12,));p.branch('BR_ZERO',label('tail_zero'),a_s=11)
        p.energy(v('A'),11,(2,));a.emit('SQRT',dst_s=6,a_s=11)
    p.branch('BR_COMPARE',label('beta_ready'),a_s=5,b_s=0,immediate=2);a.emit('NEG',dst_s=6,a_s=6)
    a.label(label('beta_ready'));state_sub(7,5,6);state_sub(11,6,5);p.div(8,11,6)
    mov(9,7);p.branch('BR_COMPARE',label('abs_ready'),a_s=9,b_s=0,immediate=5);a.emit('NEG',dst_s=9,a_s=9)
    a.label(label('abs_ready'));p.set(10,1<<26)
    p.branch('BR_COMPARE',label('recip_regular'),a_s=9,b_s=10,immediate=1)
    p.set(10,1<<27);p.set(9,27);p.branch('JUMP',label('recip_div'))
    a.label(label('recip_regular'));a.emit('RECIP_PREP',dst_s=10,a_s=9,shift_s=9)
    a.label(label('recip_div'));p.div(10,10,7)
    if factor_energy_tap:
        slice_('W','A',(2,),15,12)
    k('NORMALIZE','V','W',(12,),sa=10,shift=9,template='dot')
    if not schedule_compact:p.op('zero',v('A'),length=(2,))
    replace('V','A',(2,),'V',15,12)
    if stream_scalar_insert:
        p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
    else:replace('V','V',(2,),'ONE',0,15)
    p.branch('JUMP',label('reflector_ready'))
    a.label(label('tail_zero'));mov(6,5);p.set(8,0);p.op('zero',v('V'),length=(2,))
    if stream_scalar_insert:
        p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
    else:replace('V','V',(2,),'ONE',0,15)
    a.label(label('reflector_ready'));p.branch('BR_ZERO',rank_label,a_s=6)
    if stream_scalar_insert:
        stream_insert('T','T',(support_register,),8,1);stream_insert('A','V',(2,),6,0)
    else:
        scalar('SC',8);replace('T','T',(support_register,),'SC',1,15)
        scalar('SC',6);replace('A','V',(2,),'SC',0,15)
    factor('FACTOR_WRITE','A',(2,),1,1)
    mov(3,4);p.branch('BR_ZERO',label('factor_next'),a_s=8)
    if panel_min_columns:
        p.set(13,panel_min_columns);a.label(label('columns'))
        p.branch('BR_GE',label('factor_next'),a_s=3,b_s=support_register)
        sub64(12,support_register,3);p.branch('BR_COMPARE',label('panel_columns'),a_s=12,b_s=13,immediate=5)
        factor('FACTOR_READ','W',(2,),3,1);reflector_apply();factor('FACTOR_WRITE','W',(2,),3,1)
        p.inc(3);p.branch('JUMP',label('columns'))
        a.label(label('panel_columns'))
        if resident_project:
            p.call('FACTOR_PROJECT_UPDATE','X',v('V'),'X',length=(2,),template='factor_project_update',dense=1,sa=8,support_length_s=support_register,index_s=3,aux_length_s=1)
        else:
            p.call('FACTOR_MATVEC',v('Q'),v('V'),length=(2,),template='factor_matvec',dense=1,support_length_s=support_register,index_s=3,aux_length_s=1)
            p.scale_op(v('Q'),v('Q'),8,(12,))
            p.call('FACTOR_RANK1',v('Q'),v('V'),v('Q'),length=(2,),template='factor_rank1',dense=1,support_length_s=support_register,index_s=3,aux_length_s=1)
        p.branch('JUMP',label('factor_next'))
    else:
        a.label(label('columns'));p.branch('BR_GE',label('factor_next'),a_s=3,b_s=support_register)
        factor('FACTOR_READ','W',(2,),3,1);reflector_apply();factor('FACTOR_WRITE','W',(2,),3,1)
        p.inc(3);p.branch('JUMP',label('columns'))
    a.label(label('factor_next'));p.inc(1);p.branch('BR_COMPARE',label('factor'),a_s=1,b_s=support_register,immediate=2)
    # The certificate denominator is for the new B^T original RHS.  It is
    # never borrowed from the prefix and must not retain the panel threshold.
    dense_mv(v('W'),rhs_vector,True);p.energy(v('W'),13,(support_register,))
    # Initial RHS uses cached Q_old^T y and applies only new reflectors.
    p.op('copy',v('Y'),qty_vector,length=p.m);mov(1,old_count_register)
    a.label(label('qty'))
    p.branch('BR_GE',label('qty_done'),a_s=1,b_s=support_register)
    p.set(12,p.m);sub64(2,12,1)
    p.call('PICK',v('SC'),v('T'),length=(support_register,),out=8,index_s=1)
    p.branch('BR_ZERO',label('qty_next'),a_s=8)
    if factor_range_template:
        p.set(15,1<<22)
        factor_range('V','Y',(2,),1,1,4,scalar_register=15,out=11)
    else:
        factor('FACTOR_READ','V',(2,),1,1)
        if stream_scalar_insert:
            p.set(15,1<<22);stream_insert('V','V',(2,),15,0)
        else:
            p.set(15,1);replace('V','V',(2,),'ONE',0,15)
    if factor_range_template:
        # Op24 supplied the raw QTy dot.  The remaining reflector update is
        # intentionally identical to the range-template schedule.
        a.emit('RESCALE',dst_s=11,a_s=11)
        if scalar_template:p.scalar_template('MUL',12,8,11)
        else:scalar('SC',8);p.scale_op(v('SC'),v('SC'),11,1);p.call('PICK',v('SC'),v('SC'),length=1,out=12,index_s=0)
        p.scale_op(v('P'),v('V'),12,(2,))
        range_call('W','Y','P',(2,),'sub',a_offset=1)
        replace('Y','Y',p.m,'W',1,2)
    elif range_template:
        range_call('W','V','Y',(2,),'dot',out=11,b_offset=1)
        a.emit('RESCALE',dst_s=11,a_s=11)
        if scalar_template:p.scalar_template('MUL',12,8,11)
        else:scalar('SC',8);p.scale_op(v('SC'),v('SC'),11,1);p.call('PICK',v('SC'),v('SC'),length=1,out=12,index_s=0)
        p.scale_op(v('P'),v('V'),12,(2,))
        range_call('W','Y','P',(2,),'sub',a_offset=1)
        replace('Y','Y',p.m,'W',1,2)
    else:
        slice_('W','Y',p.m,1,2);reflector_apply();replace('Y','Y',p.m,'W',1,2)
    a.label(label('qty_next'));p.inc(1);p.branch('JUMP',label('qty'))
    a.label(label('qty_done'));p.op('copy',qty_vector,v('Y'),length=p.m)
    # Full triangular solve with the retained old prefix and appended suffix.
    p.op('zero',v('D'),length=(support_register,));p.set(15,1);sub64(1,support_register,15)
    a.label(label('back'))
    sub64(2,support_register,1);mov(4,1);p.inc(4);p.set(15,1);sub64(12,2,15)
    if factor_range_template:
        p.set(11,0);p.branch('BR_ZERO',label('back_l1'),a_s=12)
        factor_range('A','D',(2,),1,1,3,out=11)
        p.call('PICK',v('SC'),v('A'),length=1,out=7,index_s=0)
        a.emit('RESCALE',dst_s=11,a_s=11);p.branch('JUMP',label('dot_ready'))
        a.label(label('back_l1'));factor('FACTOR_READ','A',(2,),1,1,True);p.call('PICK',v('SC'),v('A'),length=(2,),out=7,index_s=0)
        p.branch('JUMP',label('dot_ready'))
    else:
        factor('FACTOR_READ','A',(2,),1,1,True);p.call('PICK',v('SC'),v('A'),length=(2,),out=7,index_s=0)
        p.set(11,0);p.branch('BR_ZERO',label('dot_ready'),a_s=12)
    if factor_range_template:
        pass
    elif range_template:
        range_call('W','A','D',(2,),'dot',out=11,b_offset=1)
    elif schedule_compact:
        slice_('P','D',(support_register,),1,2);p.op('dot',v('W'),v('A'),v('P'),length=(2,),out=11)
    else:
        slice_('W','A',(2,),15,12);slice_('P','D',(support_register,),4,12);p.op('dot',v('W'),v('W'),v('P'),length=(12,),out=11)
    if not factor_range_template:a.emit('RESCALE',dst_s=11,a_s=11)
    a.label(label('dot_ready'));p.call('PICK',v('SC'),v('Y'),length=(support_register,),out=5,index_s=1);state_sub(5,5,11);p.div(5,5,7)
    if scalar_insert:
        p.call('SCALAR_INSERT',v('D'),v('D'),length=(support_register,),template='scalar_insert',sa=5,index_s=1)
    else:
        scalar('SC',5);replace('D','D',(support_register,),'SC',1,15)
    p.branch('BR_ZERO',label('initial_solve_done'),a_s=1);sub64(1,1,15);p.branch('JUMP',label('back'))
    a.label(label('initial_solve_done'));p.set(25,1);p.call('STORE',result_vector,v('D'),length=(support_register,),store_mode=1)
    # A correction deliberately calls the full reflector solve, never the
    # cached Q^T RHS.  Emit the same certificate sequence for the initial
    # candidate and every correction without maintaining two implementations.
    def certificate_block():
        dense_mv(v('W'),result_vector,False);p.op('sub',v('R'),rhs_vector,v('W'),length=p.m)
        dense_mv(v('W'),v('R'),True);p.energy(v('W'),14,(support_register,))
        a.emit('CERT',dst_s=15,a_s=14,b_s=13,immediate=c_left|(c_right<<10))
        p.branch('BR_NONZERO',label('success'),a_s=15);p.set(15,max_refinements+1)
        p.branch('BR_GE',failure_label,a_s=25,b_s=15)
        p.op('copy',v('Y'),v('R'),length=p.m);p.branch('CALL',full_solve_label)
        p.op('add',v('D'),result_vector,v('D'),length=(support_register,));p.call('STORE',result_vector,v('D'),length=(support_register,),store_mode=1)
        p.inc(25);p.branch('JUMP',label('certificate'))
    a.label(label('certificate'))
    certificate_block()
    a.label(label('success'))
    if residual_vector is not None:p.op('copy',residual_vector,v('R'),length=p.m)
    p.set(15,1);a.emit('RET')
