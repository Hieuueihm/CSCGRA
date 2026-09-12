"""Canonical v4 resident matrix image construction and validation.

The host owns the physical operator and quantizes it once.  This module then
stores the resulting integer matrix in the two :class:`MatrixLayout`
orientations used by the v4 GEMV schedule.  It deliberately does not generate
an operator, choose a numerical profile, or model RTL cycles.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from numbers import Integral, Real
from pathlib import Path
import re
from functools import lru_cache
from typing import Sequence

import numpy as np

from compiler.v4.mapping import MatrixLayout
from models.v4.fixed import Arithmetic, Format, Profile


_ORIENTATIONS = ("A", "transpose_A")


def _require_text(value: object, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string")
    return value


def _require_matrix_kind(value: object) -> str:
    value = _require_text(value, "matrix_kind")
    if value != "dense":
        raise ValueError("only matrix_kind='dense' is implemented")
    return value


def _shape_matrix(matrix: object) -> np.ndarray:
    source = np.asarray(matrix)
    if source.ndim != 2:
        raise ValueError("matrix must be two-dimensional")
    rows, columns = source.shape
    if rows < 1 or columns < 1:
        raise ValueError("matrix dimensions must be positive")
    for value in source.flat:
        item = value.item() if hasattr(value, "item") else value
        if isinstance(item, bool) or not isinstance(item, Real):
            raise TypeError("matrix values must be real numbers")
        if not math.isfinite(item):
            raise ValueError("matrix values must be finite")
    return source


def _shape_product(phi: object, psi: object) -> tuple[np.ndarray, np.ndarray]:
    left, right = _shape_matrix(phi), _shape_matrix(psi)
    if left.shape[1] != right.shape[0]:
        raise ValueError("Phi and Psi dimensions do not compose")
    return left, right


def _raw_integer(value: object, name: str = "raw value") -> int:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise ValueError(f"{name} must be an integer")
    return int(value)


def _validate_format(fmt: Format, name: str = "format") -> Format:
    if not isinstance(fmt, Format):
        raise TypeError(f"{name} must be a Format")
    return fmt


def signed_hex(value: int, fmt: Format) -> str:
    """Encode one signed raw value as exact-width two's-complement hex."""
    fmt = _validate_format(fmt)
    raw = _raw_integer(value)
    if raw < fmt.minimum or raw > fmt.maximum:
        raise ValueError(f"raw value {raw} is outside signed {fmt.width}-bit range")
    digits = (fmt.width + 3) // 4
    return format(raw & ((1 << fmt.width) - 1), f"0{digits}x")


def parse_signed_hex(token: str, fmt: Format) -> int:
    """Decode one exact-width two's-complement hexadecimal token."""
    fmt = _validate_format(fmt)
    if not isinstance(token, str):
        raise TypeError("hex token must be a string")
    digits = (fmt.width + 3) // 4
    if re.fullmatch(rf"[0-9a-fA-F]{{{digits}}}", token) is None:
        raise ValueError(f"hex token must contain exactly {digits} hexadecimal digits")
    encoded = int(token, 16)
    # For widths which are not a multiple of four, the unused high nibble bits
    # must be zero for a canonical encoding.
    if encoded >= (1 << fmt.width):
        raise ValueError("hex token has bits above the signed width")
    sign = 1 << (fmt.width - 1)
    return encoded - (1 << fmt.width) if encoded & sign else encoded


def compose_operator(phi: object, psi: object) -> np.ndarray:
    """Return the real host operator ``A = Phi @ Psi`` before quantization."""
    left, right = _shape_product(phi, psi)
    result = np.asarray(left @ right)
    # Object multiplication can preserve Python integer precision, while the
    # normal NumPy path is preferable for floating-point source operators.
    for value in result.flat:
        item = value.item() if hasattr(value, "item") else value
        if isinstance(item, bool) or not isinstance(item, Real):
            raise TypeError("composed matrix values must be real numbers")
        if not math.isfinite(item):
            raise ValueError("composed matrix values must be finite")
    return result


