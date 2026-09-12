"""Optional VM-only C18*S27 int64 GEMV; no model class mutation.

Only signed C18F16 coefficients, S27F22 vectors/output and ACC64 enter the
fast path. At most1024 products contribute to an output: the sum of absolute
products is <=1024 * 2**17 * 2**26 = 2**53, so every serial prefix, subtree
and NumPy int64 total is exact. Unsupported input delegates to the original
method, preserving its errors and observable arithmetic event counters.
"""
from numbers import Integral
import numpy as np
from models.v4.fixed import Format


def signed_integers(values):
    array=np.asarray(values)
    if array.dtype.kind not in 'iu':
        if array.dtype.kind!='O' or any(isinstance(x,(bool,np.bool_)) or not isinstance(x,Integral) for x in array.flat):
            raise ValueError('raw integer array required')
    if array.dtype.kind=='u' and array.size and int(array.max())>=(1<<63):
        raise ValueError('unsigned value outside int64')
    return array.astype(np.int64)


class _PreparedC18:
    """Private ownership token for the validated, read-only matrix copy."""
    def __init__(self,data):
        self.data=data


class BoundedGemv:
    def __init__(self,arithmetic,stats=None):
        self.arithmetic=arithmetic
        # Capture the instance's original method; never patch Arithmetic.
        self.reference=arithmetic.matvec
        self.stats={} if stats is None else stats

    def prepare(self,matrix):
        """Capture a validated immutable C18 operator at a VM ownership boundary.

        The VM owns its quantized Phi and rebuilds B explicitly. It never writes
        either matrix in place. This method is not a cache keyed by address:
        every prepare captures fresh values; a new BUILD must prepare again.
        """
        try:
            if (self.arithmetic.profile.coefficient!=Format(18,16) or
                    self.arithmetic.profile.state!=Format(27,22) or
                    self.arithmetic.profile.accumulator_width!=64):
                return None
            data=signed_integers(matrix)
            if data.ndim!=2 or not all(1<=n<=1024 for n in data.shape):return None
            if int(data.min())<-(1<<17) or int(data.max())>=(1<<17):return None
        except (ValueError,TypeError,OverflowError):return None
        data.setflags(write=False)
        self.stats['prepared_operators']=self.stats.get('prepared_operators',0)+1
        return _PreparedC18(data)

    def prepared_matvec(self,operator,vector,transpose=False):
        """Use only a private matrix returned by prepare; validate fresh vector."""
        if not isinstance(operator,_PreparedC18):
            raise TypeError('prepared_matvec requires a validated private operator')
        operator=operator.data
        left=operator.T if transpose else operator
        try:
            right=signed_integers(vector)
            if right.ndim!=1 or len(right)!=left.shape[1]:raise ValueError('shape')
            if int(right.min())<-(1<<26) or int(right.max())>=(1<<26):raise ValueError('vector bound')
        except (ValueError,TypeError,OverflowError):
            self.stats['fallback_calls']=self.stats.get('fallback_calls',0)+1
            return self.reference(operator,vector,Format(18,16),Format(27,22),Format(27,22),transpose)
        self.stats['prepared_calls']=self.stats.get('prepared_calls',0)+1
        return self._finish(left,right,Format(18,16),Format(27,22),Format(27,22))

    def _finish(self,left,right,ma_fmt,vec_fmt,out):
        self.stats['fast_calls']=self.stats.get('fast_calls',0)+1
        self.stats['integer_products']=self.stats.get('integer_products',0)+left.size
        totals=left@right
        return np.array([self.arithmetic.rescale(self.arithmetic._accumulator_clip(int(v)),
                                                ma_fmt.frac+vec_fmt.frac,out)
                         for v in totals],dtype=object)

    def matvec(self,matrix,vector,ma_fmt,vec_fmt,out,transpose=False):
        try:
            if (ma_fmt!=Format(18,16) or vec_fmt!=Format(27,22) or out!=Format(27,22)
                    or self.arithmetic.profile.accumulator_width!=64):
                raise ValueError('unsupported arithmetic profile')
            if not isinstance(transpose,(bool,np.bool_)):
                raise ValueError('noncanonical transpose')
            left,right=signed_integers(matrix),signed_integers(vector)
            if left.ndim!=2 or right.ndim!=1:
                raise ValueError('shape')
            left=left.T if transpose else left
            if not 1<=left.shape[0]<=1024 or not 1<=left.shape[1]<=1024 or left.shape[1]!=len(right):
                raise ValueError('shape bound')
            if (int(left.min())<-(1<<17) or int(left.max())>=(1<<17)
                    or int(right.min())<-(1<<26) or int(right.max())>=(1<<26)):
                raise ValueError('raw storage bound')
        except (ValueError,TypeError,OverflowError):
            self.stats['fallback_calls']=self.stats.get('fallback_calls',0)+1
            return self.reference(matrix,vector,ma_fmt,vec_fmt,out,transpose)
        # Keep the original final ACC clipping, one rounding boundary and
        # per-output saturation events rather than implementing a new oracle.
        return self._finish(left,right,ma_fmt,vec_fmt,out)
