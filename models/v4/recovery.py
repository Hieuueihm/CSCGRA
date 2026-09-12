"""Eight recovery programs over explicit float or integer kernel backends.

This is a numerical design model, not a cycle model or an RTL implementation.
Float LS uses NumPy SVD; integer LS uses unregularized CGLS and checks the
normal residual AFTER narrowing coefficients to the stored data format.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from copy import deepcopy
from fractions import Fraction
from functools import cmp_to_key
import numpy as np

from models.v4.fixed import Arithmetic, Format, Profile

ALGORITHMS = ("MP", "OMP", "GOMP", "CoSaMP", "SP", "IHT", "HTP", "GP")


@dataclass(frozen=True)
class Policy:
    sparsity: int
    max_iterations: int = 64
    residual_atol: float = 1e-6
    step_size: float = 0.1
    group_size: int = 2
    ls_max_iterations: int = 128
    ls_normal_rtol: float = 1e-4
    sp_stop_on_non_decrease: bool = True


@dataclass
class Result:
    x: np.ndarray
    support: list[int]
    residual: np.ndarray
    status: str
    events: dict
    trace: list[dict] = field(default_factory=list)
    raw_x: list[int] | None = None
    solver_trace: list[dict] = field(default_factory=list)
    raw_x_format: dict | None = None


def rank(values, count, excluded=(), norms=None):
    """Stable magnitude ranking; normalized scores compare squared ratios."""
    excluded = set(excluded)
    indices = [i for i in range(len(values)) if i not in excluded]
    if norms is None:
        return sorted(indices, key=lambda i: (-abs(values[i]), i))[:count]
    def compare(i, j):
        left = values[i] * values[i] * norms[j]
        right = values[j] * values[j] * norms[i]
        return (-1 if left > right else 1 if left < right else
                -1 if i < j else 1 if i > j else 0)
    return sorted(indices, key=cmp_to_key(compare))[:count]


class FloatKernels:
    def __init__(self, matrix, measurement, policy):
        self.a, self.y, self.policy = matrix, measurement, policy
        self.events = {}
        self.norms = np.sum(matrix * matrix, axis=0)
        self.ls_steps = 0

    def zeros(self, n):
        return np.zeros(n)

    def mv(self, vector, transpose=False, support=None):
        a = self.a if support is None else self.a[:, support]
        return (a.T if transpose else a) @ vector

    def add(self, a, b):
        return a + b

    def sub(self, a, b):
        return a - b

    def scale(self, a, scalar):
        return a * scalar

    def scalar(self, value):
        return float(value)

    def dot(self, a, b):
        return float(a @ b)

    def ratio(self, n, d):
        if d == 0:
            raise ArithmeticError("zero_denominator")
        return n / d

    def store(self, value):
        return value.copy()

    def decode(self, value):
        return np.asarray(value, dtype=float)

    def done(self, r):
        return self.dot(r, r) <= self.policy.residual_atol ** 2

    def least_squares(self, support):
        self.ls_steps = 1
        if not support:
            return self.zeros(0)
        return np.linalg.lstsq(self.a[:, support], self.y, rcond=None)[0]


class IntegerKernels:
    def __init__(self, matrix, measurement, policy, profile):
        self.profile, self.policy = profile, policy
        self.arithmetic = ar = Arithmetic(profile)
        self.a = ar.quantize(matrix, profile.coefficient)
        yd = ar.quantize(measurement, profile.data)
        self.y = np.array([ar.rescale(int(x), profile.data.frac, profile.state)
                           for x in yd], dtype=object)
        self.events = ar.events
        self.norms = np.array([ar.dot_raw(col, col) for col in self.a.T], dtype=object)
        self.ls_steps = 0
        if any(x == 0 for x in self.norms):
            raise ValueError("dictionary column becomes zero after quantization")

    def zeros(self, n):
        return np.zeros(n, dtype=object)

    def mv(self, vector, transpose=False, support=None):
        a = self.a if support is None else self.a[:, support]
        return self.arithmetic.matvec(a, vector, self.profile.coefficient,
                                      self.profile.state, self.profile.state,
                                      transpose=transpose)

    def add(self, a, b):
        return np.array([self.arithmetic.add(int(x), int(y), self.profile.state)
                         for x, y in zip(a, b)], dtype=object)

    def sub(self, a, b):
        return np.array([self.arithmetic.sub(int(x), int(y), self.profile.state)
                         for x, y in zip(a, b)], dtype=object)

    def scale(self, a, scalar):
        fmt = self.profile.state
        return np.array([self.arithmetic.mul(int(x), int(scalar), fmt, fmt, fmt)
                         for x in a], dtype=object)

    def scalar(self, value):
        return int(self.arithmetic.quantize([value], self.profile.state)[0])

    def dot(self, a, b):
        return self.arithmetic.dot_raw(a, b)

    def ratio(self, n, d):
        return self.arithmetic.ratio(int(n), int(d), 0, self.profile.state)

    def store(self, value):
        p, ar = self.profile, self.arithmetic
        return np.array([ar.rescale(ar.rescale(int(v), p.state.frac, p.data),
                                    p.data.frac, p.state) for v in value], dtype=object)

    def decode(self, value):
        return self.arithmetic.decode(value, self.profile.state)

    def done(self, residual):
        limit = Fraction(str(self.policy.residual_atol)) * self.profile.state.scale
        return self.dot(residual, residual) * limit.denominator ** 2 <= limit.numerator ** 2

    def certificate(self, coefficients, support, rhs_energy):
        r = self.sub(self.y, self.mv(coefficients, support=support))
        normal = self.mv(r, transpose=True, support=support)
        energy = self.dot(normal, normal)
        tolerance = Fraction(str(self.policy.ls_normal_rtol))
        return energy * tolerance.denominator ** 2 <= rhs_energy * tolerance.numerator ** 2

    def least_squares(self, support):
        self.ls_steps = 0
        if not support:
            return self.zeros(0)
        x = self.zeros(len(support))
        r = self.y.copy()
        gradient = self.mv(r, transpose=True, support=support)
        direction = gradient.copy()
        gamma = self.dot(gradient, gradient)
        rhs_energy = gamma
        if self.certificate(x, support, rhs_energy):
            return x
        for iteration in range(self.policy.ls_max_iterations):
            projected = self.mv(direction, support=support)
            denominator = self.dot(projected, projected)
            if denominator <= 0 or gamma <= 0:
                break
            alpha = self.ratio(gamma, denominator)
            x = self.add(x, self.scale(direction, alpha))
            r = self.sub(r, self.scale(projected, alpha))
            candidate = self.store(x)
            self.ls_steps = iteration + 1
            if any(self.events.values()):
                raise ArithmeticError("numeric_fault")
            if self.certificate(candidate, support, rhs_energy):
                return candidate
            next_gradient = self.mv(r, transpose=True, support=support)
            next_gamma = self.dot(next_gradient, next_gradient)
            beta = self.ratio(next_gamma, gamma)
            direction = self.add(next_gradient, self.scale(direction, beta))
            gradient, gamma = next_gradient, next_gamma
        raise ArithmeticError("ls_not_converged")


def run(algorithm, matrix, measurement, policy, profile: Profile | None = None,
        *, ls_solver: str = "cgls", solution_format: Format | None = None,
        qr_max_refinements: int = 0):
    """Run the existing outer program with an explicitly selected integer LS.

    The default CGLS path is retained as reference. Float always uses SVD.
    LSQR and QR are separate numerical implementations, not RTL qualifications.
    QR is explicit for the five greedy programs that call restricted LS.
    """
    if ls_solver not in ("cgls", "lsqr", "qr"):
        raise ValueError("ls_solver must be cgls, lsqr or qr")
    if qr_max_refinements != 0 and ls_solver != "qr":
        raise ValueError("qr_max_refinements requires the QR backend")
    if ls_solver == "qr" and (profile is None or algorithm not in ("OMP", "GOMP", "CoSaMP", "SP", "HTP")):
        raise ValueError("QR requires a fixed profile and an LS-calling greedy program")
    if solution_format is not None and (profile is None or ls_solver not in ("lsqr", "qr")):
        raise ValueError("explicit solution_format requires the fixed LSQR backend or QR backend")
    if algorithm not in ALGORITHMS:
        raise ValueError(f"unknown algorithm: {algorithm}")
    a, y = np.asarray(matrix, dtype=float), np.asarray(measurement, dtype=float)
    if a.ndim != 2 or y.shape != (a.shape[0],) or not np.all(np.isfinite(a)) or not np.all(np.isfinite(y)):
        raise ValueError("finite A[M,N] and y[M] required")
    if np.any(np.linalg.norm(a, axis=0) == 0):
        raise ValueError("zero dictionary column")
    if not (0 < policy.sparsity <= a.shape[1]) or policy.max_iterations < 1 or policy.group_size < 1:
        raise ValueError("invalid sparsity/iteration/group policy")
    if not (0 <= policy.residual_atol and 0 < policy.step_size and 0 < policy.ls_normal_rtol < 1) or policy.ls_max_iterations < 1:
        raise ValueError("invalid numeric policy")
    if profile is None:
        b = FloatKernels(a, y, policy)
    elif ls_solver == "lsqr":
        from models.v4.lsqr import IntegerLSQRKernels
        b = IntegerLSQRKernels(a, y, policy, profile, solution_format=solution_format)
    elif ls_solver == "qr":
        from models.v4.qr import IntegerQRKernels
        b = IntegerQRKernels(a, y, policy, profile, solution_format=solution_format,
                             max_refinements=qr_max_refinements)
    else:
        b = IntegerKernels(a, y, policy, profile)
    x, support, r = b.zeros(a.shape[1]), [], b.y.copy()
    trace, status = [], "max_iterations"
    solver_trace = []

    def solve(indices):
        estimate = b.zeros(a.shape[1])
        try:
            estimate[indices] = b.least_squares(indices)
        finally:
            report = getattr(b, "last_ls_report", None)
            if report is not None:
                solver_trace.append({"support": list(indices), **deepcopy(report)})
        trace.append({"phase": "LS", "support": list(indices), "inner_iterations": b.ls_steps})
        return b.store(estimate)

    try:
        if any(b.events.values()):
            raise ArithmeticError("numeric_fault")
        if not b.done(r) and algorithm == "SP":
            initial_support = sorted(rank(b.mv(r, True), policy.sparsity))
            initial_x = solve(initial_support)
            initial_r = b.sub(b.y, b.mv(initial_x))
            if any(b.events.values()):
                raise ArithmeticError("numeric_fault")
            x, support, r = initial_x, initial_support, initial_r
            trace.append({"phase": "INITIALIZE", "support": support.copy()})
        limit = policy.max_iterations
        exhausted_status = "max_iterations"
        if algorithm == "GOMP":
            paper_limit = min(policy.sparsity, a.shape[0] // policy.group_size)
            limit = min(limit, paper_limit)
            if limit == paper_limit:
                exhausted_status = "paper_iteration_limit"
        for iteration in range(limit):
            if b.done(r):
                status = "residual_tolerance"
                break
            g = b.mv(r, True)
            new_support, new_x = support.copy(), x.copy()
            if algorithm in ("OMP", "GOMP"):
                count = policy.group_size if algorithm == "GOMP" else 1
                chosen = rank(g, count, support, b.norms if algorithm == "OMP" else None)
                if len(chosen) < count:
                    status = "no_new_atom"
                    break
                new_support += chosen
                new_x = solve(new_support)
            elif algorithm in ("CoSaMP", "SP"):
                count = 2 * policy.sparsity if algorithm == "CoSaMP" else policy.sparsity
                candidates = rank(g, count)
                union = sorted(set(support).union(candidates))
                estimate = solve(union)
                new_support = sorted(rank(estimate, policy.sparsity))
                new_x = b.zeros(len(x))
                new_x[new_support] = estimate[new_support]
                if algorithm == "SP":
                    new_x = solve(new_support)
                trace.append({"phase": "PRUNE", "support": new_support.copy(), "union": union})
            elif algorithm in ("IHT", "HTP"):
                candidate = b.add(x, b.scale(g, b.scalar(policy.step_size)))
                new_support = sorted(rank(candidate, policy.sparsity))
                new_x = b.zeros(len(x))
                new_x[new_support] = candidate[new_support]
                if algorithm == "HTP":
                    new_x = solve(new_support)
            else:
                chosen = rank(g, 1, norms=b.norms)[0]
                if chosen not in new_support:
                    new_support.append(chosen)
                if algorithm == "MP":
                    if profile is None:
                        alpha = b.ratio(g[chosen], b.norms[chosen])
                    else:
                        # Correlation is state F, norm-squared is coefficient 2F.
                        alpha = b.arithmetic.ratio(int(g[chosen]), int(b.norms[chosen]),
                            profile.state.frac - 2 * profile.coefficient.frac, profile.state)
                    new_x[chosen] = b.add(x[chosen:chosen+1], np.array([alpha]))[0]
                else:
                    direction = b.zeros(len(x))
                    direction[new_support] = g[new_support]
                    projected = b.mv(direction)
                    denominator = b.dot(projected, projected)
                    if denominator == 0:
                        status = "stationary"
                        break
                    alpha = b.ratio(b.dot(r, projected), denominator)
                    new_x = b.add(x, b.scale(direction, alpha))
            new_x = b.store(new_x)
            new_r = b.sub(b.y, b.mv(new_x))
            if any(b.events.values()):
                raise ArithmeticError("numeric_fault")
            if (algorithm == "SP" and policy.sp_stop_on_non_decrease
                    and b.dot(new_r, new_r) >= b.dot(r, r)):
                trace.append({"phase": "ROLLBACK", "iteration": iteration})
                status = "residual_not_decreased"
                break
            x, support, r = new_x, new_support, new_r
            trace.append({"phase": "COMMIT", "iteration": iteration, "support": support.copy(),
                          "residual_energy_raw": b.dot(r, r)})
        else:
            if b.done(r):
                status = "residual_tolerance"
            else:
                status = exhausted_status
    except ArithmeticError as error:
        status = str(error)
        trace.append({"phase": "FAULT", "reason": status})
    stored_format = None if profile is None else getattr(b, "solution_format", profile.data)
    raw = None if profile is None else [b.arithmetic.rescale(int(v), profile.state.frac, stored_format) for v in x]
    raw_format = None if stored_format is None else {"width": stored_format.width, "frac": stored_format.frac}
    return Result(b.decode(x), support, b.decode(r), status, dict(b.events), trace, raw, solver_trace, raw_format)
