"""Bit-accurate v3 hardware model derived from :mod:`models.v3.paper`.

The model preserves each paper's macro-phase order while replacing arithmetic
with D18F14/S27F19/A62 fixed point and replacing exact least squares with a
matrix-free, measurement-domain restricted-refinement transaction.
Regularization defaults to zero because the cited algorithms specify ordinary
least squares; a nonzero lambda is a separately named semantic profile.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Callable, Sequence

import numpy as np

from models.v3.paper import PAPER_SOURCES, Policy


Array = np.ndarray


@dataclass(frozen=True)
class NumericProfile:
    data_w: int = 18
    data_f: int = 14
    solver_w: int = 27
    solver_f: int = 19
    acc_w: int = 62
    rounding: str = "nearest_ties_away"
    narrowing: str = "signed_saturating"


@dataclass(frozen=True)
class RefinementPolicy:
    profile: str = "strict_paper"
    max_iterations: int = 128
    strict_normal_residual_shift: int = 14
    balanced_normal_residual_shift: int = 8
    reliable_recompute_interval: int = 8
    cheap_certificate_guard_bits: int = 0
    lambda_q: int = 0
    quantization_floor_shift: int = 0


@dataclass
class Events:
    data_saturation: int = 0
    solver_saturation: int = 0
    acc_overflow: int = 0
    divide_by_zero: int = 0
    refinement_breakdown: int = 0


@dataclass
class Phase:
    seq: int
    iteration: int
    name: str
    support: list[int] = field(default_factory=list)
    candidates: list[int] = field(default_factory=list)
    vectors: dict[str, list[int]] = field(default_factory=dict)
    scalars: dict[str, int | str | bool] = field(default_factory=dict)
    events: dict[str, int] = field(default_factory=dict)


@dataclass
class Trace:
    algorithm: str
    x: list[int]
    residual: list[int]
    support: list[int]
    phases: list[Phase]
    stop_reason: str
    events: Events


class Arithmetic:
    def __init__(self, profile: NumericProfile, events: Events):
        self.p = profile
        self.events = events

    @staticmethod
    def round_div(num: int, den: int) -> int:
        if den == 0:
            raise ZeroDivisionError
        negative = (num < 0) ^ (den < 0)
        q = (abs(num) + abs(den) // 2) // abs(den)
        return -q if negative else q

    @staticmethod
    def round_shift(value: int, shift: int) -> int:
        if shift < 0:
            return value << -shift
        if shift == 0:
            return value
        rounded = (abs(value) + (1 << (shift - 1))) >> shift
        return -rounded if value < 0 else rounded

    def _sat(self, value: int, width: int, field_name: str) -> int:
        lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
        if value < lo or value > hi:
            setattr(self.events, field_name, getattr(self.events, field_name) + 1)
        return max(lo, min(hi, int(value)))

    def data(self, value: int) -> int:
        return self._sat(value, self.p.data_w, "data_saturation")

    def solver(self, value: int) -> int:
        return self._sat(value, self.p.solver_w, "solver_saturation")

    def acc(self, value: int) -> int:
        lo, hi = -(1 << (self.p.acc_w - 1)), (1 << (self.p.acc_w - 1)) - 1
        if value < lo or value > hi:
            self.events.acc_overflow += 1
        return max(lo, min(hi, int(value)))

    def quantize_data(self, value: float) -> int:
        scaled = int(np.floor(abs(value) * (1 << self.p.data_f) + 0.5))
        return self.data(-scaled if value < 0 else scaled)

    def data_to_solver(self, value: int) -> int:
        return self.solver(value << (self.p.solver_f - self.p.data_f))

    def solver_to_data(self, value: int) -> int:
        return self.data(self.round_shift(value, self.p.solver_f - self.p.data_f))

    def solver_mul(self, a: int, b: int) -> int:
        raw = self.acc(a * b)
        return self.solver(self.round_shift(raw, self.p.solver_f))

    def solver_div(self, num: int, den: int) -> int:
        if den == 0:
            self.events.divide_by_zero += 1
            return 0
        return self.solver(self.round_div(num << self.p.solver_f, den))

    @staticmethod
    def _wrap_signed(value: int, width: int) -> int:
        mask = (1 << width) - 1
        wrapped = value & mask
        return wrapped - (1 << width) if wrapped & (1 << (width - 1)) else wrapped

    @staticmethod
    def _clip_signed(value: int, width: int) -> tuple[int, bool]:
        low = -(1 << (width - 1))
        high = (1 << (width - 1)) - 1
        return max(low, min(high, value)), value < low or value > high

    def pe_execute(self, operation: str, operand_a: int, operand_b: int,
                   accumulator: int = 0, *, selected_predicate: bool = True,
                   phi_nonzero: bool = True,
                   phi_sign: bool = False) -> tuple[int, int, bool, bool, bool]:
        """Bit-exact M6 PE primitive model.

        Returns result, next accumulator, accumulator-write, comparison bit and
        saturation event. ADD/SUB and left SHIFT saturate to S27; right SHIFT
        is arithmetic. SATURATING_ADD/SUB update the L48 accumulator and then
        saturating-narrow the routed/RF result.
        """
        a = self._wrap_signed(operand_a, self.p.solver_w)
        b = self._wrap_signed(operand_b, self.p.solver_w)
        acc = self._wrap_signed(accumulator, 48)
        result = 0
        acc_next = acc
        acc_write = False
        comparison = False
        saturated = False

        if operation == "NOP":
            pass
        elif operation == "PASS":
            result = a
        elif operation == "ADD":
            result, saturated = self._clip_signed(a + b, self.p.solver_w)
        elif operation == "SUB":
            result, saturated = self._clip_signed(a - b, self.p.solver_w)
        elif operation == "ABS":
            result, saturated = self._clip_signed(abs(a), self.p.solver_w)
        elif operation == "MIN":
            result = min(a, b)
        elif operation == "MAX":
            result = max(a, b)
        elif operation == "COMPARE_EQ":
            comparison = a == b
            result = int(comparison)
        elif operation == "COMPARE_LT":
            comparison = a < b
            result = int(comparison)
        elif operation == "COMPARE_LE":
            comparison = a <= b
            result = int(comparison)
        elif operation == "SELECT":
            result = a if selected_predicate else b
        elif operation == "SHIFT":
            if b < 0:
                result = a >> (abs(b) & 31)
            else:
                result, saturated = self._clip_signed(
                    a << (b & 31), self.p.solver_w)
        elif operation == "BIT_AND":
            result = self._wrap_signed(a & b, self.p.solver_w)
        elif operation == "BIT_OR":
            result = self._wrap_signed(a | b, self.p.solver_w)
        elif operation == "BIT_XOR":
            result = self._wrap_signed(a ^ b, self.p.solver_w)
        elif operation == "PHI_ACCUMULATE":
            # Accumulator-only sign/zero MAC. Keeping the signed term in L48
            # avoids an artificial S27 narrowing between sign application and
            # accumulation; the S27 result port is intentionally zero.
            term = 0 if not phi_nonzero else (a if phi_sign else -a)
            acc_next, saturated = self._clip_signed(acc + term, 48)
            result = 0
            acc_write = True
        elif operation == "PHI_DATA_ACCUMULATE":
            narrowed, data_saturated = self._clip_signed(
                self.round_shift(a, self.p.solver_f - self.p.data_f),
                self.p.data_w)
            rescaled = narrowed << (self.p.solver_f - self.p.data_f)
            term = 0 if not phi_nonzero else (rescaled if phi_sign else -rescaled)
            acc_next, acc_saturated = self._clip_signed(acc + term, 48)
            result = 0
            acc_write = True
            saturated = data_saturated or acc_saturated
        elif operation == "ACCUMULATOR_READ":
            result, saturated = self._clip_signed(acc, self.p.solver_w)
        elif operation in {"SATURATING_ADD", "SATURATING_SUB"}:
            wide = operand_a + (operand_b if operation == "SATURATING_ADD" else -operand_b)
            acc_next, wide_sat = self._clip_signed(wide, 48)
            result, narrow_sat = self._clip_signed(acc_next, self.p.solver_w)
            acc_write = True
            saturated = wide_sat or narrow_sat
        elif operation == "PHI_SIGN_SCALE":
            if phi_nonzero:
                result, saturated = self._clip_signed(a if phi_sign else -a,
                                                      self.p.solver_w)
        elif operation == "ACCUMULATOR_CLEAR":
            acc_next = 0
            acc_write = True
        elif operation in {"PHI_ACCUMULATOR_CAPTURE", "PHI_RESIDUAL_CAPTURE"}:
            result = 0
        else:
            raise ValueError(f"unsupported M6 PE operation: {operation}")
        return result, acc_next, acc_write, comparison, saturated


class Recorder:
    def __init__(self, events: Events):
        self.phases: list[Phase] = []
        self.events = events

    def emit(
        self,
        iteration: int,
        name: str,
        *,
        support: Sequence[int] = (),
        candidates: Sequence[int] = (),
        vectors: dict[str, Sequence[int]] | None = None,
        scalars: dict[str, Any] | None = None,
    ) -> None:
        self.phases.append(Phase(
            seq=len(self.phases),
            iteration=iteration,
            name=name,
            support=[int(v) for v in support],
            candidates=[int(v) for v in candidates],
            vectors={k: [int(x) for x in v] for k, v in (vectors or {}).items()},
            scalars={k: (bool(v) if isinstance(v, (bool, np.bool_)) else int(v) if isinstance(v, (int, np.integer)) else str(v))
                     for k, v in (scalars or {}).items()},
            events=asdict(self.events),
        ))


def quantize_inputs(phi: Array, y: Array, arithmetic: Arithmetic) -> tuple[list[list[int]], list[int]]:
    p = np.asarray(phi, dtype=np.float64)
    v = np.asarray(y, dtype=np.float64)
    if p.ndim != 2 or v.ndim != 1 or p.shape[0] != v.size:
        raise ValueError("expected Phi[M,N] and y[M]")
    return (
        [[arithmetic.quantize_data(float(value)) for value in row] for row in p],
        [arithmetic.quantize_data(float(value)) for value in v],
    )


def _rank(values: Sequence[int], count: int, exclude: set[int] | None = None) -> list[int]:
    excluded = exclude or set()
    return sorted(
        (idx for idx in range(len(values)) if idx not in excluded),
        key=lambda idx: (-abs(int(values[idx])), idx),
    )[:max(0, count)]


def _normalized_rank(phi: list[list[int]], correlations: Sequence[int], count: int) -> list[int]:
    norms = [sum(int(row[col]) * int(row[col]) for row in phi)
             for col in range(len(phi[0]))]
    if len(set(norms)) != 1:
        raise ValueError("v3 hardware MP/GP requires equal-norm matrix columns")
    return _rank(correlations, count)


def _corr(phi: list[list[int]], residual: Sequence[int], a: Arithmetic) -> list[int]:
    result = []
    shift = 2 * a.p.data_f - a.p.solver_f
    for col in range(len(phi[0])):
        raw = a.acc(sum(int(phi[row][col]) * int(residual[row]) for row in range(len(phi))))
        result.append(a.solver(a.round_shift(raw, shift)))
    return result


def _matvec_data(phi: list[list[int]], x: Sequence[int], a: Arithmetic) -> list[int]:
    result = []
    for row in range(len(phi)):
        raw = a.acc(sum(int(phi[row][col]) * int(x[col]) for col in range(len(x))))
        result.append(a.data(a.round_shift(raw, a.p.data_f)))
    return result


def _residual(phi: list[list[int]], y: Sequence[int], x: Sequence[int], a: Arithmetic) -> list[int]:
    fitted = _matvec_data(phi, x, a)
    return [a.data(int(yi) - int(fi)) for yi, fi in zip(y, fitted)]


def _norm_sq(values: Sequence[int], a: Arithmetic) -> int:
    return a.acc(sum(int(v) * int(v) for v in values))


def _solver_dot(left: Sequence[int], right: Sequence[int], a: Arithmetic) -> int:
    return a.acc(sum(int(x) * int(y) for x, y in zip(left, right)))


def _solver_vec_mul(vector: Sequence[int], scalar: int, a: Arithmetic) -> list[int]:
    return [a.solver_mul(int(value), scalar) for value in vector]


def _restricted_forward(phi_s: list[list[int]], vector: Sequence[int],
                        a: Arithmetic) -> list[int]:
    return [a.solver(a.round_shift(
        a.acc(sum(int(v) * int(w) for v, w in zip(row, vector))), a.p.data_f
    )) for row in phi_s]


def _restricted_transpose(phi_s: list[list[int]], vector: Sequence[int],
                          a: Arithmetic) -> list[int]:
    return [a.solver(a.round_shift(a.acc(sum(
        int(phi_s[row][col]) * int(vector[row]) for row in range(len(phi_s))
    )), a.p.data_f)) for col in range(len(phi_s[0]))]


def _profile_budget(profile: str, algorithm: str, support_count: int) -> int:
    del support_count
    balanced = {"OMP": 3, "GOMP": 4, "HTP": 3, "CoSaMP": 5,
                "SP": 4}
    fast = {"OMP": 3, "GOMP": 3, "HTP": 10, "CoSaMP": 6, "SP": 7}
    if profile == "strict_paper":
        return 1 << 30
    if profile == "balanced_variant":
        return balanced.get(algorithm, 3)
    if profile == "fast_variant":
        return fast.get(algorithm, 1)
    raise ValueError(f"unknown refinement profile {profile}")


def _refinement_success(reason: str) -> bool:
    return reason in {"empty", "certificate_pass", "balanced_certificate_pass",
                      "fast_budget_commit"}


def _refinement_certificate_limit(
    gamma_reference: int,
    shift: int,
    support_count: int,
    measurement_count: int,
    solver_fractional_bits: int,
    data_fractional_bits: int = 14,
    quantization_floor_shift: int = 0,
) -> tuple[int, int, int]:
    relative_limit = (gamma_reference + (1 << (2 * shift)) - 1) >> (2 * shift)
    # A post-D18 residual cannot satisfy an arbitrarily small relative target
    # once narrowing noise dominates. One 32-row block keeps the original
    # 2^11 F38 energy allowance per active atom. Multi-block reductions add a
    # second rounding boundary, so they use 2^12 per atom plus a row-count
    # floor of 2^10 per measurement. M<=32 therefore remains bit-identical.
    per_atom_floor = 1 << (11 if measurement_count <= 32 else 12)
    base_quantization_floor = max(
        1 << 14,
        measurement_count * (1 << 10) if measurement_count > 32 else 0,
        support_count * per_atom_floor,
    )
    energy_scale_shift = 2 * ((solver_fractional_bits - 19) - (data_fractional_bits - 14)) - quantization_floor_shift
    quantization_floor = (
        base_quantization_floor << energy_scale_shift
        if energy_scale_shift >= 0
        else max(1, base_quantization_floor >> -energy_scale_shift)
    )
    return max(relative_limit, quantization_floor), relative_limit, quantization_floor


def _post_d18_refinement_state(
    phi: list[list[int]], y: Sequence[int], ordered: Sequence[int],
    x: Sequence[int], phi_s: list[list[int]], a: Arithmetic,
) -> tuple[list[int], list[int], list[int], list[int], int]:
    dense_data = [0] * len(phi[0])
    for index, value in zip(ordered, x):
        dense_data[index] = a.solver_to_data(value)
    residual_data = _residual(phi, y, dense_data, a)
    cert_r = [a.data_to_solver(value) for value in residual_data]
    cert_g = _restricted_transpose(phi_s, cert_r, a)
    cert_gamma = _solver_dot(cert_g, cert_g, a)
    return dense_data, residual_data, cert_r, cert_g, cert_gamma


def _restricted_refinement(
    phi: list[list[int]],
    y: Sequence[int],
    support: Sequence[int],
    a: Arithmetic,
    policy: RefinementPolicy,
    rec: Recorder,
    algorithm_iteration: int,
    algorithm: str,
    initial_x: Sequence[int] | None = None,
    initial_residual: Sequence[int] | None = None,
    captured_proxy: Sequence[int] | None = None,
) -> tuple[list[int], list[int], list[int], str]:
    ordered = list(dict.fromkeys(int(v) for v in support))
    n = len(phi[0])
    if not ordered:
        return [0] * n, list(y), [0] * n, "empty"
    phi_s = [[row[index] for index in ordered] for row in phi]
    dense_start = list(initial_x) if initial_x is not None else [0] * n
    x = [a.data_to_solver(int(dense_start[index])) for index in ordered]
    if initial_residual is None:
        dense_restricted = [0] * n
        for index, value in zip(ordered, x):
            dense_restricted[index] = a.solver_to_data(value)
        residual_data = _residual(phi, y, dense_restricted, a)
    else:
        residual_data = list(initial_residual)
    r = [a.data_to_solver(int(value)) for value in residual_data]
    proxy_reused = captured_proxy is not None
    g = ([int(captured_proxy[index]) for index in ordered]
         if captured_proxy is not None else _restricted_transpose(phi_s, r, a))
    if policy.lambda_q:
        g = [a.solver(gv - a.solver_mul(policy.lambda_q, xv))
             for gv, xv in zip(g, x)]
    p = list(g)
    gamma = _solver_dot(g, g, a)
    gamma_reference = max(gamma, 1)
    budget = min(policy.max_iterations, _profile_budget(policy.profile, algorithm, len(ordered)))
    rec.emit(algorithm_iteration, "REFINEMENT_BEGIN", support=ordered,
             vectors={"x": x, "r": r, "g": g, "p": p},
             scalars={"profile": policy.profile, "budget": budget,
                      "proxy_reused": proxy_reused})
    reason = "max_iterations"
    balanced_fallback = False
    if gamma == 0 and policy.max_iterations > 0:
        shift = (policy.balanced_normal_residual_shift
                 if policy.profile == "balanced_variant"
                 else policy.strict_normal_residual_shift)
        certificate_limit, relative_limit, quantization_floor = (
            _refinement_certificate_limit(
                gamma_reference, shift, len(ordered), len(phi),
                a.p.solver_f, a.p.data_f, policy.quantization_floor_shift))
        _, _, cert_r, cert_g, cert_gamma = _post_d18_refinement_state(
            phi, y, ordered, x, phi_s, a)
        passed = cert_gamma <= certificate_limit
        rec.emit(algorithm_iteration, "REFINEMENT_CERTIFICATE", support=ordered,
                 scalars={"refinement_iteration": -1,
                          "normal_residual_sq": cert_gamma,
                          "reference_sq": gamma_reference, "shift": shift,
                          "relative_limit": relative_limit,
                          "quantization_floor": quantization_floor,
                          "certificate_limit": certificate_limit,
                          "trigger_initial_zero_gamma": True,
                          "post_d18": True, "passed": passed})
        if passed:
            reason = ("balanced_certificate_pass"
                      if policy.profile == "balanced_variant"
                      else "certificate_pass")
        else:
            r, g, p = cert_r, cert_g, list(cert_g)
            gamma = cert_gamma
    for refinement_iteration in range(policy.max_iterations):
        if _refinement_success(reason):
            break
        d = _restricted_forward(phi_s, p, a)
        delta = _solver_dot(d, d, a)
        if policy.lambda_q:
            delta = a.acc(delta + a.round_shift(
                policy.lambda_q * _solver_dot(p, p, a), a.p.solver_f))
        if delta <= 0 or gamma <= 0:
            a.events.refinement_breakdown += 1
            reason = "breakdown"
            rec.emit(algorithm_iteration, "REFINEMENT_BREAKDOWN", support=ordered,
                     scalars={"refinement_iteration": refinement_iteration,
                              "delta": delta, "gamma": gamma})
            break
        alpha = a.solver_div(gamma, delta)
        x = [a.solver(xv + dv) for xv, dv in zip(x, _solver_vec_mul(p, alpha, a))]
        r = [a.solver(rv - dv) for rv, dv in zip(r, _solver_vec_mul(d, alpha, a))]
        g_new = _restricted_transpose(phi_s, r, a)
        if policy.lambda_q:
            g_new = [a.solver(gv - a.solver_mul(policy.lambda_q, xv))
                     for gv, xv in zip(g_new, x)]
        gamma_new = _solver_dot(g_new, g_new, a)

        step_number = refinement_iteration + 1
        reliable = (policy.reliable_recompute_interval > 0
                    and step_number % policy.reliable_recompute_interval == 0)
        balanced_boundary = (policy.profile == "balanced_variant"
                             and not balanced_fallback and step_number >= budget)
        fast_boundary = policy.profile == "fast_variant" and step_number >= budget
        strict_final = step_number >= policy.max_iterations
        shift = (policy.balanced_normal_residual_shift
                 if policy.profile == "balanced_variant" and not balanced_fallback
                 else policy.strict_normal_residual_shift)
        certificate_limit, relative_limit, quantization_floor = (
            _refinement_certificate_limit(
                gamma_reference, shift, len(ordered), len(phi),
                a.p.solver_f, a.p.data_f, policy.quantization_floor_shift))
        cheap_limit = certificate_limit << (2 * policy.cheap_certificate_guard_bits)
        cheap_candidate = gamma_new <= cheap_limit
        certificate_due = (cheap_candidate or reliable or balanced_boundary
                           or fast_boundary or strict_final)
        recurrence_update = not certificate_due
        rec.emit(algorithm_iteration, "REFINEMENT_STEP", support=ordered,
                 vectors={"x": x, "r": r, "g": g_new, "d": d},
                 scalars={"refinement_iteration": refinement_iteration,
                          "alpha": alpha, "gamma": gamma,
                          "gamma_new": gamma_new, "delta": delta,
                          "cheap_certificate_candidate": cheap_candidate,
                          "certificate_due": certificate_due,
                          "reliable_recompute": reliable,
                          "recurrence_update": recurrence_update,
                          "solver_transpose_computed": True})

        if certificate_due:
            _, _, cert_r, cert_g, cert_gamma = _post_d18_refinement_state(
                phi, y, ordered, x, phi_s, a)
            passed = cert_gamma <= certificate_limit
            rec.emit(algorithm_iteration, "REFINEMENT_CERTIFICATE", support=ordered,
                     scalars={"refinement_iteration": refinement_iteration,
                              "normal_residual_sq": cert_gamma,
                              "reference_sq": gamma_reference, "shift": shift,
                              "relative_limit": relative_limit,
                              "quantization_floor": quantization_floor,
                              "certificate_limit": certificate_limit,
                              "trigger_cheap_gamma": cheap_candidate,
                              "trigger_reliable_interval": reliable,
                              "trigger_profile_boundary": (balanced_boundary
                                                           or fast_boundary),
                              "trigger_final": strict_final,
                              "post_d18": True, "passed": passed})
            if fast_boundary:
                reason = "fast_budget_commit"
                break
            if passed:
                reason = ("balanced_certificate_pass"
                          if policy.profile == "balanced_variant"
                          and not balanced_fallback else "certificate_pass")
                break
            r, g, p = cert_r, cert_g, list(cert_g)
            gamma = cert_gamma
            restart_reason = "certificate_failed_restart"
            if balanced_boundary:
                balanced_fallback = True
                restart_reason = "balanced_fallback_to_strict"
            elif reliable:
                restart_reason = "reliable_residual_replacement"
            rec.emit(algorithm_iteration, "REFINEMENT_RESTART", support=ordered,
                     scalars={"refinement_iteration": refinement_iteration,
                              "reason": restart_reason})
            continue
        beta = a.solver_div(gamma_new, gamma)
        p = [a.solver(gv + pv) for gv, pv in zip(
            g_new, _solver_vec_mul(p, beta, a))]
        g, gamma = g_new, gamma_new
    dense_solver = [0] * n
    dense_data = [0] * n
    for index, value in zip(ordered, x):
        dense_solver[index] = value
        dense_data[index] = a.solver_to_data(value)
    residual = _residual(phi, y, dense_data, a)
    commit = _refinement_success(reason)
    rec.emit(algorithm_iteration, "REFINEMENT_COMMIT" if commit else "REFINEMENT_ROLLBACK",
             support=ordered,
             vectors={"x_solver": dense_solver, "x": dense_data,
                      "residual": residual}, scalars={"refinement_reason": reason})
    return dense_data, residual, dense_solver, reason


def _done(residual: Sequence[int], policy: Policy, a: Arithmetic) -> bool:
    if policy.residual_atol <= 0:
        return False
    threshold = a.quantize_data(policy.residual_atol)
    # Preserve the paper L2 threshold but do not demand sub-quantum energy from
    # a D18 vector: one raw-LSB squared per measurement is the narrowing floor.
    return _norm_sq(residual, a) <= max(threshold * threshold, len(residual))


def _result(name: str, x: Sequence[int], residual: Sequence[int], support: Sequence[int],
            rec: Recorder, reason: str, events: Events) -> Trace:
    return Trace(name, list(x), list(residual), list(support), rec.phases, reason, events)


def _setup(phi: Array, y: Array, profile: NumericProfile) -> tuple[list[list[int]], list[int], Arithmetic, Recorder, Events]:
    events = Events()
    arithmetic = Arithmetic(profile, events)
    phi_q, y_q = quantize_inputs(phi, y, arithmetic)
    return phi_q, y_q, arithmetic, Recorder(events), events


def omp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
        refinement: RefinementPolicy) -> Trace:
    p, v, a, rec, events = _setup(phi, y, profile)
    support, x, residual, reason = [], [0] * len(p[0]), list(v), "max_iterations"
    for iteration in range(policy.max_iterations):
        proxy = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        selected = _rank(proxy, 1, set(support))
        if not selected:
            reason = "no_new_atom"
            break
        proposed_support = support + [selected[0]]
        rec.emit(iteration, "SELECT", support=proposed_support, candidates=selected)
        candidate_x, candidate_residual, _, ls_reason = _restricted_refinement(
            p, v, proposed_support, a, refinement, rec, iteration, "OMP",
            initial_x=x, initial_residual=residual, captured_proxy=proxy)
        rec.emit(iteration, "LS", support=proposed_support, vectors={"x": candidate_x},
                 scalars={"ls_reason": ls_reason})
        rec.emit(iteration, "RESIDUAL", support=proposed_support, vectors={"residual": residual},
                 scalars={"ls_reason": ls_reason})
        if not _refinement_success(ls_reason):
            reason = "solver_" + ls_reason
            break
        support, x, residual = proposed_support, candidate_x, candidate_residual
        rec.phases[-1].vectors["residual"] = list(residual)
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("OMP", x, residual, support, rec, reason, events)


def cosamp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
           refinement: RefinementPolicy) -> Trace:
    p, v, a, rec, events = _setup(phi, y, profile)
    support, x, residual, reason = [], [0] * len(p[0]), list(v), "max_iterations"
    for iteration in range(policy.max_iterations):
        proxy = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        candidates = _rank(proxy, min(2 * policy.sparsity, len(proxy)))
        rec.emit(iteration, "IDENTIFY", support=support, candidates=candidates)
        work = sorted(set(support).union(candidates))
        rec.emit(iteration, "MERGE", support=work)
        _, _, estimate, ls_reason = _restricted_refinement(
            p, v, work, a, refinement, rec, iteration, "CoSaMP",
            initial_x=x, initial_residual=residual, captured_proxy=proxy)
        rec.emit(iteration, "LS", support=work, vectors={"estimate": estimate},
                 scalars={"ls_reason": ls_reason})
        if not _refinement_success(ls_reason):
            reason = "solver_" + ls_reason
            break
        support = sorted(_rank(estimate, policy.sparsity))
        x = [0] * len(estimate)
        for index in support:
            x[index] = a.solver_to_data(estimate[index])
        rec.emit(iteration, "PRUNE", support=support, vectors={"x": x})
        residual = _residual(p, v, x, a)
        rec.emit(iteration, "RESIDUAL", support=support, vectors={"residual": residual})
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("CoSaMP", x, residual, support, rec, reason, events)


def iht(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
        refinement: RefinementPolicy) -> Trace:
    del refinement
    p, v, a, rec, events = _setup(phi, y, profile)
    support, x, residual, reason = [], [0] * len(p[0]), list(v), "max_iterations"
    mu = a.solver(int(np.floor(abs(policy.step_size) * (1 << profile.solver_f) + 0.5)) *
                  (-1 if policy.step_size < 0 else 1))
    for iteration in range(policy.max_iterations):
        gradient = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"gradient": gradient})
        tentative = [a.solver(a.data_to_solver(xv) + a.solver_mul(mu, gv))
                     for xv, gv in zip(x, gradient)]
        rec.emit(iteration, "UPDATE", support=support, vectors={"tentative": tentative},
                 scalars={"step_size": mu})
        support = sorted(_rank(tentative, policy.sparsity))
        x = [a.solver_to_data(tentative[i]) if i in set(support) else 0
             for i in range(len(tentative))]
        rec.emit(iteration, "PRUNE", support=support, vectors={"x": x})
        residual = _residual(p, v, x, a)
        rec.emit(iteration, "RESIDUAL", support=support, vectors={"residual": residual})
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("IHT", x, residual, support, rec, reason, events)


def htp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
        refinement: RefinementPolicy) -> Trace:
    p, v, a, rec, events = _setup(phi, y, profile)
    support, x, residual, reason = [], [0] * len(p[0]), list(v), "max_iterations"
    mu = a.solver(int(np.floor(abs(policy.step_size) * (1 << profile.solver_f) + 0.5)) *
                  (-1 if policy.step_size < 0 else 1))
    for iteration in range(policy.max_iterations):
        gradient = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"gradient": gradient})
        tentative = [a.solver(a.data_to_solver(xv) + a.solver_mul(mu, gv))
                     for xv, gv in zip(x, gradient)]
        proposed_support = sorted(_rank(tentative, policy.sparsity))
        rec.emit(iteration, "SELECT", support=proposed_support, vectors={"tentative": tentative},
                 scalars={"step_size": mu})
        candidate_x, candidate_residual, _, ls_reason = _restricted_refinement(
            p, v, proposed_support, a, refinement, rec, iteration, "HTP")
        rec.emit(iteration, "LS", support=proposed_support, vectors={"x": candidate_x},
                 scalars={"ls_reason": ls_reason})
        rec.emit(iteration, "RESIDUAL", support=proposed_support, vectors={"residual": residual},
                 scalars={"ls_reason": ls_reason})
        if not _refinement_success(ls_reason):
            reason = "solver_" + ls_reason
            break
        support, x, residual = proposed_support, candidate_x, candidate_residual
        rec.phases[-1].vectors["residual"] = list(residual)
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("HTP", x, residual, support, rec, reason, events)


def sp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
       refinement: RefinementPolicy) -> Trace:
    p, v, a, rec, events = _setup(phi, y, profile)
    proxy = _corr(p, v, a)
    rec.emit(0, "INIT_PROXY", vectors={"proxy": proxy})
    support = sorted(_rank(proxy, policy.sparsity))
    rec.emit(0, "INIT_SELECT", support=support)
    x, residual = [0] * len(p[0]), list(v)
    candidate_x, candidate_residual, _, ls_reason = _restricted_refinement(
        p, v, support, a, refinement, rec, 0, "SP", captured_proxy=proxy)
    rec.emit(0, "INIT_LS", support=support, vectors={"x": candidate_x},
             scalars={"ls_reason": ls_reason})
    rec.emit(0, "INIT_RESIDUAL", support=support, vectors={"residual": residual},
             scalars={"ls_reason": ls_reason})
    reason = "max_iterations"
    if not _refinement_success(ls_reason):
        return _result("SP", x, residual, [], rec, "solver_" + ls_reason, events)
    x, residual = candidate_x, candidate_residual
    rec.phases[-1].vectors["residual"] = list(residual)
    for iteration in range(1, policy.max_iterations + 1):
        old_x, old_residual, old_support = list(x), list(residual), list(support)
        proxy = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        candidates = _rank(proxy, policy.sparsity)
        work = sorted(set(support).union(candidates))
        rec.emit(iteration, "MERGE", support=work, candidates=candidates)
        work_x, work_residual, estimate, ls_reason = _restricted_refinement(
            p, v, work, a, refinement, rec, iteration, "SP",
            initial_x=x, initial_residual=residual, captured_proxy=proxy)
        rec.emit(iteration, "LS_WORK", support=work, vectors={"estimate": estimate},
                 scalars={"ls_reason": ls_reason})
        if not _refinement_success(ls_reason):
            reason = "solver_" + ls_reason
            break
        proposed_support = sorted(_rank(estimate, policy.sparsity))
        rec.emit(iteration, "PRUNE", support=proposed_support)
        candidate_x, candidate_residual, _, ls_reason = _restricted_refinement(
            p, v, proposed_support, a, refinement, rec, iteration, "SP",
            initial_x=work_x)
        rec.emit(iteration, "LS_FINAL", support=proposed_support,
                 vectors={"x": candidate_x}, scalars={"ls_reason": ls_reason})
        accepted = (_norm_sq(candidate_residual, a) < _norm_sq(old_residual, a)
                    if _refinement_success(ls_reason) else False)
        rec.emit(iteration, "RESIDUAL_CHECK", support=proposed_support,
                 vectors={"residual": candidate_residual},
                 scalars={"accepted": accepted, "ls_reason": ls_reason})
        if not _refinement_success(ls_reason):
            reason = "solver_" + ls_reason
            break
        support, x, residual = proposed_support, candidate_x, candidate_residual
        if policy.sp_stop_on_non_decrease and not accepted:
            x, residual, support = old_x, old_residual, old_support
            reason = "residual_not_decreased"
            rec.emit(iteration, "ROLLBACK", support=support,
                     vectors={"x": x, "residual": residual})
            break
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("SP", x, residual, support, rec, reason, events)


def gomp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
         refinement: RefinementPolicy) -> Trace:
    p, v, a, rec, events = _setup(phi, y, profile)
    limit = min(policy.max_iterations, policy.sparsity, len(p) // policy.group_size)
    support, x, residual = [], [0] * len(p[0]), list(v)
    reason = "paper_iteration_limit" if limit == min(policy.sparsity, len(p) // policy.group_size) else "max_iterations"
    for iteration in range(limit):
        proxy = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        selected = _rank(proxy, policy.group_size, set(support))
        if not selected:
            reason = "no_new_atom"
            break
        proposed_support = support + selected
        rec.emit(iteration, "SELECT_GROUP", support=proposed_support, candidates=selected)
        candidate_x, candidate_residual, _, ls_reason = _restricted_refinement(
            p, v, proposed_support, a, refinement, rec, iteration, "GOMP",
            initial_x=x, initial_residual=residual, captured_proxy=proxy)
        rec.emit(iteration, "LS", support=proposed_support, vectors={"x": candidate_x},
                 scalars={"ls_reason": ls_reason})
        rec.emit(iteration, "RESIDUAL", support=proposed_support, vectors={"residual": residual},
                 scalars={"ls_reason": ls_reason})
        if not _refinement_success(ls_reason):
            reason = "solver_" + ls_reason
            break
        support, x, residual = proposed_support, candidate_x, candidate_residual
        rec.phases[-1].vectors["residual"] = list(residual)
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("GOMP", x, residual, support, rec, reason, events)


def mp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
       refinement: RefinementPolicy) -> Trace:
    del refinement
    p, v, a, rec, events = _setup(phi, y, profile)
    support, x, residual, reason = [], [0] * len(p[0]), list(v), "max_iterations"
    for iteration in range(policy.max_iterations):
        corr = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": corr})
        selected = _normalized_rank(p, corr, 1)[0]
        direction = [corr[index] if index == selected else 0
                     for index in range(len(corr))]
        projected = _restricted_forward(p, direction, a)
        numerator = _solver_dot(direction, direction, a)
        denominator = _solver_dot(projected, projected, a)
        step = a.solver_div(numerator, denominator)
        alpha = a.solver_mul(step, corr[selected])
        updated = a.solver(a.data_to_solver(x[selected]) + alpha)
        x[selected] = a.solver_to_data(updated)
        if selected not in support:
            support.append(selected)
        rec.emit(iteration, "UPDATE", support=support, candidates=[selected],
                 vectors={"x": x}, scalars={"alpha": alpha})
        residual = _residual(p, v, x, a)
        rec.emit(iteration, "RESIDUAL", support=support, vectors={"residual": residual})
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("MP", x, residual, support, rec, reason, events)


def gp(phi: Array, y: Array, policy: Policy, profile: NumericProfile,
       refinement: RefinementPolicy) -> Trace:
    del refinement
    p, v, a, rec, events = _setup(phi, y, profile)
    support, x, residual, reason = [], [0] * len(p[0]), list(v), "max_iterations"
    for iteration in range(policy.max_iterations):
        gradient = _corr(p, residual, a)
        rec.emit(iteration, "PROXY", support=support, vectors={"gradient": gradient})
        selected = _normalized_rank(p, gradient, 1)[0]
        reselected = selected in support
        if not reselected:
            support.append(selected)
        rec.emit(iteration, "SELECT", support=support, candidates=[selected],
                 scalars={"reselected": reselected})
        direction = [gradient[i] if i in set(support) else 0 for i in range(len(gradient))]
        projected = []
        for row in p:
            raw = a.acc(sum(int(row[col]) * int(direction[col]) for col in range(len(direction))))
            projected.append(a.solver(a.round_shift(raw, profile.data_f)))
        residual_solver = [a.data_to_solver(value) for value in residual]
        numerator = _solver_dot(residual_solver, projected, a)
        denominator = _solver_dot(projected, projected, a)
        alpha = a.solver_div(numerator, denominator)
        rec.emit(iteration, "DIRECTION", support=support,
                 vectors={"direction": direction, "projected": projected},
                 scalars={"alpha": alpha, "denominator": denominator})
        updated_solver = [a.solver(a.data_to_solver(xv) + a.solver_mul(alpha, dv))
                          for xv, dv in zip(x, direction)]
        x = [a.solver_to_data(value) for value in updated_solver]
        residual = _residual(p, v, x, a)
        rec.emit(iteration, "UPDATE", support=support, vectors={"x": x})
        rec.emit(iteration, "RESIDUAL", support=support, vectors={"residual": residual})
        if _done(residual, policy, a):
            reason = "residual_tolerance"
            break
    return _result("GP", x, residual, support, rec, reason, events)


ALGORITHMS: dict[str, Callable[[Array, Array, Policy, NumericProfile, RefinementPolicy], Trace]] = {
    "OMP": omp,
    "CoSaMP": cosamp,
    "IHT": iht,
    "HTP": htp,
    "SP": sp,
    "GP": gp,
    "GOMP": gomp,
    "MP": mp,
}


def run(name: str, phi: Array, y: Array, policy: Policy,
        profile: NumericProfile | None = None,
        refinement: RefinementPolicy | None = None) -> Trace:
    if name not in PAPER_SOURCES:
        raise ValueError(f"unknown algorithm {name}")
    return ALGORITHMS[name](phi, y, policy, profile or NumericProfile(),
                            refinement or RefinementPolicy())
