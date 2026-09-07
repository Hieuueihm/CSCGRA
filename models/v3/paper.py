"""Paper-faithful floating-point references for the eight v3 algorithms.

The equations in this module are independent of fixed-point formats, PCG,
memory capacity and RTL scheduling.  Deterministic tie-breaking and a finite
iteration budget are harness policies, not changes to the cited algorithms.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable

import numpy as np


Array = np.ndarray


PAPER_SOURCES = {
    "OMP": "https://doi.org/10.1109/TIT.2007.909108",
    "CoSaMP": "https://doi.org/10.1016/j.acha.2008.07.002",
    "IHT": "https://doi.org/10.1016/j.acha.2009.04.002",
    "HTP": "https://doi.org/10.1137/100806278",
    "SP": "https://doi.org/10.1109/TIT.2009.2016006",
    "GP": "https://doi.org/10.1109/TSP.2007.916124",
    "GOMP": "https://doi.org/10.1109/TSP.2012.2218810",
    "MP": "https://doi.org/10.1109/78.258082",
}


@dataclass(frozen=True)
class Policy:
    sparsity: int
    max_iterations: int
    residual_atol: float = 0.0
    step_size: float = 1.0
    group_size: int = 2
    sp_stop_on_non_decrease: bool = True


@dataclass
class Phase:
    seq: int
    iteration: int
    name: str
    support: list[int] = field(default_factory=list)
    candidates: list[int] = field(default_factory=list)
    vectors: dict[str, list[float]] = field(default_factory=dict)
    scalars: dict[str, float | int | str | bool] = field(default_factory=dict)


@dataclass
class Trace:
    algorithm: str
    x: list[float]
    residual: list[float]
    support: list[int]
    phases: list[Phase]
    stop_reason: str


class Recorder:
    def __init__(self) -> None:
        self.phases: list[Phase] = []

    def emit(
        self,
        iteration: int,
        name: str,
        *,
        support: list[int] | tuple[int, ...] = (),
        candidates: list[int] | tuple[int, ...] = (),
        vectors: dict[str, Array] | None = None,
        scalars: dict[str, Any] | None = None,
    ) -> None:
        self.phases.append(Phase(
            seq=len(self.phases),
            iteration=iteration,
            name=name,
            support=[int(v) for v in support],
            candidates=[int(v) for v in candidates],
            vectors={k: [float(x) for x in v] for k, v in (vectors or {}).items()},
            scalars=dict(scalars or {}),
        ))


def _inputs(phi: Array, y: Array, policy: Policy) -> tuple[Array, Array]:
    phi = np.asarray(phi, dtype=np.float64)
    y = np.asarray(y, dtype=np.float64)
    if phi.ndim != 2 or y.ndim != 1 or phi.shape[0] != y.size:
        raise ValueError("expected Phi[M,N] and y[M]")
    if not (0 < policy.sparsity <= phi.shape[1]):
        raise ValueError("illegal sparsity")
    if policy.max_iterations <= 0:
        raise ValueError("max_iterations must be positive")
    if np.any(np.linalg.norm(phi, axis=0) == 0.0):
        raise ValueError("zero dictionary atom")
    return phi, y


def _rank(values: Array, count: int, exclude: set[int] | None = None) -> list[int]:
    exclude = exclude or set()
    indices = np.asarray([i for i in range(values.size) if i not in exclude], dtype=np.int64)
    if indices.size == 0 or count <= 0:
        return []
    order = np.lexsort((indices, -np.abs(values[indices])))
    return [int(i) for i in indices[order[:count]]]


def _normalized_proxy(phi: Array, residual: Array) -> Array:
    """Correlation used for MP-family atom selection.

    The cited MP/GP derivations use unit-norm atoms.  Dividing by column norm
    extends the same selection rule to the equal-but-not-unit Bernoulli columns
    used by v3 without changing their least-squares problem.
    """

    return (phi.T @ residual) / np.linalg.norm(phi, axis=0)


def _raw_proxy(phi: Array, residual: Array) -> Array:
    return phi.T @ residual


def _ls(phi: Array, y: Array, support: list[int]) -> tuple[Array, Array]:
    x = np.zeros(phi.shape[1], dtype=np.float64)
    if support:
        coeff, *_ = np.linalg.lstsq(phi[:, support], y, rcond=None)
        x[np.asarray(support)] = coeff
    residual = y - phi @ x
    return x, residual


def _residual_done(residual: Array, policy: Policy) -> bool:
    return bool(np.linalg.norm(residual) <= policy.residual_atol)


def _result(name: str, x: Array, residual: Array, support: list[int],
            recorder: Recorder, reason: str) -> Trace:
    return Trace(name, x.tolist(), residual.tolist(), list(support),
                 recorder.phases, reason)


def omp(phi: Array, y: Array, policy: Policy) -> Trace:
    phi, y = _inputs(phi, y, policy)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    reason = "max_iterations"
    for iteration in range(policy.max_iterations):
        proxy = _normalized_proxy(phi, residual)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        selected = _rank(proxy, 1, set(support))
        if not selected:
            reason = "no_new_atom"
            break
        support.append(selected[0])
        rec.emit(iteration, "SELECT", support=support, candidates=selected)
        x, residual = _ls(phi, y, support)
        rec.emit(iteration, "LS", support=support, vectors={"x": x})
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("OMP", x, residual, support, rec, reason)


def cosamp(phi: Array, y: Array, policy: Policy) -> Trace:
    """Needell--Tropp Algorithm 1; no post-prune debias LS."""

    phi, y = _inputs(phi, y, policy)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    reason = "max_iterations"
    for iteration in range(policy.max_iterations):
        proxy = _raw_proxy(phi, residual)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        candidates = _rank(proxy, min(2 * policy.sparsity, phi.shape[1]))
        rec.emit(iteration, "IDENTIFY", support=support, candidates=candidates)
        work = sorted(set(support).union(candidates))
        rec.emit(iteration, "MERGE", support=work)
        estimate, _ = _ls(phi, y, work)
        rec.emit(iteration, "LS", support=work, vectors={"estimate": estimate})
        support = sorted(_rank(estimate, policy.sparsity))
        x = np.zeros_like(estimate)
        x[support] = estimate[support]
        rec.emit(iteration, "PRUNE", support=support, vectors={"x": x})
        residual = y - phi @ x
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("CoSaMP", x, residual, support, rec, reason)


def iht(phi: Array, y: Array, policy: Policy) -> Trace:
    phi, y = _inputs(phi, y, policy)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    reason = "max_iterations"
    for iteration in range(policy.max_iterations):
        gradient = _raw_proxy(phi, residual)
        rec.emit(iteration, "PROXY", support=support, vectors={"gradient": gradient})
        tentative = x + policy.step_size * gradient
        rec.emit(iteration, "UPDATE", support=support, vectors={"tentative": tentative},
                 scalars={"step_size": policy.step_size})
        support = sorted(_rank(tentative, policy.sparsity))
        x_next = np.zeros_like(x)
        x_next[support] = tentative[support]
        x = x_next
        rec.emit(iteration, "PRUNE", support=support, vectors={"x": x})
        residual = y - phi @ x
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("IHT", x, residual, support, rec, reason)


def htp(phi: Array, y: Array, policy: Policy) -> Trace:
    phi, y = _inputs(phi, y, policy)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    reason = "max_iterations"
    for iteration in range(policy.max_iterations):
        gradient = _raw_proxy(phi, residual)
        rec.emit(iteration, "PROXY", support=support, vectors={"gradient": gradient})
        tentative = x + policy.step_size * gradient
        support = sorted(_rank(tentative, policy.sparsity))
        rec.emit(iteration, "SELECT", support=support,
                 vectors={"tentative": tentative},
                 scalars={"step_size": policy.step_size})
        x, residual = _ls(phi, y, support)
        rec.emit(iteration, "LS", support=support, vectors={"x": x})
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("HTP", x, residual, support, rec, reason)


def sp(phi: Array, y: Array, policy: Policy) -> Trace:
    """Dai--Milenkovic SP with explicit initialization and reject-on-rise."""

    phi, y = _inputs(phi, y, policy)
    rec = Recorder()
    proxy = _raw_proxy(phi, y)
    rec.emit(0, "INIT_PROXY", vectors={"proxy": proxy})
    support = sorted(_rank(proxy, policy.sparsity))
    rec.emit(0, "INIT_SELECT", support=support)
    x, residual = _ls(phi, y, support)
    rec.emit(0, "INIT_LS", support=support, vectors={"x": x})
    rec.emit(0, "INIT_RESIDUAL", support=support, vectors={"residual": residual},
             scalars={"norm2": float(np.linalg.norm(residual))})
    reason = "max_iterations"
    if _residual_done(residual, policy):
        return _result("SP", x, residual, support, rec, "residual_tolerance")
    for iteration in range(1, policy.max_iterations + 1):
        old_x, old_residual, old_support = x.copy(), residual.copy(), list(support)
        proxy = _raw_proxy(phi, residual)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        candidates = _rank(proxy, policy.sparsity)
        work = sorted(set(support).union(candidates))
        rec.emit(iteration, "MERGE", support=work, candidates=candidates)
        estimate, _ = _ls(phi, y, work)
        rec.emit(iteration, "LS_WORK", support=work, vectors={"estimate": estimate})
        support = sorted(_rank(estimate, policy.sparsity))
        rec.emit(iteration, "PRUNE", support=support)
        x, residual = _ls(phi, y, support)
        rec.emit(iteration, "LS_FINAL", support=support, vectors={"x": x})
        old_norm, new_norm = np.linalg.norm(old_residual), np.linalg.norm(residual)
        accepted = not policy.sp_stop_on_non_decrease or new_norm < old_norm
        rec.emit(iteration, "RESIDUAL_CHECK", support=support,
                 vectors={"residual": residual},
                 scalars={"old_norm2": float(old_norm), "new_norm2": float(new_norm),
                          "accepted": accepted})
        if not accepted:
            x, residual, support = old_x, old_residual, old_support
            reason = "residual_not_decreased"
            rec.emit(iteration, "ROLLBACK", support=support,
                     vectors={"x": x, "residual": residual})
            break
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("SP", x, residual, support, rec, reason)


def gomp(phi: Array, y: Array, policy: Policy) -> Trace:
    """Wang--Kwon--Shim gOMP; select L new atoms every iteration.

    The paper permits up to min(K, floor(M/L)) iterations, so support capacity
    is L*K in the worst case.  It does not trim the final group to force K.
    """

    phi, y = _inputs(phi, y, policy)
    if policy.group_size <= 0:
        raise ValueError("group_size must be positive")
    paper_limit = min(policy.sparsity, phi.shape[0] // policy.group_size)
    limit = min(policy.max_iterations, paper_limit)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    reason = "paper_iteration_limit" if limit == paper_limit else "max_iterations"
    for iteration in range(limit):
        proxy = _raw_proxy(phi, residual)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        selected = _rank(proxy, policy.group_size, set(support))
        if not selected:
            reason = "no_new_atom"
            break
        support = support + selected
        rec.emit(iteration, "SELECT_GROUP", support=support, candidates=selected)
        x, residual = _ls(phi, y, support)
        rec.emit(iteration, "LS", support=support, vectors={"x": x})
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("GOMP", x, residual, support, rec, reason)


def mp(phi: Array, y: Array, policy: Policy) -> Trace:
    phi, y = _inputs(phi, y, policy)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    norms_sq = np.sum(phi * phi, axis=0)
    reason = "max_iterations"
    for iteration in range(policy.max_iterations):
        raw = _raw_proxy(phi, residual)
        proxy = raw / np.sqrt(norms_sq)
        rec.emit(iteration, "PROXY", support=support, vectors={"proxy": proxy})
        selected = _rank(proxy, 1)[0]  # MP explicitly permits re-selection.
        alpha = raw[selected] / norms_sq[selected]
        x[selected] += alpha
        if selected not in support:
            support.append(selected)
        rec.emit(iteration, "UPDATE", support=support, candidates=[selected],
                 vectors={"x": x}, scalars={"alpha": float(alpha)})
        residual = residual - alpha * phi[:, selected]
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("MP", x, residual, support, rec, reason)


def gp(phi: Array, y: Array, policy: Policy) -> Trace:
    """Basic Gradient Pursuit from Blumensath--Davies section III-A."""

    phi, y = _inputs(phi, y, policy)
    rec, support = Recorder(), []
    x, residual = np.zeros(phi.shape[1]), y.copy()
    reason = "max_iterations"
    for iteration in range(policy.max_iterations):
        raw = _raw_proxy(phi, residual)
        selection_proxy = raw / np.linalg.norm(phi, axis=0)
        rec.emit(iteration, "PROXY", support=support,
                 vectors={"proxy": selection_proxy, "gradient": raw})
        selected = _rank(selection_proxy, 1)[0]  # GP permits re-selection.
        reselected = selected in support
        if not reselected:
            support.append(selected)
        rec.emit(iteration, "SELECT", support=support, candidates=[selected],
                 scalars={"reselected": reselected})
        direction = np.zeros(phi.shape[1])
        direction[support] = raw[support]
        projected = phi @ direction
        denominator = float(projected @ projected)
        alpha = float((residual @ projected) / denominator) if denominator else 0.0
        rec.emit(iteration, "DIRECTION", support=support,
                 vectors={"direction": direction, "projected": projected},
                 scalars={"alpha": alpha, "denominator": denominator})
        x = x + alpha * direction
        residual = residual - alpha * projected
        rec.emit(iteration, "UPDATE", support=support, vectors={"x": x})
        rec.emit(iteration, "RESIDUAL", support=support,
                 vectors={"residual": residual},
                 scalars={"norm2": float(np.linalg.norm(residual))})
        if _residual_done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result("GP", x, residual, support, rec, reason)


ALGORITHMS: dict[str, Callable[[Array, Array, Policy], Trace]] = {
    "OMP": omp,
    "CoSaMP": cosamp,
    "IHT": iht,
    "HTP": htp,
    "SP": sp,
    "GP": gp,
    "GOMP": gomp,
    "MP": mp,
}


def run(name: str, phi: Array, y: Array, policy: Policy) -> Trace:
    try:
        function = ALGORITHMS[name]
    except KeyError as exc:
        raise ValueError(f"unknown algorithm {name}") from exc
    return function(phi, y, policy)