def _canonical_integer_bytes(raw: tuple[tuple[int, ...], ...]) -> bytes:
    payload = {"columns": len(raw[0]), "rows": len(raw), "values": raw}
    return json.dumps(payload, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def matrix_hash(raw: Sequence[Sequence[int]]) -> str:
    """Hash dimensions and integer coefficients in canonical JSON form."""
    rows = tuple(tuple(_raw_integer(value) for value in row) for row in raw)
    if not rows or not rows[0] or any(len(row) != len(rows[0]) for row in rows):
        raise ValueError("raw matrix must be a non-empty rectangular matrix")
    return hashlib.sha256(_canonical_integer_bytes(rows)).hexdigest()


def _validate_raw_matrix(raw: object, fmt: Format) -> tuple[tuple[int, ...], ...]:
    fmt = _validate_format(fmt, "coefficient format")
    source = np.asarray(raw, dtype=object)
    if source.ndim != 2 or source.shape[0] < 1 or source.shape[1] < 1:
        raise ValueError("raw matrix must be a non-empty two-dimensional matrix")
    result: list[tuple[int, ...]] = []
    for row in source:
        checked = tuple(_raw_integer(value) for value in row)
        if any(value < fmt.minimum or value > fmt.maximum for value in checked):
            raise ValueError(f"matrix coefficient is outside signed {fmt.width}-bit range")
        result.append(checked)
    if not result or any(len(row) != len(result[0]) for row in result):
        raise ValueError("raw matrix must be rectangular")
    if not any(value != 0 for row in result for value in row):
        raise ValueError("matrix must contain at least one non-zero coefficient")
    # A zero column generally indicates a dropped or uninitialized atom.  It
    # is a load-time error rather than a valid sparse operator column.
    if any(not any(row[column] != 0 for row in result) for column in range(len(result[0]))):
        raise ValueError("matrix contains a zero column")
    return tuple(result)


def _layout_bijection(layout: MatrixLayout) -> None:
    addresses: set[tuple[int, int]] = set()
    for output in range(layout.output_count):
        for reduction in range(layout.reduction_count):
            address = layout.address(output, reduction)
            if address in addresses:
                raise ValueError("matrix layout aliases two coefficients")
            addresses.add(address)
    if len(addresses) != layout.output_count * layout.reduction_count:
        raise ValueError("matrix layout address map is not bijective")


def _pack_raw(raw: tuple[tuple[int, ...], ...], layout: MatrixLayout,
              fmt: Format) -> tuple[tuple[int | None, ...], ...]:
    _layout_bijection(layout)
    # MatrixLayout uses None as an internal marker.  A resident image has an
    # explicit zero in every padded tail cell so an uninitialized SRAM word is
    # never mistaken for a valid coefficient.
    packed = tuple(tuple(0 if value is None else value for value in bank)
                   for bank in layout.pack(raw))
    for bank in packed:
        if len(bank) != layout.bank_depth:
            raise ValueError("matrix bank has incorrect depth")
        for value in bank:
            if value is not None and (value < fmt.minimum or value > fmt.maximum):
                raise ValueError("packed coefficient exceeds signed format")
    return packed


@lru_cache(maxsize=None)
def _inverse_slots(layout: MatrixLayout) -> tuple[tuple[tuple[int, int] | None, ...], ...]:
    """Build the inverse map once; unpacking a 128x1024 image stays linear."""
    slots: list[list[tuple[int, int] | None]] = [
        [None] * layout.bank_depth for _ in range(32)
    ]
    for output in range(layout.output_count):
        for reduction in range(layout.reduction_count):
            bank, address = layout.address(output, reduction)
            if slots[bank][address] is not None:
                raise ValueError("matrix layout aliases two coefficients")
            # Return logical layout coordinates.  Thus unpack(A) has shape
            # MxN and unpack(transpose_A) has shape NxM (the latter is A.T).
            slots[bank][address] = (output, reduction)
    return tuple(tuple(bank) for bank in slots)


def unpack_orientation(banks: Sequence[Sequence[int | None]], layout: MatrixLayout,
                       fmt: Format) -> tuple[tuple[int, ...], ...]:
    """Unpack and validate one orientation, including tails and valid cells."""
    fmt = _validate_format(fmt, "coefficient format")
    if not isinstance(layout, MatrixLayout):
        raise TypeError("layout must be a MatrixLayout")
    if len(banks) != 32:
        raise ValueError("matrix image must contain exactly 32 banks")
    _layout_bijection(layout)
    inverse = _inverse_slots(layout)
    matrix: list[list[int | None]] = [[None] * layout.reduction_count
                                      for _ in range(layout.output_count)]
    for bank_index, bank in enumerate(banks):
        if len(bank) != layout.bank_depth:
            raise ValueError("matrix bank depth differs from layout")
        for address, value in enumerate(bank):
            slot = inverse[bank_index][address]
            if slot is None:
                if value is None:
                    raise ValueError("matrix tail is uninitialized")
                raw = _raw_integer(value, "tail value")
                if raw != 0:
                    raise ValueError("matrix tail contains a non-zero value")
                continue
            if value is None:
                raise ValueError("matrix valid coefficient is uninitialized")
            raw = _raw_integer(value)
            if raw < fmt.minimum or raw > fmt.maximum:
                raise ValueError("matrix coefficient is outside signed format")
            output, reduction = slot
            if matrix[output][reduction] is not None:
                raise ValueError("matrix layout aliases two coefficients")
            matrix[output][reduction] = raw
    if any(value is None for row in matrix for value in row):
        raise ValueError("matrix unpack left an uninitialized coefficient")
    return tuple(tuple(int(value) for value in row) for row in matrix)


@dataclass(frozen=True)
class MatrixImage:
    """A validated integer matrix and its two resident bank orientations."""

    raw_matrix: tuple[tuple[int, ...], ...]
    coefficient_format: Format
    profile: Profile
    source_domain: str
    source_tag: str
    matrix_kind: str
    forward_banks: tuple[tuple[int | None, ...], ...]
    transpose_banks: tuple[tuple[int | None, ...], ...]

    def __post_init__(self) -> None:
        fmt = _validate_format(self.coefficient_format, "coefficient format")
        if not isinstance(self.profile, Profile):
            raise TypeError("profile must be a Profile")
        if self.profile.coefficient != fmt:
            raise ValueError("coefficient format must be the profile coefficient format")
        _require_text(self.source_domain, "source_domain")
        _require_text(self.source_tag, "source_tag")
        _require_matrix_kind(self.matrix_kind)
        raw = _validate_raw_matrix(self.raw_matrix, fmt)
        if not isinstance(self.raw_matrix, tuple) or raw != self.raw_matrix:
            object.__setattr__(self, "raw_matrix", raw)
        forward = _pack_raw(raw, MatrixLayout(self.rows, self.columns), fmt)
        transpose = _pack_raw(raw, MatrixLayout(self.rows, self.columns, True), fmt)
        if tuple(self.forward_banks) != forward or tuple(self.transpose_banks) != transpose:
            raise ValueError("bank images are not the canonical packing of raw_matrix")
        self.validate()

    @property
    def rows(self) -> int:
        return len(self.raw_matrix)

    @property
    def columns(self) -> int:
        return len(self.raw_matrix[0])

    @property
    def matrix_sha256(self) -> str:
        return matrix_hash(self.raw_matrix)

    @property
    def layouts(self) -> dict[str, MatrixLayout]:
        return {"A": MatrixLayout(self.rows, self.columns),
                "transpose_A": MatrixLayout(self.rows, self.columns, True)}

    def banks(self, orientation: str) -> tuple[tuple[int | None, ...], ...]:
        if orientation == "A":
            return self.forward_banks
        if orientation == "transpose_A":
            return self.transpose_banks
        raise ValueError("orientation must be 'A' or 'transpose_A'")

    def unpack(self, orientation: str = "A") -> tuple[tuple[int, ...], ...]:
        layout = self.layouts.get(orientation)
        if layout is None:
            raise ValueError("orientation must be 'A' or 'transpose_A'")
        return unpack_orientation(self.banks(orientation), layout, self.coefficient_format)

    def validate(self) -> None:
        forward = self.unpack("A")
        transpose = self.unpack("transpose_A")
        if forward != self.raw_matrix:
            raise ValueError("A bank image does not round-trip to the canonical matrix")
        expected_transpose = tuple(tuple(row) for row in zip(*self.raw_matrix))
        if transpose != expected_transpose:
            raise ValueError("transpose_A bank image is not the exact transpose")
        if tuple(zip(*transpose)) != self.raw_matrix:
            raise ValueError("transpose equality failed")

    def manifest(self) -> dict:
        fmt = self.coefficient_format
        orientations: dict[str, dict[str, int | str]] = {}
        payload_words = self.rows * self.columns
        payload_bits = payload_words * fmt.width
        for name, layout in self.layouts.items():
            padded_words = 32 * layout.bank_depth
            padded_bits = padded_words * fmt.width
            orientations[name] = {
                "bank_count": 32,
                "bank_depth": layout.bank_depth,
                "bank_words": padded_words,
                "payload_words": payload_words,
                "padded_bits": padded_bits,
                "padded_bytes": (padded_bits + 7) // 8,
                "payload_bits": payload_bits,
                "payload_bytes": (payload_bits + 7) // 8,
            }
        return {
            "schema": "cscgra-v4-matrix-image-v1",
            "matrix_hash": self.matrix_sha256,
            "matrix_kind": self.matrix_kind,
            "source": {"domain": self.source_domain, "tag": self.source_tag},
            "dimensions": {"rows": self.rows, "columns": self.columns,
                           "measurements": self.rows, "atoms": self.columns},
            "numeric_format": {
                "profile": self.profile.name,
                "data": {"width": self.profile.data.width, "frac": self.profile.data.frac},
                "coefficient": {"width": fmt.width, "frac": fmt.frac,
                                "signed": True, "encoding": "two_complement"},
                "state": {"width": self.profile.state.width, "frac": self.profile.state.frac},
                "accumulator_width": self.profile.accumulator_width,
                "quantization": "single_pass_host_quantize",
            },
            "resident_orientations": orientations,
            "resident_payload_bytes": sum(item["payload_bytes"] for item in orientations.values()),
            "hex_digits": (fmt.width + 3) // 4,
            "tail_policy": "valid coefficients and every padded tail cell are explicit signed hex zero or value",
        }

    def write_bank_images(self, output_dir: str | Path) -> dict:
        """Write both 32-bank orientations and one canonical manifest."""
        destination = Path(output_dir)
        destination.mkdir(parents=True, exist_ok=True)
        files: dict[str, list[str]] = {}
        for orientation in _ORIENTATIONS:
            names: list[str] = []
            for bank_index, bank in enumerate(self.banks(orientation)):
                path = destination / f"{orientation}_bank{bank_index:02d}.hex"
                lines = [signed_hex(value or 0, self.coefficient_format)
                         for value in bank]
                path.write_text("\n".join(lines) + "\n", encoding="ascii")
                names.append(path.name)
            files[orientation] = names
        manifest = self.manifest()
        manifest["bank_files"] = files
        (destination / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        return manifest

    export = write_bank_images


def _manifest_value(manifest: dict, path: str) -> object:
    value: object = manifest
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            raise ValueError(f"manifest missing {path}")
        value = value[part]
    return value


def read_matrix_image(output_dir: str | Path, profile: Profile) -> MatrixImage:
    """Read and fully validate an exported image.

    ``profile`` is supplied by the caller because the manifest records the
    selected coefficient format and profile name, while the data/state formats
    remain a host/compiler contract.  Only direct child files named by the
    manifest are accepted; this also rejects path traversal and extra/missing
    bank images deterministically.
    """
    if not isinstance(profile, Profile):
        raise TypeError("profile must be a Profile")
    directory = Path(output_dir)
    manifest_path = directory / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError("matrix image is missing manifest.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("matrix image manifest is unreadable") from exc
    if not isinstance(manifest, dict) or manifest.get("schema") != "cscgra-v4-matrix-image-v1":
        raise ValueError("unsupported matrix image manifest schema")
    kind = manifest.get("matrix_kind")
    _require_matrix_kind(kind)
    dimensions = _manifest_value(manifest, "dimensions")
    if not isinstance(dimensions, dict):
        raise ValueError("manifest dimensions must be an object")
    rows, columns = dimensions.get("rows"), dimensions.get("columns")
    if (not isinstance(rows, int) or isinstance(rows, bool) or rows < 1 or
            not isinstance(columns, int) or isinstance(columns, bool) or columns < 1):
        raise ValueError("manifest dimensions are invalid")
    numeric = _manifest_value(manifest, "numeric_format")
    coefficient = numeric.get("coefficient") if isinstance(numeric, dict) else None
    if not isinstance(coefficient, dict):
        raise ValueError("manifest coefficient format is missing")
    if (coefficient.get("width") != profile.coefficient.width or
            coefficient.get("frac") != profile.coefficient.frac or
            coefficient.get("signed") is not True or
            coefficient.get("encoding") != "two_complement" or
            numeric.get("profile") != profile.name):
        raise ValueError("manifest numeric format differs from supplied profile")
    source = manifest.get("source")
    if not isinstance(source, dict):
        raise ValueError("manifest source is missing")
    source_domain = _require_text(source.get("domain"), "source.domain")
    source_tag = _require_text(source.get("tag"), "source.tag")
    listed = manifest.get("bank_files")
    if not isinstance(listed, dict) or set(listed) != set(_ORIENTATIONS):
        raise ValueError("manifest must name both resident orientations")
    expected_names: set[str] = set()
    parsed: dict[str, tuple[tuple[int, ...], ...]] = {}
    fmt = profile.coefficient
    for orientation in _ORIENTATIONS:
        layout = MatrixLayout(rows, columns, orientation == "transpose_A")
        names = listed[orientation]
        if not isinstance(names, list) or len(names) != 32:
            raise ValueError(f"manifest {orientation} bank list must contain 32 files")
        for bank_index, name in enumerate(names):
            if (not isinstance(name, str) or Path(name).name != name or
                    Path(name).is_absolute() or name in expected_names):
                raise ValueError("manifest bank file path is invalid or duplicated")
            expected = f"{orientation}_bank{bank_index:02d}.hex"
            if name != expected:
                raise ValueError("manifest bank file name does not match canonical order")
            expected_names.add(name)
        banks: list[tuple[int, ...]] = []
        for name in names:
            path = directory / name
            if not path.is_file() or path.resolve().parent != directory.resolve():
                raise ValueError(f"matrix image is missing bank file {name}")
            try:
                lines = path.read_text(encoding="ascii").splitlines()
            except (OSError, UnicodeError) as exc:
                raise ValueError(f"bank file {name} is unreadable") from exc
            if len(lines) != layout.bank_depth:
                raise ValueError(f"bank file {name} has incorrect depth")
            banks.append(tuple(parse_signed_hex(token, fmt) for token in lines))
        parsed[orientation] = unpack_orientation(tuple(banks), layout, fmt)
    actual_files = {path.name for path in directory.iterdir() if path.is_file()}
    if actual_files != expected_names | {"manifest.json"}:
        raise ValueError("matrix image has missing or extra files")
    raw = parsed["A"]
    if manifest.get("matrix_hash") != matrix_hash(raw):
        raise ValueError("manifest matrix hash does not match bank images")
    if tuple(tuple(row) for row in zip(*parsed["transpose_A"])) != raw:
        raise ValueError("exported orientations are not exact transposes")
    image = _image_from_raw(raw, profile, source_domain=source_domain,
                            source_tag=source_tag, matrix_kind=kind)
    if manifest.get("matrix_hash") != image.matrix_sha256:
        raise ValueError("manifest matrix hash does not match bank images")
    expected_manifest = image.manifest()
    for key in ("schema", "matrix_hash", "matrix_kind", "source", "dimensions",
                "numeric_format", "resident_orientations", "resident_payload_bytes",
                "hex_digits", "tail_policy"):
        if manifest.get(key) != expected_manifest.get(key):
            raise ValueError(f"manifest field {key} does not match image")
    return image


def build_matrix_image(matrix: object, profile: Profile, *, source_domain: str,
                       source_tag: str, matrix_kind: str = "dense") -> MatrixImage:
    """Quantize physical ``A`` once and create both resident orientations."""
    if not isinstance(profile, Profile):
        raise TypeError("profile must be a Profile")
    _require_matrix_kind(matrix_kind)
    physical = _shape_matrix(matrix)
    arithmetic = Arithmetic(profile)
    quantized = arithmetic.quantize(physical, profile.coefficient)
    if arithmetic.events["saturation"]:
        raise ValueError("matrix coefficient quantization saturated")
    raw = _validate_raw_matrix(quantized, profile.coefficient)
    return _image_from_raw(raw, profile, source_domain=source_domain,
                           source_tag=source_tag, matrix_kind=matrix_kind)


def _image_from_raw(raw: tuple[tuple[int, ...], ...], profile: Profile, *,
                    source_domain: str, source_tag: str,
                    matrix_kind: str = "dense") -> MatrixImage:
    """Create an image from already-quantized raw integers (no second quantize)."""
    _require_matrix_kind(matrix_kind)
    raw = _validate_raw_matrix(raw, profile.coefficient)
    forward = _pack_raw(raw, MatrixLayout(len(raw), len(raw[0])), profile.coefficient)
    transpose = _pack_raw(raw, MatrixLayout(len(raw), len(raw[0]), True), profile.coefficient)
    return MatrixImage(raw, profile.coefficient, profile, source_domain, source_tag,
                       matrix_kind, forward, transpose)


def build_composed_matrix_image(phi: object, psi: object, profile: Profile, *,
                                source_domain: str, source_tag: str,
                                matrix_kind: str = "dense") -> MatrixImage:
    """Compose ``Phi @ Psi`` in host real arithmetic, then quantize once."""
    return build_matrix_image(compose_operator(phi, psi), profile,
                              source_domain=source_domain, source_tag=source_tag,
                              matrix_kind=matrix_kind)


# Short aliases make the intended host API discoverable without adding a
# general operator framework.
construct_composed_matrix = compose_operator
construct_composed_matrix_image = build_composed_matrix_image


def _example_profile(width: int, frac: int) -> Profile:
    return Profile(Format(18, 14), Format(width, frac), Format(27, 19), 64)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Emit a deterministic v4 matrix image example")
    parser.add_argument("--output", type=Path, default=Path("reports/v4/matrix_example"))
    parser.add_argument("--rows", type=int, default=128)
    parser.add_argument("--columns", type=int, default=1024)
    parser.add_argument("--coefficient-width", type=int, default=18)
    parser.add_argument("--coefficient-frac", type=int, default=14)
    args = parser.parse_args(argv)
    if args.rows < 1 or args.columns < 1:
        parser.error("rows and columns must be positive")
    # This is explicitly a dense host example, not a claimed Bernoulli or
    # Phi/Psi construction.  Keeping the seed fixed makes the manifest stable.
    rng = np.random.default_rng(20260908)
    physical = rng.uniform(-0.5, 0.5, size=(args.rows, args.columns))
    image = build_matrix_image(physical, _example_profile(args.coefficient_width,
                                                           args.coefficient_frac),
                               source_domain="example", source_tag="seed=20260908",
                               matrix_kind="dense")
    image.write_bank_images(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
