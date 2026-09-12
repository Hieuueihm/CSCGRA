"""Scoped study-model accelerator; VM acceleration is a separate local backend.

This context temporarily changes process-global methods and is not intended
for concurrent model execution from other threads. Nested calls and exceptions
restore exactly the methods present at entry. Production source is untouched.
"""
from contextlib import contextmanager
from models.v4.fixed import Arithmetic
from models.v4.recovery import IntegerKernels
from scripts.v4.k8_exact_integer_acceleration import dot,matvec
from verification.v4.exact_vm_gemv import BoundedGemv


class _KernelGemvCache:
    """Own one validated, immutable C18 matrix for a model-kernel lifetime."""
    def __init__(self,kernel):
        # IntegerKernels quantizes into its own object array; never trust its
        # caller matrix or retain a zero-copy caller view. Freeze that owned
        # matrix before capturing BoundedGemv's independent int64 copy.
        kernel.a.setflags(write=False)
        backend=BoundedGemv(kernel.arithmetic)
        prepared=backend.prepare(kernel.a)
        if prepared is None:raise ValueError('unsupported integer-kernel matrix')
        self.source,self.backend,self.prepared=kernel.a,backend,prepared

    def matvec(self,vector,transpose):
        return self.backend.prepared_matvec(self.prepared,vector,transpose)


def _accelerated_kernel_init(previous):
    def init(self,*args,**kwargs):
        previous(self,*args,**kwargs)
        try:self._study_gemv_cache=_KernelGemvCache(self)
        except (ValueError,TypeError,OverflowError):self._study_gemv_cache=None
    return init


def _accelerated_kernel_mv(previous):
    def mv(self,vector,transpose=False,support=None):
        cache=getattr(self,'_study_gemv_cache',None)
        # Restricted supports retain the unmodified model path. Proximal
        # methods use the complete frozen operator, which is the expensive
        # ADMM/FISTA/PDHG case accelerated here.
        # The cache applies only while the original owned, frozen quantized
        # matrix remains installed. A reassignment or a caller reopening it
        # for write invalidates this shortcut and delegates to the active
        # reference path, so stale coefficients cannot be used.
        if (cache is not None and support is None and cache.source is self.a
                and not self.a.flags.writeable):
            return cache.matvec(vector,transpose)
        return previous(self,vector,transpose=transpose,support=support)
    return mv


@contextmanager
def model_acceleration():
    previous=(Arithmetic.dot_raw,Arithmetic.matvec,IntegerKernels.__init__,IntegerKernels.mv)
    Arithmetic.dot_raw,Arithmetic.matvec=dot,matvec
    IntegerKernels.__init__=_accelerated_kernel_init(previous[2])
    IntegerKernels.mv=_accelerated_kernel_mv(previous[3])
    try:
        yield
    finally:
        Arithmetic.dot_raw,Arithmetic.matvec,IntegerKernels.__init__,IntegerKernels.mv=previous
