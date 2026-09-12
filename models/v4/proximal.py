"""Distinct LASSO programs sharing the v4 GEMV/vector/scalar kernels.

Objective: 0.5*||A*x-y||_2^2 + regularization*||x||_1.
These numerical exploration programs are not yet compiled to CGRA contexts.
"""
from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
import math
from numbers import Integral
import numpy as np

from models.v4.recovery import FloatKernels, IntegerKernels, Result

ALGORITHMS = ("FISTA", "ADMM", "PDHG")


@dataclass(frozen=True)
class Policy:
    regularization: float = 0.01
    max_iterations: int = 128
    step_size: float = 0.1
    pd_sigma: float = 1.0
    admm_rho: float = 1.0
    inner_max_iterations: int = 128
    inner_rtol: float = 1e-4


def soft_threshold(values, threshold):
    return np.array([max(v-threshold, 0) if v >= 0 else min(v+threshold, 0)
                     for v in values], dtype=values.dtype)


def _solve_shifted(b, rhs, rho, policy):
    """CG for (A.T*A + rho*I)x=rhs, with an explicit residual certificate.

    rho is ADMM's penalty parameter; this operator is never substituted for
    the unregularized least-squares call in OMP/CoSaMP/SP/HTP/gOMP.
    """
    def op(x):
        return b.add(b.mv(b.mv(x), True), b.scale(x, rho))
    def certified(x):
        residual = b.sub(rhs, op(x))
        energy = b.dot(residual, residual)
        if isinstance(b, FloatKernels):
            return energy <= policy.inner_rtol ** 2 * rhs_energy
        t = Fraction(str(policy.inner_rtol))
        return energy * t.denominator ** 2 <= rhs_energy * t.numerator ** 2
    x = b.zeros(len(rhs))
    r, p = rhs.copy(), rhs.copy()
    gamma = rhs_energy = b.dot(r, r)
    if certified(x):
        return x, 0
    for iteration in range(policy.inner_max_iterations):
        q = op(p)
        denominator = b.dot(p, q)
        if denominator <= 0 or gamma <= 0:
            break
        alpha = b.ratio(gamma, denominator)
        x = b.add(x, b.scale(p, alpha))
        r = b.sub(r, b.scale(q, alpha))
        if any(b.events.values()):
            raise ArithmeticError("numeric_fault")
        if certified(x):
            return x, iteration+1
        next_gamma = b.dot(r, r)
        p = b.add(r, b.scale(p, b.ratio(next_gamma, gamma)))
        gamma = next_gamma
    raise ArithmeticError("inner_not_converged")


