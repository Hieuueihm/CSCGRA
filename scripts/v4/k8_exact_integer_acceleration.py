"""Study-only guarded int64 reductions; original round/clip/events retained.

Uses a dynamic absolute-product bound <2^63 before NumPy reduction. Any shape,
type or bound outside this fast path falls back to the original model method.
No production model is edited and this is not an RTL cycle optimization.
"""
from contextlib import contextmanager
from numbers import Integral
import numpy as np
from models.v4.fixed import Arithmetic

ORIGINAL_DOT=Arithmetic.dot_raw
ORIGINAL_MATVEC=Arithmetic.matvec


def integers(value):
    obj=np.asarray(value)
    if obj.dtype.kind not in 'iu':
        if obj.dtype.kind!='O' or any(not isinstance(v,Integral) or isinstance(v,(bool,np.bool_)) for v in obj.flat):
            raise ValueError('not integer')
    if obj.dtype.kind=='u' and obj.size and int(obj.max())>=(1<<63):raise ValueError('uint64 outside signed range')
    return obj.astype(np.int64)


def bound(value):
    return max(abs(int(value.min(initial=0))),abs(int(value.max(initial=0))))


def dot(self,a,b):
    try:
        left,right=integers(a),integers(b)
        if left.ndim!=1 or right.shape!=left.shape or left.size*bound(left)*bound(right)>=(1<<63):raise ValueError('unsafe')
    except (ValueError,TypeError,OverflowError):return ORIGINAL_DOT(self,a,b)
    return self._accumulator_clip(int(left@right))


def matvec(self,matrix,vector,ma_fmt,vec_fmt,out,transpose=False):
    try:
        left,right=integers(matrix),integers(vector)
        if not isinstance(transpose,(bool,np.bool_)):raise ValueError('transpose')
        if left.ndim!=2 or right.ndim!=1:raise ValueError('shape')
        left=left.T if transpose else left
        if left.shape[1]!=len(right) or len(right)*bound(left)*bound(right)>=(1<<63):raise ValueError('unsafe')
    except (ValueError,TypeError,OverflowError):return ORIGINAL_MATVEC(self,matrix,vector,ma_fmt,vec_fmt,out,transpose)
    return np.array([self.rescale(self._accumulator_clip(int(v)),ma_fmt.frac+vec_fmt.frac,out) for v in left@right],dtype=object)


@contextmanager
def enabled():
    Arithmetic.dot_raw,Arithmetic.matvec=dot,matvec
    try:yield
    finally:Arithmetic.dot_raw,Arithmetic.matvec=ORIGINAL_DOT,ORIGINAL_MATVEC


def verify(profile):
    rng=np.random.default_rng(9082026);count=0
    for length in (0,1,7,32,64,256,1024):
        for _ in range(8):
            a=rng.integers(-(1<<26),1<<26,length,dtype=np.int64).astype(object)
            b=rng.integers(-(1<<26),1<<26,length,dtype=np.int64).astype(object)
            first,second=Arithmetic(profile),Arithmetic(profile)
            assert ORIGINAL_DOT(first,a,b)==dot(second,a,b) and first.events==second.events;count+=1
    for huge in (1<<62,1<<80):
        first,second=Arithmetic(profile),Arithmetic(profile)
        a=np.array([huge,-huge,huge],dtype=object);b=np.array([2,1,-1],dtype=object)
        assert ORIGINAL_DOT(first,a,b)==dot(second,a,b) and first.events==second.events;count+=1
    first,second=Arithmetic(profile),Arithmetic(profile)
    a=np.array([1<<63],dtype=np.uint64);b=np.array([1],dtype=np.uint64)
    assert ORIGINAL_DOT(first,a,b)==dot(second,a,b) and first.events==second.events;count+=1
    for shape in ((1,1),(5,7),(32,64),(64,256),(128,1024)):
        a=rng.integers(-(1<<17),1<<17,shape,dtype=np.int64).astype(object)
        for trans in (False,True):
            b=rng.integers(-(1<<26),1<<26,shape[0] if trans else shape[1],dtype=np.int64).astype(object)
            first,second=Arithmetic(profile),Arithmetic(profile)
            expected=ORIGINAL_MATVEC(first,a,b,profile.coefficient,profile.state,profile.state,trans)
            actual=matvec(second,a,b,profile.coefficient,profile.state,profile.state,trans)
            assert np.array_equal(expected,actual) and first.events==second.events;count+=1
    return count
