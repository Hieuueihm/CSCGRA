"""Candidate fixed-point Householder QR; independent of the LSQR recurrence.

Reflectors use v[0]=1, beta=-copysign(norm(x),x[0]), tau=(beta-x[0])/beta.
One scaled reciprocal normalizes the entire reflector tail. All arithmetic
rounding and range boundaries below are intended hardware service boundaries.
Floating diagnostics never select a candidate or alter its certificate.
"""
from fractions import Fraction
import math
import numpy as np

from models.v4.fixed import Format
from models.v4.recovery import IntegerKernels


class IntegerQRKernels(IntegerKernels):
    def __init__(self, matrix, measurement, policy, profile, solution_format=None, max_refinements=0):
        super().__init__(matrix, measurement, policy, profile)
        self.solution_format = Format(24,20) if solution_format is None else solution_format
        if (profile.state,profile.coefficient,profile.accumulator_width)!=(Format(27,22),Format(18,16),64):
            raise ValueError('QR candidate requires S27F22/C18F16/ACC64')
        if self.solution_format!=Format(24,20):
            raise ValueError('QR candidate storage requires X24F20')
        if not isinstance(max_refinements,int) or not 0<=max_refinements<=8:
            raise ValueError('bounded refinement count0..8 required')
        self.max_refinements=max_refinements
        self.last_ls_report={}
        self.last_factors=None
        self.last_candidate=None

    def _guard(self):
        if any(self.events.values()):raise ArithmeticError('numeric_fault')

    def _count(self,kind):
        counts=self.last_ls_report['counts'];counts[kind]=counts.get(kind,0)+1

    def _state(self,value):
        result=int(self.arithmetic.clip(int(value),self.profile.state));self._guard();return result

    def _round(self,value,shift):
        self._count('round')
        return self._state(self.arithmetic.round_shift(int(value),int(shift)))

    def _add(self,a,b):
        self._count('add');return self._state(int(a)+int(b))

    def _sub(self,a,b):
        self._count('sub');return self._state(int(a)-int(b))

    def _mul(self,a,b):
        self._count('mul');return self._round(int(a)*int(b),22)

    def _dot(self,a,b):
        self._count('dot');total=0
        for x,y in zip(a,b):
            total+=int(x)*int(y)
            self.last_ls_report['max_accumulator_magnitude']=max(self.last_ls_report['max_accumulator_magnitude'],abs(total))
            if not -(1<<63)<=total<(1<<63):
                self.events['accumulator_overflow']+=1;raise ArithmeticError('numeric_fault')
        return total

    def _sqrt(self,energy):
        self._count('sqrt')
        if energy<0:raise ArithmeticError('numeric_fault')
        q=math.isqrt(energy)
        return self._state(q+int(energy-q*q>q))

    def _div(self,a,b):
        self._count('div')
        if b==0:raise ArithmeticError('rank_deficient')
        result=int(self.arithmetic.ratio(int(a),int(b),0,self.profile.state))
        self._guard();return result

    def store(self,values):
        result=np.array([self.arithmetic.rescale(self.arithmetic.rescale(int(v),22,self.solution_format),20,self.profile.state)
                         for v in values],dtype=object)
        self._guard();return result

    def _apply(self,vector,tau,values):
        # Explicit DOT round22, scalar MUL round22, vector MUL round22, SUB.
        if tau==0:return list(values)
        coefficient=self._mul(tau,self._round(self._dot(vector,values),22))
        return [self._sub(value,self._mul(v,coefficient)) for v,value in zip(vector,values)]

    def _factor(self,matrix):
        rows,columns=matrix.shape
        factors=np.array(matrix,dtype=object,copy=True)
        reflectors=[]
        for column in range(columns):
            x=[int(v) for v in factors[column:,column]]
            tail_energy=self._dot(x[1:],x[1:])
            if tail_energy==0:
                beta=x[0];tau=0;vector=[1<<22]+[0]*(len(x)-1)
            else:
                norm=self._sqrt(self._dot(x,x));beta=-norm if x[0]>=0 else norm
                denominator=self._sub(x[0],beta)
                tau=self._div(self._sub(beta,x[0]),beta)
                exponent=abs(denominator).bit_length()
                reciprocal=self._div(1<<exponent,denominator)
                vector=[1<<22]+[self._round(v*reciprocal,exponent) for v in x[1:]]
            if beta==0:raise ArithmeticError('rank_deficient')
            reflectors.append((column,vector,tau))
            factors[column,column]=beta
            factors[column+1:,column]=0
            for target in range(column+1,columns):
                factors[column:,target]=self._apply(vector,tau,factors[column:,target])
            self.last_ls_report['reflectors']=column+1
        return factors,reflectors

    def _solve_factors(self,factors,reflectors,rhs):
        values=[int(v) for v in rhs]
        for column,vector,tau in reflectors:
            values[column:]=self._apply(vector,tau,values[column:])
        count=factors.shape[1];answer=[0]*count
        for row in range(count-1,-1,-1):
            dot=self._round(self._dot(factors[row,row+1:],answer[row+1:]),22)
            answer[row]=self._div(self._sub(values[row],dot),int(factors[row,row]))
        return np.asarray(answer,dtype=object)

    def _certificate(self,candidate,support,rhs_energy):
        self._count('certificate')
        residual=self.sub(self.y,self.mv(candidate,support=support))
        normal=self.mv(residual,transpose=True,support=support)
        self._guard();energy=self._dot(normal,normal)
        tolerance=Fraction(str(self.policy.ls_normal_rtol))
        passed=energy*tolerance.denominator**2<=rhs_energy*tolerance.numerator**2
        self.last_ls_report['certificate_history'].append(dict(
            normal_energy_raw=energy,rhs_energy_raw=rhs_energy,passed=bool(passed),
            stored_raw_x=[int(v)//4 for v in candidate]))
        return bool(passed),residual

    def least_squares(self,support):
        support=list(support);self.ls_steps=0;self.last_candidate=None;self.last_factors=None
        self.last_ls_report=dict(solver='HOUSEHOLDER_QR_CANDIDATE',status='running',counts={},
            reflectors=0,refinement_steps=0,max_accumulator_magnitude=0,certificate_history=[],
            numerical_contract='S27 reflectors/updates; X24 stored certificate; no LSQR fallback',
            max_refinements=self.max_refinements)
        try:
            self._guard()
            if len(set(support))!=len(support) or any(i<0 or i>=self.a.shape[1] for i in support):
                raise ValueError('invalid ordered support')
            if len(support)>min(96,self.a.shape[0]):raise ArithmeticError('rank_deficient')
            if not support:
                self.last_ls_report['status']='success';return self.zeros(0)
            matrix=np.array([[int(v)<<6 for v in row] for row in self.a[:,support]],dtype=object)
            self._guard()
            factors,reflectors=self._factor(matrix)
            self.last_factors=(factors,reflectors)
            normal_rhs=self.mv(self.y,transpose=True,support=support);self._guard()
            rhs_energy=self._dot(normal_rhs,normal_rhs)
            candidate=self.store(self._solve_factors(factors,reflectors,self.y))
            for refinement in range(self.max_refinements+1):
                self.last_candidate=candidate.copy()
                passed,residual=self._certificate(candidate,support,rhs_energy)
                if passed:
                    self.last_ls_report['status']='success';self.ls_steps=1+refinement
                    self.last_ls_report['steps']=self.ls_steps;return candidate
                if refinement<self.max_refinements:
                    correction=self._solve_factors(factors,reflectors,residual)
                    candidate=self.store([self._add(x,dx) for x,dx in zip(candidate,correction)])
                    self.last_ls_report['refinement_steps']=refinement+1
            raise ArithmeticError('qr_not_converged')
        except ArithmeticError as error:
            self.last_ls_report['status']=str(error);self.last_ls_report['steps']=self.ls_steps
            raise

    def diagnostics(self,support):
        """Read-only float64 diagnostics of the frozen integer factors/candidate."""
        if self.last_factors is None:return {'available':False}
        factors,reflectors=self.last_factors
        b=np.asarray(self.a[:,support],dtype=float)/2**16
        q=np.eye(len(b))
        for column,vector,tau in reflectors:
            v=np.asarray(vector,dtype=float)/2**22
            q[:,column:]-=(tau/2**22)*np.outer(q[:,column:]@v,v)
        r=np.asarray(factors,dtype=float)/2**22
        denom=np.linalg.norm(b)
        svd,_,rank,singular=np.linalg.lstsq(b,np.asarray(self.y,dtype=float)/2**22,rcond=None)
        output={'available':True,'factor_relative_residual':float(np.linalg.norm(q@r-b)/denom) if denom else 0.0,
                'orthogonality_frobenius':float(np.linalg.norm(q.T@q-np.eye(len(b)))),
                'rank':int(rank),'condition_number':float(singular[0]/singular[-1]) if singular[-1] else None}
        if self.last_candidate is not None:
            x=np.asarray(self.last_candidate,dtype=float)/2**22
            output['coefficient_relative_error']=float(np.linalg.norm(x-svd)/np.linalg.norm(svd)) if np.linalg.norm(svd) else float(np.linalg.norm(x))
        return output
