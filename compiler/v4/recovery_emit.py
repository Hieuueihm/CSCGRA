"""Complete non-LS candidate programs; emitted services still require RTL qualification."""
from dataclasses import asdict
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from compiler.v4.recovery_program import Assembler, ABI, KERNEL, decode, service_immediate
from compiler.v4.stream_program import encode_context, encode_descriptor
from compiler.v4.live_mapping import layout_descriptor
from models.v4.fixed import Arithmetic, Format, Profile

PROFILE = Profile(Format(18,14), Format(18,16), Format(27,22), 64)


def mapping_estimate(rows,cols,transpose=False,dense=False):
    """Current feeder schedules; approximate ticks, not measured program cycles."""
    outputs,reductions=(cols,rows) if transpose else (rows,cols)
    choices=[]
    for r4 in (False,True):
        width=8 if r4 else 32;groups=(outputs+width-1)//width;frames=0;ticks=0;passes=0
        for output in range(0,outputs,width):
            active=min(width,outputs-output)
            for red in range(0,reductions,32 if r4 else 1):
                for step in range(min(8,reductions-red) if r4 else 1):
                    count=1
                    if not dense and r4!=transpose:
                        count=min(4,(reductions-red-step+7)//8) if r4 else (active+7)//8
                    frames+=1;passes+=count;ticks+=3+3*count
        ticks+=groups*(32 if r4 else 0)
        choices.append(dict(r4=r4,frames=frames,active_phi_passes=passes if not dense else 0,
                            output_groups=groups,estimated_ticks=ticks))
    return choices

# Exact source-bound XSim measurements, not extrapolated buckets.  These are
# the only automatic entries: the fixed active10 target geometries with live Phi.
# Dense restricted-B width is held in a runtime register, so it stays on the
# explicitly-labelled legacy fallback unless a future measured branch contract
# makes that runtime selection observable and qualified.
CALIBRATED_LIVE_PHI_R4 = {
    (32, 64, False): False,
    (32, 64, True): True,
    (64, 256, False): False,
    (64, 256, True): True,
}

MAPPING_CALIBRATION = json.loads((Path(__file__).resolve().parents[2] /
                                 'config/v4_gemv_mapping_calibration.json').read_text())

def validate_mapping_calibration(profile=None, root=None):
    profile = MAPPING_CALIBRATION if profile is None else profile
    root = Path(__file__).resolve().parents[2] if root is None else Path(root)
    if profile.get('schema_version') != 1 or not profile.get('source_sha256'):
        raise ValueError('invalid GEMV mapping calibration schema')
    for name, expected in profile['source_sha256'].items():
        path = (root / name).resolve()
        if root.resolve() not in path.parents or not path.is_file():
            raise ValueError(f'missing calibration source: {name}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f'stale GEMV mapping calibration: {name}; recalibrate before auto selection')
    seen = set()
    for entry in profile['entries']:
        shape = entry['shape']
        layout_descriptor(shape['rows'], shape['columns'], shape['dense'])
        if type(shape['transpose']) is not bool:
            raise ValueError('invalid calibrated transpose')
        key = (shape['rows'], shape['columns'], shape['dense'], shape['transpose'])
        if key in seen or set(entry['cycles']) != {'R1', 'R4'}:
            raise ValueError('duplicate shape or invalid calibrated modes')
        seen.add(key)
        if any(type(value) is not int or value <= 0 for value in entry['cycles'].values()):
            raise ValueError('calibrated cycles must be positive integers')

def measured_mapping(rows, cols, transpose=False, dense=False):
    shape = dict(rows=rows, columns=cols, dense=bool(dense), transpose=bool(transpose))
    for entry in MAPPING_CALIBRATION['entries']:
        if entry['shape'] == shape:
            validate_mapping_calibration()
            return dict(entry['cycles'])
    return None


def mapping_selection(rows, cols, transpose=False, dense=False, r4=None, *, support_columns=None):
    """Choose an explicit override, an exact measured Phi entry, or a legacy fallback.

    ``mapping_estimate`` remains diagnostic only.  It is retained for unsupported
    and runtime-dynamic shapes to preserve prior behavior while recording that the
    choice was not made by a measured calibration table.
    """
    if r4 is not None and not isinstance(r4, bool):
        raise ValueError('r4 must be None (auto), False or True')
    if support_columns is not None and (not dense or type(support_columns) is not int or not 1 <= support_columns <= 96):
        raise ValueError('support_columns requires a known dense width in 1..96')
    effective_columns = support_columns if support_columns is not None else cols
    estimates = mapping_estimate(rows, effective_columns, transpose, dense)
    measured = (measured_mapping(rows, effective_columns, transpose, dense)
                if r4 is None and (not dense or support_columns is not None) else None)
    legacy = min(estimates, key=lambda item: item['estimated_ticks'])['r4']
    if r4 is not None:
        return dict(r4=r4, selection='explicit_ablation_override', estimates=estimates,
                    calibration=None, measured_command_cycles=measured)
    if not dense and measured is not None:
        return dict(r4=measured['R4'] < measured['R1'], selection='measured_exact_live_phi',
                    estimates=estimates,
                    calibration=dict(storage='live_phi', rows=rows, columns=cols,
                                     transpose=bool(transpose), exact_shape=True),
                    measured_command_cycles=measured)
    if dense and measured is not None:
        return dict(r4=measured['R4'] < measured['R1'], selection='measured_exact_restricted_dense',
                    estimates=estimates, measured_command_cycles=measured,
                    calibration=dict(storage='restricted_dense', rows=rows, columns=support_columns,
                                     transpose=bool(transpose), exact_shape=True))
    return dict(r4=legacy, selection='legacy_estimate_unqualified_fallback', estimates=estimates,
                measured_command_cycles=None,
                calibration=dict(reason=('runtime_dynamic_restricted_dense_width' if dense and support_columns is None
                                         else 'no_exact_measured_shape')))


class Program:
    def __init__(self, algorithm, matrix, policy, r4, operand_chains=False):
        if not isinstance(operand_chains, bool):
            raise ValueError('operand_chains must be boolean')
        self.a=Assembler();self.algorithm=algorithm;self.policy=policy;self.r4=r4;self.mappings=[]
        self.operand_chains=operand_chains;self.affine_emitted=False
        if r4 is not None and not isinstance(r4,bool):raise ValueError('r4 must be None (auto), False or True')
        matrix=np.asarray(matrix,dtype=float)
        if matrix.ndim!=2 or not np.all(np.isfinite(matrix)):raise ValueError('finite matrix required')
        self.m,self.n=matrix.shape
        if not 1<=self.m<=128 or not 1<=self.n<=1024:raise ValueError('unsupported matrix dimensions')
        self.ar=Arithmetic(PROFILE)
        raw=self.ar.quantize(matrix,PROFILE.coefficient)
        magnitudes={abs(int(v)) for v in raw.flat}
        if len(magnitudes)!=1 or 0 in magnitudes:raise ValueError('live Phi requires one nonzero column magnitude')
        self.scale=magnitudes.pop()
        self.operator_hash=hashlib.sha256(np.asarray(raw,dtype='<i4').tobytes()).hexdigest()
        if any(self.ar.events.values()):raise ValueError('matrix not representable')
        self.lipschitz=float(np.linalg.norm(self.ar.decode(raw,PROFILE.coefficient),2)**2)
        if not isinstance(policy.max_iterations,int) or not 1<=policy.max_iterations<=1024:raise ValueError('iteration limit1..1024')
        self.v={}
        for name,size in [('X',self.n),('R',self.m),('S',1 if algorithm in ('FISTA','PDHG','ADMM') else 96),('Y',self.m)]:self.vec(name,size)
        self.t={}
        for name,op,out,a,b,bind,mode in [('zero','MOV','EACH','ZERO','ZERO',0,1),('copy','MOV','EACH','A','B',0,1),
            ('add','ADD','EACH','A','B',0,1),('sub','SUB','EACH','A','B',0,1),('scale','MUL','EACH','A','B',0xffffffff,1),
            ('dot','MAC','SUM_ACC','A','B',0,1),('energy','MAC','SUM_ACC','A','A',0,1),('gemv','MAC','SUM_ACC','A','B',0,0)]:
            self.t[name]=self.a.template(name,op,out,src_a=a,src_b=b,bind_b=bind,mode=mode)
        self.t['scalar']=self.a.template('scalar','MOV',bind_a=0xffffffff)
        self.set(30,policy.max_iterations)
        self.op('zero','X',length=self.n);self.op('copy','R','Y',length=self.m)
    def vec(self,name,size=None):
        self.v[name]=self.a.vector(name,self.n if size is None else size);return name
    def set(self,r,value):self.a.emit('SET',dst_s=r,immediate=int(value))
    def scalar(self,value,positive=False):
        raw=int(self.ar.quantize(np.asarray([value]),PROFILE.state)[0])
        if any(self.ar.events.values()) or (positive and raw<=0):raise ValueError('configuration scalar not representable')
        return raw
    def call(self,op,dst,a='X',b='X',length=None,template='copy',out=0,flag=0,count=False,sa=0,sb=0,**imm):
        if length is None:length=self.n
        mode=3 if isinstance(length,tuple) else 2
        length=length[0] if isinstance(length,tuple) else length
        selected=False
        if op=='GEMV':
            decision=mapping_selection(self.m,self.n,bool(imm.get('transpose')),bool(imm.get('dense')),self.r4)
            selected=decision['r4']
            dense = bool(imm.get('dense'))
            bank_layout = layout_descriptor(self.m, None if dense else self.n, dense)
            if dense:
                bank_layout['support_length_register'] = imm.get('support_length_s')
            self.mappings.append(dict(pc=len(self.a.instructions),transpose=bool(imm.get('transpose')),selected_r4=selected,
                                      selection=decision['selection'],estimates=decision['estimates'],
                                      calibration=decision['calibration'], bank_layout=bank_layout,
                                      measured_command_cycles=decision['measured_command_cycles']))
        fields=dict(template=self.t[template],length=length,r4=int(selected),**imm)
        self.a.emit('KERNEL',kernel=KERNEL['operations'][op],dst_v=self.v[dst],a_v=self.v[a],b_v=self.v[b],
                    dst_s=out,flag_s=flag,target=int(count),a_s=sa,b_s=sb,length_mode=mode,immediate=service_immediate(**fields))
    def scalar_template(self,op,dst,left,right=0):
        if op not in ('MOV','ADD','SUB','MUL'):raise ValueError('unsupported scalar template')
        key='scalar_'+op.lower()
        if key not in self.t:self.t[key]=self.a.template(key,op,bind_a=1,bind_b=0 if op=='MOV' else 1,mode=1)
        self.call('SCALAR_TEMPLATE','X','X','X',length=1,template=key,out=dst,sa=left,sb=right)
    def op(self,name,dst,a='X',b='X',length=None,out=0,scalar=0):
        self.call('TEMPLATE',dst,a,b,length,name,out=out,sa=scalar if name=='scalar' else 0,sb=scalar if name=='scale' else 0)
    def energy(self,a,r,length=None):self.op('energy',a,a,length=length,out=r)
    def mv(self,dst,a,trans=False):self.call('GEMV',dst,a,length=self.m if trans else self.n,template='gemv',transpose=int(trans))
    def store(self,dst,a):self.call('STORE',dst,a,store_mode=2 if self.algorithm in ('FISTA','PDHG','ADMM') else 1)
    def scale_op(self,dst,a,r,length=None):self.op('scale',dst,a,length=length,scalar=r)
    def affine(self,dst,c,x,*,scalar=0,y=None,subtract=False,length=None):
        """Emit feature8 C +/- round22(X*Y) without publishing the product.

        ``y is None`` selects the canonical scalar-B shape; otherwise this
        emits the generic vector-B shape.  All legacy calls stay separate
        SCALE then ADD/SUB unless ``operand_chains`` was explicitly selected.
        """
        if not self.operand_chains:
            raise ValueError('ROUNDED_AFFINE requires operand_chains=True')
        if length is None:length=self.n
        if not isinstance(length,int) or not 1<=length<=1024:
            raise ValueError('ROUNDED_AFFINE length must be1..1024')
        scalar_mode=y is None
        if scalar_mode and not isinstance(scalar,int):
            raise ValueError('ROUNDED_AFFINE scalar register must be an integer')
        name='affine_'+('sub' if subtract else 'add')+('_scalar' if scalar_mode else '_vector')
        if name not in self.t:
            # The cascade contract uses an ordinary EACH template.  Its lower
            # half produces the rounded product and its upper half consumes C
            # plus or minus that product.  Scalar B binds only its low16
            # source lanes; vector B remains unbound.
            affine_descriptor=encode_descriptor(inc_a=1,inc_b=1,inc_dst=1,output_kind='EACH')
            mul=encode_context(op='MUL',mode=1,src_a='A',src_b='B')
            operation='SUB' if subtract else 'ADD'
            self.t[name]=len(self.a.templates)
            self.a.templates.append(dict(name=name,descriptor=affine_descriptor,
                bind_a=0,bind_b=0xffff if scalar_mode else 0,
                contexts=[mul]*16+[encode_context(op=operation,mode=1,src_a='A',src_b='B')]*16))
        for vector in (dst,c,x) + (() if scalar_mode else (y,)):
            if length>self.a.vectors[self.v[vector]]['capacity']:
                raise ValueError('ROUNDED_AFFINE length exceeds vector capacity')
        self.affine_emitted=True
        self.a.emit('KERNEL',kernel=KERNEL['operations']['ROUNDED_AFFINE'],
                    dst_v=self.v[dst],a_v=self.v[x],b_v=0 if scalar_mode else self.v[y],
                    dst_s=0,flag_s=0,target=0,a_s=0,b_s=scalar if scalar_mode else 0,
                    length_mode=2,immediate=service_immediate(template=self.t[name],length=length,
                    aux_v=self.v[c]))
    def threshold(self,dst,a):self.call('SOFT',dst,a,template='sub',sa=2)
    def div(self,dst,a,b,frac=0):self.a.emit('DIV',dst_s=dst,a_s=a,b_s=b,immediate=frac&255)
    def residual(self,dst,x,temp):self.mv(temp,x);self.op('sub',dst,'Y',temp,length=self.m)
    def branch(self,kind,label,**fields):self.a.branch(kind,label,**fields)
    def inc(self,r):self.a.emit('INC',dst_s=r,a_s=r)
    def halt(self,status):self.a.emit('HALT_STATUS',dst_v=self.v['X'],a_v=self.v['R'],b_v=self.v['S'],immediate=ABI['statuses'][status])
    def finish(self):
        p=self.a.finish();p.update(algorithm=self.algorithm,policy=asdict(self.policy),rows=self.m,cols=self.n,
            scale_raw=self.scale,operator_raw_c18_sha256=self.operator_hash,operator_hash_encoding='row-major little-endian signed32 raw C18; shape rows/cols above',
            r4_override=self.r4,mapping_decisions=self.mappings,
            mapping_model=('Exact XSim-calibrated live-Phi table for M32/N64 and M64/N256 orientations; '
                           'other shapes retain the legacy feeder active-frame/pass 3+3*passes plus32/group R4 estimate as an explicitly unqualified fallback. '
                           'Dynamic restricted dense support width is not inferred from full-N. '
                           'Per-command bank metadata describes the existing compact-Phi or paired diagonal-B layout, without repacking or changing RTL.'),
            measurement_vector=self.v['Y'],candidate_storage='D18F14' if self.algorithm in ('FISTA','PDHG','ADMM') else 'X24F20',
            scope='Complete non-LS candidate service program; numerical/RTL execution qualification is separate; no host iteration decisions')
        return p


def proximal(algorithm,matrix,policy,r4=None,operand_chains=False):
    p=Program(algorithm,matrix,policy,r4,operand_chains);a=p.a
    for name in ('E','D','C','NE','ND','T','G'):
        if algorithm=='ADMM' and name in ('E','NE','G'):continue
        if algorithm=='FISTA' and name in ('D','ND'):continue
        p.vec(name,p.m if name in ('D','ND') and algorithm=='PDHG' else None)
    p.vec('M',p.m)
    if algorithm!='ADMM':p.op('zero','E')
    if algorithm!='FISTA':p.op('zero','D',length=p.m if algorithm=='PDHG' else p.n)
    if algorithm in ('FISTA','PDHG'):
        tau=p.scalar(policy.step_size,True);p.set(1,tau)
        p.set(2,p.scalar(tau/2**22*policy.regularization,policy.regularization>0))
        if algorithm=='FISTA':
            if tau/2**22*p.lipschitz>1+1e-12:raise ValueError('unstable FISTA step')
            momentum=1.0
            for _ in range(policy.max_iterations):
                nxt=(1+math.sqrt(1+4*momentum*momentum))/2
                a.constant(p.scalar((momentum-1)/nxt));momentum=nxt
        else:
            sigma=p.scalar(policy.pd_sigma,True);p.set(3,sigma);p.set(4,p.scalar(1/(1+sigma/2**22),True))
            if tau/2**22*sigma/2**22*p.lipschitz>=1:raise ValueError('unstable PDHG steps')
    else:
        rho=p.scalar(policy.admm_rho,True);p.set(3,rho)
        p.set(2,p.scalar(policy.regularization/(rho/2**22),policy.regularization>0))
        if not 0<policy.inner_rtol<1 or not 1<=policy.inner_max_iterations<=1024:raise ValueError('invalid inner policy')
        p.set(31,policy.inner_max_iterations)
        for name in ('BASE','RHS','PRIMAL','CR','CP','CQ','CT','CU'):p.vec(name)
        p.mv('BASE','Y',True)
    a.label('outer')
    if algorithm=='FISTA':
        p.mv('M','E');p.op('sub','M','M','Y',length=p.m);p.mv('G','M',True)
        if operand_chains:p.affine('T','E','G',scalar=1,subtract=True)
        else:p.scale_op('T','G',1);p.op('sub','T','E','T')
        p.threshold('T','T');p.store('C','T')
        a.emit('CONST_LOAD',dst_s=5,a_s=26,immediate=0)
        p.op('sub','T','C','X')
        if operand_chains:p.affine('NE','C','T',scalar=5)
        else:p.scale_op('T','T',5);p.op('add','NE','C','T')
    elif algorithm=='PDHG':
        p.mv('M','E');p.op('sub','M','M','Y',length=p.m)
        if operand_chains:p.affine('M','D','M',scalar=3,length=p.m)
        else:p.scale_op('M','M',3,p.m);p.op('add','M','D','M',length=p.m)
        p.scale_op('ND','M',4,p.m)
        p.mv('G','ND',True)
        if operand_chains:p.affine('T','X','G',scalar=1,subtract=True)
        else:p.scale_op('T','G',1);p.op('sub','T','X','T')
        p.threshold('T','T');p.store('C','T')
        p.op('sub','T','C','X');p.op('add','NE','C','T')
    else:
        p.op('sub','T','X','D');p.scale_op('T','T',3);p.op('add','RHS','BASE','T')
        p.branch('CALL','cg');p.op('add','T','PRIMAL','D');p.threshold('T','T');p.store('C','T')
        p.op('sub','T','PRIMAL','C');p.op('add','ND','D','T')
    p.op('copy','X','C')
    if algorithm!='ADMM':p.op('copy','E','NE')
    if algorithm!='FISTA':p.op('copy','D','ND',length=p.m if algorithm=='PDHG' else p.n)
    p.inc(26);p.branch('BR_GE','finished',a_s=26,b_s=30);p.branch('JUMP','outer')
    a.label('finished');p.residual('R','X','M');p.halt('MAX_ITERATIONS')
    if algorithm=='ADMM':
        tolerance=Fraction(str(policy.inner_rtol));cn=a.constant(tolerance.denominator**2);cd=a.constant(tolerance.numerator**2)
        def operator(dst,src):
            p.mv('M',src);p.mv('CU','M',True);p.scale_op('CT',src,3);p.op('add',dst,'CU','CT')
        def certificate():
            operator('CQ','PRIMAL');p.op('sub','CT','RHS','CQ');p.energy('CT',14)
            a.emit('CERT',dst_s=15,a_s=14,b_s=10,immediate=cn|(cd<<10))
            p.branch('BR_NONZERO','cg_done',a_s=15)
        a.label('cg');p.set(25,0);p.op('zero','PRIMAL');p.op('copy','CR','RHS');p.op('copy','CP','RHS')
        p.energy('CR',10);a.emit('MOV',dst_s=11,a_s=10);certificate()
        a.label('cg_loop');operator('CQ','CP');p.op('dot','CP','CP','CQ',out=12)
        p.branch('BR_COMPARE','cg_fail',a_s=12,b_s=0,immediate=ABI['comparisons']['LE'])
        p.branch('BR_COMPARE','cg_fail',a_s=11,b_s=0,immediate=ABI['comparisons']['LE'])
        p.div(13,11,12);p.scale_op('CT','CP',13);p.op('add','PRIMAL','PRIMAL','CT')
        p.scale_op('CT','CQ',13);p.op('sub','CR','CR','CT');p.inc(25);certificate()
        p.energy('CR',14);p.div(13,14,11);p.scale_op('CT','CP',13);p.op('add','CP','CR','CT');a.emit('MOV',dst_s=11,a_s=14)
        p.branch('BR_GE','cg_fail',a_s=25,b_s=31);p.branch('JUMP','cg_loop')
        a.label('cg_done');a.emit('RET')
        a.label('cg_fail');p.residual('R','X','M');p.halt('INNER_NOT_CONVERGED')
    return p.finish()


def greedy(algorithm,matrix,policy,r4=None,sparse_forward=False,operand_chains=False):
    p=Program(algorithm,matrix,policy,r4,operand_chains);a=p.a
    if not 1<=policy.sparsity<=min(p.n,96) or policy.residual_atol<0:raise ValueError('invalid greedy policy')
    sparse_bound=min(p.n,policy.sparsity if algorithm=='IHT' else policy.max_iterations)
    if sparse_forward and sparse_bound>min(p.m,96):
        raise ValueError('sparse_forward policy can exceed restricted B support min(M,96)')
    for name in ('G','C','T','D'):p.vec(name)
    for name in ('NR','M'):p.vec(name,p.m)
    p.vec('NS',96);p.vec('CH',1);p.vec('ONE',1)
    if sparse_forward:p.vec('PACKED',96)
    sparse_calls=0
    def restricted_forward(dst,src,build):
        nonlocal sparse_calls
        label=f'sparse_{sparse_calls}';sparse_calls+=1
        p.branch('BR_ZERO',label+'_empty',a_s=28)
        if build:a.emit('BUILD_B',a_v=p.v['NS'],a_s=28)
        p.call('GATHER','PACKED',src,support_v=p.v['NS'],support_length_s=28)
        p.call('GEMV',dst,'PACKED',length=(28,),template='gemv',dense=1,support_length_s=28)
        p.mappings[-1]['dynamic_columns_register']=28
        p.mappings[-1]['estimate_scope']='Mapping selection uses conservative full-N cost; measured BUILD/GATHER/GEMV costs qualify the variant'
        p.branch('JUMP',label+'_done')
        a.label(label+'_empty');p.op('zero',dst,length=p.m)
        a.label(label+'_done')
    p.set(7,1);p.set(16,96);p.set(17,policy.sparsity)
    if algorithm=='IHT':p.set(18,p.scalar(policy.step_size,True))
    # For uniform Phi every column has precisely this C18F16 energy.
    p.set(19,p.m*p.scale*p.scale)
    tol=Fraction(str(policy.residual_atol))*2**22
    cn=a.constant(tol.denominator**2);cd=a.constant(tol.numerator**2);p.set(20,1)
    a.label('outer');p.energy('R',9,p.m);a.emit('CERT',dst_s=10,a_s=9,b_s=20,immediate=cn|(cd<<10))
    p.branch('BR_NONZERO','residual_done',a_s=10);p.branch('BR_GE','max_done',a_s=26,b_s=30)
    p.mv('G','R',True)
    if algorithm=='IHT':
        if operand_chains:p.affine('T','X','G',scalar=18)
        else:p.scale_op('T','G',18);p.op('add','T','X','T')
        p.call('TOPK','NS','T',k_s=17,flags=2,flag=28,count=True)
        p.call('APPLY_SUPPORT','C','T',support_v=p.v['NS'],support_length_s=28)
    else:
        p.call('TOPK','CH','G',k_s=7,flag=8,count=True)
        p.call('UNION','NS',k_s=16,support_v=p.v['S'],support_length_s=29,aux_v=p.v['CH'],aux_length_s=8,flags=1,flag=28,count=True)
        if algorithm=='MP':
            p.call('PICK','CH','CH',length=1,out=8)
            p.call('PICK','G','G',index_s=8,out=9)
            p.div(9,9,19,-10);p.op('scalar','ONE',length=1,scalar=9)
            p.call('SCATTER','D','ONE',support_v=p.v['CH'],support_length_s=7)
            p.op('add','C','X','D')
        else:
            p.call('APPLY_SUPPORT','D','G',support_v=p.v['NS'],support_length_s=28)
            if sparse_forward:restricted_forward('M','D',True)
            else:p.mv('M','D')
            p.energy('M',10,p.m);p.branch('BR_ZERO','stationary',a_s=10)
            p.op('dot','R','R','M',length=p.m,out=9);p.div(9,9,10)
            if operand_chains:p.affine('C','X','D',scalar=9)
            else:p.scale_op('T','D',9);p.op('add','C','X','T')
    p.store('C','C')
    if sparse_forward:
        restricted_forward('M','C',algorithm!='GP')
        p.op('sub','NR','Y','M',length=p.m)
    else:p.residual('NR','C','M')
    p.op('copy','X','C');p.op('copy','R','NR',length=p.m);p.op('copy','S','NS',length=(28,))
    a.emit('MOV',dst_s=29,a_s=28);p.inc(26);p.branch('JUMP','outer')
    for label,status in [('residual_done','RESIDUAL_TOLERANCE'),('max_done','MAX_ITERATIONS'),('stationary','STATIONARY')]:
        a.label(label);p.halt(status)
    package=p.finish()
    package.update(sparse_forward=bool(sparse_forward),
        sparse_forward_policy='BUILD ordered NS, GATHER coefficients, dense B forward; GP reuses its projected-gradient B; empty support yields zero' if sparse_forward else 'full Phi forward baseline')
    return package


def compile_recovery(algorithm,matrix,policy,*,r4=None,sparse_forward=False,operand_chains=False):
    if not isinstance(sparse_forward,bool):raise ValueError('sparse_forward must be boolean')
    if not isinstance(operand_chains,bool):raise ValueError('operand_chains must be boolean')
    if sparse_forward and algorithm not in ('MP','GP','IHT'):raise ValueError('sparse_forward is available only for MP/GP/IHT')
    if algorithm in ('FISTA','PDHG','ADMM'):package=proximal(algorithm,matrix,policy,r4,operand_chains)
    elif algorithm in ('MP','GP','IHT'):package=greedy(algorithm,matrix,policy,r4,sparse_forward,operand_chains)
    elif algorithm in ('OMP','GOMP','CoSaMP','SP','HTP'):
        raise ValueError('QR factor-transfer subroutine binding is not yet available; no LSQR fallback')
    else:raise ValueError('unknown recovery algorithm')
    emitted=any(decode(word)['kind']==ABI['kinds']['KERNEL'] and decode(word)['kernel']==KERNEL['operations']['ROUNDED_AFFINE']
                for word in package['program'])
    package.update(operand_chains=operand_chains,operand_chains_emitted=emitted,
                   operand_chain_scope=('ROUNDED_AFFINE feature8 replaces only selected non-QR SCALE then ADD/SUB pairs' if emitted else 'requested but no affine site is emitted for this algorithm' if operand_chains else 'disabled; legacy SCALE and ADD/SUB program image retained'),
                   required_kernel_revision=8 if emitted else 1,
                   required_kernel_features=['ROUNDED_AFFINE'] if emitted else [])
    return package
