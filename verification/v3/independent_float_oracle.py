"""Independent NumPy oracle for the eight v3 floating-point algorithms.

This module intentionally does not import ``models.v3.paper``. It provides a
second implementation used only to audit the authoritative floating-point
golden before fixed-point or RTL comparisons are allowed to run.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np


Array = np.ndarray


@dataclass(frozen=True)
class Result:
    x: Array
    residual: Array
    support: tuple[int, ...]
    stop_reason: str


def _inputs(phi: Any, y: Any, policy: Any) -> tuple[Array, Array]:
    matrix = np.asarray(phi, dtype=np.float64)
    measurement = np.asarray(y, dtype=np.float64)
    if matrix.ndim != 2 or measurement.shape != (matrix.shape[0],):
        raise ValueError("expected Phi[M,N] and y[M]")
    if not (0 < int(policy.sparsity) <= matrix.shape[1]):
        raise ValueError("illegal sparsity")
    if int(policy.max_iterations) <= 0:
        raise ValueError("max_iterations must be positive")
    if np.any(np.linalg.norm(matrix, axis=0) == 0.0):
        raise ValueError("zero dictionary atom")
    return matrix, measurement


def _rank(values: Array, count: int, excluded: set[int] | None = None) -> list[int]:
    excluded = excluded or set()
    indices = np.asarray(
        [index for index in range(values.size) if index not in excluded],
        dtype=np.int64,
    )
    order = np.lexsort((indices, -np.abs(values[indices])))
    return [int(index) for index in indices[order[:max(0, count)]]]


def _least_squares(phi: Array, y: Array, support: list[int]) -> tuple[Array, Array]:
    estimate = np.zeros(phi.shape[1], dtype=np.float64)
    if support:
        coefficients = np.linalg.lstsq(phi[:, support], y, rcond=None)[0]
        estimate[np.asarray(support, dtype=np.int64)] = coefficients
    return estimate, y - phi @ estimate


def _done(residual: Array, policy: Any) -> bool:
    return bool(np.linalg.norm(residual) <= float(policy.residual_atol))


def _result(x: Array, residual: Array, support: list[int], reason: str) -> Result:
    return Result(x.copy(), residual.copy(), tuple(support), reason)


def _omp(phi: Array, y: Array, policy: Any) -> Result:
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    reason = "max_iterations"
    column_norms = np.linalg.norm(phi, axis=0)
    for _ in range(int(policy.max_iterations)):
        selected = _rank((phi.T @ residual) / column_norms, 1, set(support))
        if not selected:
            reason = "no_new_atom"
            break
        support.append(selected[0])
        x, residual = _least_squares(phi, y, support)
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _cosamp(phi: Array, y: Array, policy: Any) -> Result:
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    reason = "max_iterations"
    for _ in range(int(policy.max_iterations)):
        count = min(2 * int(policy.sparsity), phi.shape[1])
        candidates = _rank(phi.T @ residual, count)
        work = sorted(set(support).union(candidates))
        estimate, _ = _least_squares(phi, y, work)
        support = sorted(_rank(estimate, int(policy.sparsity)))
        x = np.zeros_like(estimate)
        x[support] = estimate[support]
        residual = y - phi @ x
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _iht(phi: Array, y: Array, policy: Any) -> Result:
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    reason = "max_iterations"
    for _ in range(int(policy.max_iterations)):
        tentative = x + float(policy.step_size) * (phi.T @ residual)
        support = sorted(_rank(tentative, int(policy.sparsity)))
        x = np.zeros_like(x)
        x[support] = tentative[support]
        residual = y - phi @ x
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _htp(phi: Array, y: Array, policy: Any) -> Result:
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    reason = "max_iterations"
    for _ in range(int(policy.max_iterations)):
        tentative = x + float(policy.step_size) * (phi.T @ residual)
        support = sorted(_rank(tentative, int(policy.sparsity)))
        x, residual = _least_squares(phi, y, support)
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _sp(phi: Array, y: Array, policy: Any) -> Result:
    support = sorted(_rank(phi.T @ y, int(policy.sparsity)))
    x, residual = _least_squares(phi, y, support)
    if _done(residual, policy):
        return _result(x, residual, support, "residual_tolerance")
    reason = "max_iterations"
    for _ in range(1, int(policy.max_iterations) + 1):
        old_x = x.copy()
        old_residual = residual.copy()
        old_support = list(support)
        candidates = _rank(phi.T @ residual, int(policy.sparsity))
        work = sorted(set(support).union(candidates))
        estimate, _ = _least_squares(phi, y, work)
        support = sorted(_rank(estimate, int(policy.sparsity)))
        x, residual = _least_squares(phi, y, support)
        accepted = (
            not bool(policy.sp_stop_on_non_decrease)
            or np.linalg.norm(residual) < np.linalg.norm(old_residual)
        )
        if not accepted:
            x, residual, support = old_x, old_residual, old_support
            reason = "residual_not_decreased"
            break
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _gomp(phi: Array, y: Array, policy: Any) -> Result:
    group_size = int(policy.group_size)
    if group_size <= 0:
        raise ValueError("group_size must be positive")
    paper_limit = min(int(policy.sparsity), phi.shape[0] // group_size)
    limit = min(int(policy.max_iterations), paper_limit)
    reason = "paper_iteration_limit" if limit == paper_limit else "max_iterations"
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    for _ in range(limit):
        selected = _rank(phi.T @ residual, group_size, set(support))
        if not selected:
            reason = "no_new_atom"
            break
        support.extend(selected)
        x, residual = _least_squares(phi, y, support)
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _mp(phi: Array, y: Array, policy: Any) -> Result:
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    norms_sq = np.sum(phi * phi, axis=0)
    reason = "max_iterations"
    for _ in range(int(policy.max_iterations)):
        raw = phi.T @ residual
        selected = _rank(raw / np.sqrt(norms_sq), 1)[0]
        alpha = raw[selected] / norms_sq[selected]
        x[selected] += alpha
        if selected not in support:
            support.append(selected)
        residual = residual - alpha * phi[:, selected]
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


def _gp(phi: Array, y: Array, policy: Any) -> Result:
    support: list[int] = []
    x = np.zeros(phi.shape[1], dtype=np.float64)
    residual = y.copy()
    column_norms = np.linalg.norm(phi, axis=0)
    reason = "max_iterations"
    for _ in range(int(policy.max_iterations)):
        gradient = phi.T @ residual
        selected = _rank(gradient / column_norms, 1)[0]
        if selected not in support:
            support.append(selected)
        direction = np.zeros(phi.shape[1], dtype=np.float64)
        direction[support] = gradient[support]
        projected = phi @ direction
        denominator = float(projected @ projected)
        alpha = float((residual @ projected) / denominator) if denominator else 0.0
        x = x + alpha * direction
        residual = residual - alpha * projected
        if _done(residual, policy):
            reason = "residual_tolerance"
            break
    return _result(x, residual, support, reason)


ALGORITHMS = {
    "OMP": _omp,
    "CoSaMP": _cosamp,
    "IHT": _iht,
    "HTP": _htp,
    "SP": _sp,
    "GP": _gp,
    "GOMP": _gomp,
    "MP": _mp,
}


def run(name: str, phi: Any, y: Any, policy: Any) -> Result:
    try:
        algorithm = ALGORITHMS[name]
    except KeyError as exc:
        raise ValueError(f"unknown algorithm {name}") from exc
    matrix, measurement = _inputs(phi, y, policy)
    return algorithm(matrix, measurement, policy)
