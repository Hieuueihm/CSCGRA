"""Integer LSQR numerical model for the v4 solver study.

This module deliberately stays separate from :mod:`models.v4.recovery`.  It
implements the Paige--Saunders undamped LSQR recurrence over the same raw
integer kernel interface as ``IntegerKernels``.  Vector values are state
format integers; norms, Givens scalars, and divisions use an explicitly
selected scalar format (state format by default).  Norms and energies are
computed with checked, wide integer prefix sums so an overflow cannot turn
into an apparent successful certificate.

The class is intended to be injected by the v4 recovery wrapper.  It keeps a
``last_ls_report`` after both successful and failed solves, which is useful for
quality/cost studies and does not make a cycle claim.
"""

from __future__ import annotations

from fractions import Fraction
import math
import numpy as np

from models.v4.fixed import Format
from models.v4.recovery import IntegerKernels


class IntegerLSQRKernels(IntegerKernels):
    """Integer kernel backend using undamped zero-initialized LSQR.

    ``scalar_format`` is an explicit study knob.  Omitting it uses the shared
    state format, which is the v4 baseline and is reported in the LS report.
    It applies to norms, Givens scalars, and DIV results; vectors remain in
    the profile state format and matrix/operator values remain coefficient
    format.
    """

    def __init__(self, matrix, measurement, policy, profile, scalar_format=None,
                 solution_format=None):
        super().__init__(matrix, measurement, policy, profile)
        if scalar_format is None:
            scalar_format = profile.state
        if not isinstance(scalar_format, Format):
            raise TypeError("scalar_format must be a Format")
        self.scalar_format = scalar_format
        self.solution_format = profile.data if solution_format is None else solution_format
        if not isinstance(self.solution_format, Format):
            raise TypeError("solution_format must be a Format")
        xf, sf = self.solution_format, profile.state
        # Stored coefficients must embed exactly into the arithmetic state.
        # Otherwise the certificate would check another rounding of X.
        if (xf.frac > sf.frac or
                (xf.minimum << (sf.frac-xf.frac)) < sf.minimum or
                (xf.maximum << (sf.frac-xf.frac)) > sf.maximum):
            raise ValueError("solution format must embed exactly into state format")
        self._phase = "recurrence"
        self._report = None
        self.last_candidate = None
        self.last_pre_storage = None
        self.last_ls_report = self._new_report()

    def _new_report(self):
        scalar_name = None
        if hasattr(self, "scalar_format"):
            scalar_name = f"S{self.scalar_format.width}F{self.scalar_format.frac}"
        return {
            "solver": "LSQR",
            "scalar_format": scalar_name,
            "solution_format": {
                "width": self.solution_format.width,
                "frac": self.solution_format.frac,
            },
            "state_format": (
                f"S{self.profile.state.width}F{self.profile.state.frac}"
                if hasattr(self, "profile") else None
            ),
            "accumulator_width": (
                self.profile.accumulator_width if hasattr(self, "profile") else None
            ),
            "status": "not_run",
            "steps": 0,
            "counts": {
                "gemv": 0,
                "dot": 0,
                "div": 0,
                "sqrt": 0,
                "scale": 0,
                "add": 0,
                "sub": 0,
                "recurrence": {"gemv": 0, "dot": 0, "div": 0, "sqrt": 0},
                "certificate": {"gemv": 0, "dot": 0, "div": 0, "sqrt": 0},
            },
            "certificate_history": [],
            "scalar_ranges": {},
            "energy_prefix_max_abs": 0,
            "error": None,
        }

    def _count(self, kind):
        if self._report is None:
            return
        counts = self._report["counts"]
        counts[kind] += 1
        if self._phase in ("recurrence", "certificate") and kind in counts[self._phase]:
            counts[self._phase][kind] += 1

    def _range(self, name, value):
        if self._report is None:
            return
        value = int(value)
        ranges = self._report["scalar_ranges"]
        if name not in ranges:
            ranges[name] = {"min": value, "max": value}
        else:
            ranges[name]["min"] = min(ranges[name]["min"], value)
            ranges[name]["max"] = max(ranges[name]["max"], value)

    def mv(self, vector, transpose=False, support=None):
        self._count("gemv")
        return super().mv(vector, transpose=transpose, support=support)

    def dot(self, a, b):
        """Checked wide dot product with an accumulator-prefix guard."""
        self._count("dot")
        left = np.asarray(a, dtype=object)
        right = np.asarray(b, dtype=object)
        if left.ndim != 1 or right.ndim != 1 or left.shape != right.shape:
            raise ValueError("dot operands must be one-dimensional and aligned")
        lo = -(1 << (self.profile.accumulator_width - 1))
        hi = (1 << (self.profile.accumulator_width - 1)) - 1
        total = 0
        largest = 0
        for x, y in zip(left, right):
            total += int(x) * int(y)
            largest = max(largest, abs(total))
            if total < lo or total > hi:
                self.arithmetic.events["accumulator_overflow"] += 1
                if self._report is not None:
                    self._report["energy_prefix_max_abs"] = max(
                        self._report["energy_prefix_max_abs"], largest
                    )
                raise ArithmeticError("numeric_fault")
        if self._report is not None:
            self._report["energy_prefix_max_abs"] = max(
                self._report["energy_prefix_max_abs"], largest
            )
        return int(total)

    def _checked_energy_sum(self, terms):
        """Accumulate scalar squares under the same ACC prefix guard."""
        lo = -(1 << (self.profile.accumulator_width - 1))
        hi = (1 << (self.profile.accumulator_width - 1)) - 1
        total = 0
        for term in terms:
            total += int(term)
            if self._report is not None:
                self._report["energy_prefix_max_abs"] = max(
                    self._report["energy_prefix_max_abs"], abs(total)
                )
            if total < lo or total > hi:
                self.arithmetic.events["accumulator_overflow"] += 1
                raise ArithmeticError("numeric_fault")
        return total

    def add(self, a, b):
        self._count("add")
        return super().add(a, b)

    def sub(self, a, b):
        self._count("sub")
        return super().sub(a, b)

    def scale(self, a, scalar):
        self._count("scale")
        if not isinstance(scalar, (int, np.integer)):
            raise TypeError("LSQR scalar must be an integer")
        sf = self.scalar_format
        vf = self.profile.state
        return np.array(
            [self.arithmetic.mul(int(x), int(scalar), vf, sf, vf) for x in a],
            dtype=object,
        )

    def store(self, value):
        """Round S to persistent X, then embed X exactly back into S.

        X is independent of input D when explicitly selected. Both the LS
        certificate and the outer program consume these stored coefficients.
        With job normalization, X remains in the normalized domain and the
        host applies the inverse power-of-two exponent at final decoding.
        """
        ar, state, stored = self.arithmetic, self.profile.state, self.solution_format
        return np.array([ar.rescale(ar.rescale(int(v), state.frac, stored),
                                    stored.frac, state) for v in value], dtype=object)

    @staticmethod
    def _nearest_sqrt_integer(numerator, denominator=1):
        """Round sqrt(numerator / denominator) to nearest integer, half up."""
        if numerator < 0 or denominator <= 0:
            raise ValueError("sqrt arguments must be non-negative")
        if numerator == 0:
            return 0
        # Find q=floor(sqrt(numerator/denominator)) without a float.
        q = math.isqrt(numerator // denominator)
        while (q + 1) * (q + 1) * denominator <= numerator:
            q += 1
        while q * q * denominator > numerator:
            q -= 1
        # The midpoint between q and q+1 is exact under this comparison.
        if 4 * numerator >= (2 * q + 1) * (2 * q + 1) * denominator:
            return q + 1
        return q

    def _sqrt_energy(self, energy, vector_frac):
        """Return sqrt(real energy) as a raw scalar-format integer."""
        self._count("sqrt")
        out_frac = self.scalar_format.frac
        if out_frac >= vector_frac:
            radicand = int(energy) << (2 * (out_frac - vector_frac))
            result = math.isqrt(radicand)
            if 4 * radicand >= (2 * result + 1) ** 2:
                result += 1
        else:
            shift = 2 * (vector_frac - out_frac)
            result = self._nearest_sqrt_integer(int(energy), 1 << shift)
        result = int(self.arithmetic.clip(result, self.scalar_format))
        self._range("norm", result)
        return result

    def _div(self, numerator, denominator, source_frac, name):
        """Exact integer nearest division into scalar format, with DIV count."""
        self._count("div")
        if int(denominator) == 0:
            self.arithmetic.events["divide_by_zero"] += 1
            raise ArithmeticError("zero_denominator")
        result = int(self.arithmetic.ratio(
            int(numerator), int(denominator), int(source_frac), self.scalar_format
        ))
        self._range(name, result)
        return result

    def _vector_div_norm(self, vector, norm):
        """Normalize with one reciprocal DIV and integer vector scaling.

        Let ``e=bit_length(norm)``. The DIV computes the bounded mantissa
        ``2**e/norm`` in scalar format. The vector product applies the
        corresponding exponent at its rescale point, so the scalar does
        not have to represent the unbounded inverse of a tiny real norm.
        """
        if norm == 0:
            raise ArithmeticError("zero_denominator")
        norm = int(norm)
        e = norm.bit_length()
        # Use a mantissa-plus-exponent reciprocal.  2**e/norm is in (1, 2],
        # so the scalar service never needs to represent 1/norm itself.  The
        # exponent is applied in the one vector product's rescale point.
        reciprocal = self._div(1 << e, norm, 0, "normalized_reciprocal")
        vf = self.profile.state
        sf = self.scalar_format
        return np.array(
            [self.arithmetic.rescale(int(v) * reciprocal,
                                     vf.frac + sf.frac + e - sf.frac, vf)
             for v in vector],
            dtype=object,
        )

    def _norm(self, vector, name):
        value = self._sqrt_energy(self.dot(vector, vector), self.profile.state.frac)
        self._range(name, value)
        return value

    def certificate(self, coefficients, support, rhs_energy):
        """Evaluate the normal residual after persistent X storage (default D)."""
        previous = self._phase
        self._phase = "certificate"
        try:
            residual = self.sub(self.y, self.mv(coefficients, support=support))
            normal = self.mv(residual, transpose=True, support=support)
            energy = self.dot(normal, normal)
            tolerance = Fraction(str(self.policy.ls_normal_rtol))
            passed = (
                energy * tolerance.denominator ** 2
                <= int(rhs_energy) * tolerance.numerator ** 2
            )
            self._last_certificate = {
                "normal_energy_raw": int(energy),
                "rhs_energy_raw": int(rhs_energy),
                "passed": bool(passed),
            }
            return bool(passed)
        finally:
            self._phase = previous

    def _check_candidate(self, x, support, rhs_energy, step):
        self.last_pre_storage = np.array([int(v) for v in x], dtype=object)
        candidate = self.store(x)
        self.last_candidate = np.array([int(v) for v in candidate], dtype=object)
        if any(self.events.values()):
            raise ArithmeticError("numeric_fault")
        passed = self.certificate(candidate, support, rhs_energy)
        item = {"step": int(step), "stored": [int(v) for v in candidate]}
        item.update(self._last_certificate)
        self._report["certificate_history"].append(item)
        if any(self.events.values()):
            raise ArithmeticError("numeric_fault")
        return candidate, passed

    def _finish(self, status, error=None):
        self._report["status"] = status
        self._report["error"] = error
        self._report["last_candidate"] = (
            None if self.last_candidate is None else [int(v) for v in self.last_candidate]
        )
        self._report["last_pre_storage"] = (
            None if self.last_pre_storage is None else [int(v) for v in self.last_pre_storage]
        )
        self.last_ls_report = self._report
        self._report = None

    def least_squares(self, support):
        """Solve ``min ||B*x-y||`` by bounded undamped LSQR.

        The method raises ``ArithmeticError`` with the same status vocabulary
        as the parent CGLS backend.  The candidate is never returned before
        it has been narrowed to X and passed the normal-residual certificate.
        """
        self._report = self._new_report()
        self._phase = "recurrence"
        self.ls_steps = 0
        self.last_candidate = None
        self.last_pre_storage = None
        support = list(support)
        if any(self.events.values()):
            self._finish("numeric_fault", "numeric_fault")
            raise ArithmeticError("numeric_fault")
        if not support:
            self._finish("success")
            return self.zeros(0)

        x = self.zeros(len(support))
        try:
            # g=B^T y supplies the exact same RHS normal-energy reference as
            # IntegerKernels.  The normalized initial v is deliberately
            # formed by a second GEMV after rounded u=y/beta: fixed-point
            # operator staging is not assumed linear.
            gradient = self.mv(self.y, transpose=True, support=support)
            rhs_energy = self.dot(gradient, gradient)
            beta = self._norm(self.y, "beta")
            self._range("beta", beta)
            if beta == 0:
                candidate, passed = self._check_candidate(x, support, rhs_energy, 0)
                if passed:
                    self._finish("success")
                    return candidate
                raise ArithmeticError("ls_not_converged")

            u = self._vector_div_norm(self.y, beta)
            v = self.mv(u, transpose=True, support=support)
            alpha = self._norm(v, "alpha")
            if alpha == 0:
                candidate, passed = self._check_candidate(x, support, rhs_energy, 0)
                if passed:
                    self._finish("success")
                    return candidate
                raise ArithmeticError("ls_not_converged")
            v = self._vector_div_norm(v, alpha)
            w = v.copy()
            phibar = beta
            rhobar = alpha

            # The policy budget counts candidate updates, exactly like CGLS.
            for step in range(1, self.policy.ls_max_iterations + 1):
                projected = self.mv(v, support=support)
                projected = self.sub(projected, self.scale(u, alpha))
                beta_new = self._norm(projected, "beta")

                if beta_new != 0:
                    u_new = self._vector_div_norm(projected, beta_new)
                else:
                    u_new = self.zeros(len(self.y))

                # Complete the next Golub--Kahan pair before applying the
                # current Givens rotation.  LSQR's theta and rhobar use this
                # newly computed alpha, not the previous alpha.
                if beta_new == 0:
                    v_new = self.zeros(len(support))
                    alpha_new = 0
                else:
                    v_new = self.mv(u_new, transpose=True, support=support)
                    v_new = self.sub(v_new, self.scale(v, beta_new))
                    alpha_new = self._norm(v_new, "alpha")
                    if alpha_new != 0:
                        v_new = self._vector_div_norm(v_new, alpha_new)
                    else:
                        v_new = self.zeros(len(support))

                rho_energy = self._checked_energy_sum((
                    int(rhobar) * int(rhobar), int(beta_new) * int(beta_new)
                ))
                rho = self._sqrt_energy(rho_energy, self.scalar_format.frac)
                self._range("rho", rho)
                if rho == 0:
                    # A zero rotation is a happy breakdown only if the stored
                    # candidate proves the same certificate as every other
                    # termination path.
                    candidate, passed = self._check_candidate(x, support, rhs_energy, step - 1)
                    if passed:
                        self._finish("success")
                        return candidate
                    raise ArithmeticError("ls_not_converged")

                c = self._div(rhobar, rho, 0, "c")
                s = self._div(beta_new, rho, 0, "s")
                theta = self.arithmetic.mul(alpha_new, s, self.scalar_format,
                                             self.scalar_format, self.scalar_format)
                rhobar_new = -self.arithmetic.mul(c, alpha_new, self.scalar_format,
                                                  self.scalar_format, self.scalar_format)
                phi = self.arithmetic.mul(c, phibar, self.scalar_format,
                                           self.scalar_format, self.scalar_format)
                phibar_new = self.arithmetic.mul(s, phibar, self.scalar_format,
                                                 self.scalar_format, self.scalar_format)
                self._range("theta", theta)
                self._range("rhobar", rhobar_new)
                self._range("phi", phi)
                self._range("phibar", phibar_new)
                step_scale = self._div(phi, rho, 0, "step")
                direction_scale = self._div(theta, rho, 0, "direction")
                x = self.add(x, self.scale(w, step_scale))
                # Golub--Kahan update: the new search vector is the newly
                # normalized v, corrected by the previous search vector.
                w = self.sub(v_new, self.scale(w, direction_scale))
                candidate, passed = self._check_candidate(x, support, rhs_energy, step)
                self.ls_steps = step
                self._report["steps"] = step
                if passed:
                    self._finish("success")
                    return candidate
                if beta_new == 0 or (not np.any(v_new)):
                    raise ArithmeticError("ls_not_converged")
                v = v_new
                alpha = alpha_new
                u = u_new
                phibar = phibar_new
                rhobar = rhobar_new

            raise ArithmeticError("ls_not_converged")
        except ArithmeticError as error:
            status = str(error)
            self._report["steps"] = self.ls_steps
            self._finish(status, status)
            raise


# Short alias for callers that name the solver rather than the implementation.
LSQRKernels = IntegerLSQRKernels
