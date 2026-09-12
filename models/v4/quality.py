"""Quality gates independent of algorithm support or implementation agreement."""
from __future__ import annotations
import math
from numbers import Integral, Real
import numpy as np


def metrics(truth, estimate):
    truth, estimate = np.asarray(truth, dtype=float), np.asarray(estimate, dtype=float)
    if truth.shape != estimate.shape or not truth.size:
        raise ValueError("nonempty matching signal shapes required")
    if not (np.all(np.isfinite(truth)) and np.all(np.isfinite(estimate))):
        raise ValueError("metrics require finite data")
    energy = float(np.sum(truth * truth))
    error = float(np.sum((truth-estimate) ** 2))
    nmse = error/energy if energy else (0.0 if error == 0 else math.inf)
    snr = math.inf if error == 0 else (-math.inf if energy == 0 else -10*math.log10(nmse))
    return {"mse": error/truth.size, "nmse": nmse, "snr_db": snr}


def compare(truth, floating, fixed, max_snr_loss_db=0.5, max_nmse_ratio=1.1,
            absolute_snr_min_db=None):
    """No same-support shortcut; no arbitrary clipping of a near-zero error.

    Exact-float/nonexact-fixed cases fail the strict relative gate and must be
    handled by a separately frozen absolute-error protocol, not a hidden floor.
    """
    thresholds = (max_snr_loss_db, max_nmse_ratio)
    if not all(not isinstance(value, (bool, np.bool_))
               and isinstance(value, Real) and math.isfinite(value) and value >= 0
               for value in thresholds):
        raise ValueError("relative quality thresholds must be finite and non-negative")
    if (absolute_snr_min_db is not None
            and (isinstance(absolute_snr_min_db, (bool, np.bool_))
                 or not isinstance(absolute_snr_min_db, Real)
                 or not math.isfinite(absolute_snr_min_db))):
        raise ValueError("absolute SNR floor must be finite")
    fp, fx = metrics(truth, floating), metrics(truth, fixed)
    if fp["nmse"] == 0:
        ratio = 1.0 if fx["nmse"] == 0 else math.inf
    elif math.isinf(fp["nmse"]):
        ratio = math.inf  # undefined relative quality on a zero-energy truth
    else:
        ratio = fx["nmse"]/fp["nmse"]
    loss = (0.0 if fp["snr_db"] == fx["snr_db"] else fp["snr_db"]-fx["snr_db"])
    arithmetic_quality = bool(loss <= max_snr_loss_db and ratio <= max_nmse_ratio)
    application_quality = None if absolute_snr_min_db is None else bool(
        fp["snr_db"] >= absolute_snr_min_db and fx["snr_db"] >= absolute_snr_min_db)
    return {"float": fp, "fixed": fx, "snr_loss_db": loss, "nmse_ratio": ratio,
            "arithmetic_quality_pass": arithmetic_quality,
            "application_quality_pass": application_quality,
            "paper_quality_pass": arithmetic_quality and application_quality is True}


def signed_dot_width(a_width, b_width, length):
    values = (a_width, b_width, length)
    if any(isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral)
           for value in values) or min(values) < 1:
        raise ValueError("positive widths and length required")
    bound = int(length) * (1 << (int(a_width)-1)) * (1 << (int(b_width)-1))
    return bound.bit_length()+1