def run(algorithm, matrix, measurement, policy, profile=None):
    if algorithm not in ALGORITHMS:
        raise ValueError(f"unknown proximal program: {algorithm}")
    a, y = np.asarray(matrix, dtype=float), np.asarray(measurement, dtype=float)
    if a.ndim != 2 or y.shape != (a.shape[0],) or min(a.shape) < 1:
        raise ValueError("A[M,N] and y[M] required")
    if not np.all(np.isfinite(a)) or not np.all(np.isfinite(y)):
        raise ValueError("finite input required")
    positive = (policy.step_size, policy.pd_sigma, policy.admm_rho, policy.inner_rtol)
    if not all(math.isfinite(v) and v > 0 for v in positive) or not math.isfinite(policy.regularization) or policy.regularization < 0:
        raise ValueError("invalid numeric policy")
    valid_counts = (
        isinstance(policy.max_iterations, Integral)
        and not isinstance(policy.max_iterations, (bool, np.bool_))
        and isinstance(policy.inner_max_iterations, Integral)
        and not isinstance(policy.inner_max_iterations, (bool, np.bool_))
    )
    if (not valid_counts or policy.max_iterations < 1
            or policy.inner_max_iterations < 1 or policy.inner_rtol >= 1):
        raise ValueError("invalid iteration/certificate policy")
    b = FloatKernels(a, y, policy) if profile is None else IntegerKernels(a, y, policy, profile)
    # Configuration validation on the matrix actually executed, after quantization.
    actual_a = a if profile is None else b.arithmetic.decode(b.a, profile.coefficient)
    lipschitz = float(np.linalg.norm(actual_a, 2) ** 2)
    def scalar_real(raw):
        return float(raw) if profile is None else float(raw) / profile.state.scale

    def configuration_scalar(value, name, positive=True):
        before = dict(b.events)
        raw = b.scalar(value)
        if any(b.events.get(key, 0) != count for key, count in before.items()):
            raise ValueError(f"{name} is not representable")
        if positive and scalar_real(raw) <= 0:
            raise ValueError(f"positive {name} quantized to zero")
        return raw

    tau = configuration_scalar(policy.step_size, "step_size") \
        if algorithm in ("FISTA", "PDHG") else None
    sigma = configuration_scalar(policy.pd_sigma, "pd_sigma") \
        if algorithm == "PDHG" else None
    rho = configuration_scalar(policy.admm_rho, "admm_rho") \
        if algorithm == "ADMM" else None
    if algorithm == "FISTA" and scalar_real(tau)*lipschitz > 1+1e-12:
        raise ValueError("FISTA requires step_size*||A||^2 <= 1")
    if algorithm == "PDHG" and scalar_real(tau)*scalar_real(sigma)*lipschitz >= 1:
        raise ValueError("PDHG requires tau*sigma*||A||^2 < 1")
    threshold_real = (policy.regularization / scalar_real(rho) if algorithm == "ADMM"
                      else scalar_real(tau) * policy.regularization)
    threshold = configuration_scalar(
        threshold_real, "regularization threshold",
        positive=policy.regularization > 0,
    )
    dual_prox = configuration_scalar(
        1/(1+scalar_real(sigma)), "dual prox scale"
    ) if algorithm == "PDHG" else None
    x, extrapolated = b.zeros(a.shape[1]), b.zeros(a.shape[1])
    dual = b.zeros(a.shape[0] if algorithm == "PDHG" else a.shape[1])
    momentum, status, trace = 1.0, "max_iterations", []
    rhs_base = b.mv(b.y, True) if algorithm == "ADMM" else None
    try:
        if any(b.events.values()):
            raise ArithmeticError("numeric_fault")
        for iteration in range(policy.max_iterations):
            old = x.copy()
            inner = 0
            if algorithm == "FISTA":
                gradient = b.mv(b.sub(b.mv(extrapolated), b.y), True)
                candidate = b.store(soft_threshold(b.sub(extrapolated, b.scale(gradient, tau)), threshold))
                next_momentum = (1+math.sqrt(1+4*momentum*momentum))/2
                # Input context coefficient; sqrt is a HOST preprocessing step.
                beta = b.scalar((momentum-1)/next_momentum)
                next_extrapolated = b.add(candidate, b.scale(b.sub(candidate, old), beta))
                momentum = next_momentum
            elif algorithm == "PDHG":
                numerator = b.add(dual, b.scale(b.sub(b.mv(extrapolated), b.y), sigma))
                next_dual = b.scale(numerator, dual_prox)
                candidate = b.store(soft_threshold(b.sub(x, b.scale(b.mv(next_dual, True), tau)),
                                                  threshold))
                next_extrapolated = b.add(candidate, b.sub(candidate, old))
            else:
                rhs = b.add(rhs_base, b.scale(b.sub(x, dual), rho))
                primal, inner = _solve_shifted(b, rhs, rho, policy)
                candidate = b.store(soft_threshold(b.add(primal, dual), threshold))
                next_dual = b.add(dual, b.sub(primal, candidate))
                next_extrapolated = candidate
            if any(b.events.values()):
                raise ArithmeticError("numeric_fault")
            x, extrapolated = candidate, next_extrapolated
            if algorithm != "FISTA":
                dual = next_dual
            trace.append({"phase": "COMMIT", "iteration": iteration,
                          "inner_iterations": inner})
    except ArithmeticError as error:
        status = str(error)
        trace.append({"phase": "FAULT", "reason": status})
    residual = b.sub(b.y, b.mv(x))
    if any(b.events.values()):
        status = "numeric_fault"
    raw = None if profile is None else [b.arithmetic.rescale(int(v), profile.state.frac, profile.data) for v in x]
    decoded = b.decode(x)
    support = [int(i) for i in np.flatnonzero(decoded)]
    return Result(decoded, support, b.decode(residual), status, dict(b.events), trace, raw)
