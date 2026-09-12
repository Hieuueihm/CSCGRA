"""Bounded v4 context image format (ISA revision 1 candidate).

This module is a binary packer and structural validator only.  It does not
execute an image and it does not claim that a complete v4 program fits in one
image.  One image has 256 issue words, 32 independently encoded tile slots,
and one 256-bit control word per issue.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import argparse
import hashlib
import json
from pathlib import Path
from typing import Sequence


REVISION = 1
DEPTH = 256
PE_SLOTS = 32
TILE_BYTES = 8
CONTROL_BYTES = 32

OPCODES = {"NOP": 0, "CLEAR": 1, "READ": 2, "MAC": 3, "ADD": 4,
           "SUB": 5, "MUL": 6, "MOV": 7, "STORE": 8, "ROUTE": 9,
           "CMP": 10, "SELECT": 11, "HALT": 12}
OPERANDS = {"NONE": 0, "ACC": 1, "RF": 2, "MATRIX": 3, "VECTOR": 4,
            "IMMEDIATE": 5, "LINK": 6, "PREDICATE": 7}
FORMATS = {"NONE": 0, "SIGNED": 1, "UNSIGNED": 2, "FIXED": 3,
           "ADDRESS": 4}
ROUTES = {"NONE": 0, "VALUE": 1, "ACC": 2, "RESULT": 3}
CONTROL_KINDS = {"NOP": 0, "LOOP_BEGIN": 1, "LOOP_END": 2,
                 "BRANCH": 3, "WAIT": 4, "ADDRESS": 5, "HALT": 6}
ADDRESS_MODES = {"NONE": 0, "MATRIX": 1, "VECTOR": 2, "RESULT": 3,
                 "SCRATCH": 4}
LINK_DIRECTIONS = {0: "N", 1: "E", 2: "S", 3: "W"}
TILE_FIELDS = (("opcode", 6), ("srcA_kind", 4), ("srcB_kind", 4),
               ("srcA_reg", 3), ("srcB_reg", 3), ("dst_reg", 3),
               ("rf_write", 1), ("acc_write", 1), ("predicate", 3), ("format", 3),
               ("routeN", 3), ("routeE", 3), ("routeS", 3), ("routeW", 3),
               ("immediate", 16), ("reserved", 5))


class ImageValidationError(ValueError):
    """Raised when an image is malformed or violates the v4 candidate ABI."""


def _enum(value, table: dict[str, int], name: str) -> int:
    if isinstance(value, bool):
        raise ImageValidationError(f"{name} must be an enum value")
    if isinstance(value, str):
        if value not in table:
            raise ImageValidationError(f"unknown {name}: {value}")
        return table[value]
    if isinstance(value, int) and value in table.values():
        return value
    raise ImageValidationError(f"unknown {name}: {value!r}")


def _enum_name(value: int, table: dict[str, int]) -> str:
    return next(name for name, number in table.items() if number == value)


def _field(value: int, width: int, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ImageValidationError(f"{name} must be a non-negative integer")
    if value < 0 or value >= (1 << width):
        raise ImageValidationError(f"{name} is outside {width}-bit range")
    return value


@dataclass(frozen=True)
class TileInstruction:
    """One PE slot of one issue word.

    Field widths sum exactly to 64: 6+4+4+3+3+3+1+1+3+3+4*3+16+5.
    ``reserved`` must remain zero so later ISA revisions cannot silently
    reinterpret old images.
    """

    opcode: str | int = "NOP"
    srcA_kind: str | int = "NONE"
    srcB_kind: str | int = "NONE"
    srcA_reg: int = 0
    srcB_reg: int = 0
    dst_reg: int = 0
    rf_write: int = 0
    acc_write: int = 0
    predicate: int = 0
    format: str | int = "NONE"
    routeN: str | int = "NONE"
    routeE: str | int = "NONE"
    routeS: str | int = "NONE"
    routeW: str | int = "NONE"
    immediate: int = 0
    reserved: int = 0


@dataclass(frozen=True)
class ControlInstruction:
    """One generic control descriptor; fields are a proposal for revision 1."""

    kind: str | int = "NOP"
    flags: int = 0
    repeat: int = 0
    count: int = 0
    loop_target: int = 0
    branch_target: int = 0
    predicate: int = 0
    address_mode: str | int = "NONE"
    immediate_address: int = 0
    stride: int = 0
    immediate: int = 0
    reserved: int = 0


@dataclass(frozen=True)
class ContextImage:
    """Decoded image.  ``tiles[issue][pe]`` has 256 x 32 entries."""

    tiles: tuple[tuple[TileInstruction, ...], ...]
    controls: tuple[ControlInstruction, ...]
    metadata: dict = field(default_factory=dict)

    def validate(self) -> None:
        validate_image(self)

    def tile_payload(self, pe: int) -> bytes:
        _field(pe, 6, "pe")
        if pe >= PE_SLOTS:
            raise ImageValidationError("PE slot outside 32-slot image")
        return b"".join(pack_tile(issue[pe]) for issue in self.tiles)

    def control_payload(self) -> bytes:
        return b"".join(pack_control(control) for control in self.controls)

    @property
    def payload_bytes(self) -> int:
        return PE_SLOTS * DEPTH * TILE_BYTES + DEPTH * CONTROL_BYTES

    def disassembly(self) -> list[str]:
        lines = []
        for issue, (tiles, control) in enumerate(zip(self.tiles, self.controls)):
            if control.kind != "NOP" or any(tile.opcode != "NOP" for tile in tiles):
                active = ",".join(f"pe{pe}:{tile.opcode}" for pe, tile in enumerate(tiles)
                                  if tile.opcode != "NOP")
                lines.append(f"{issue:03d} ctl={control.kind} {active}")
        return lines


def _tile_values(tile: TileInstruction) -> tuple[int, ...]:
    opcode = _enum(tile.opcode, OPCODES, "opcode")
    a = _enum(tile.srcA_kind, OPERANDS, "srcA_kind")
    b = _enum(tile.srcB_kind, OPERANDS, "srcB_kind")
    fmt = _enum(tile.format, FORMATS, "format")
    routes = tuple(_enum(value, ROUTES, name) for value, name in
                   ((tile.routeN, "routeN"), (tile.routeE, "routeE"),
                    (tile.routeS, "routeS"), (tile.routeW, "routeW")))
    fields = (opcode, a, b, _field(tile.srcA_reg, 3, "srcA_reg"),
              _field(tile.srcB_reg, 3, "srcB_reg"), _field(tile.dst_reg, 3, "dst_reg"),
              _field(tile.rf_write, 1, "rf_write"), _field(tile.acc_write, 1, "acc_write"),
              _field(tile.predicate, 3, "predicate"), fmt, *routes,
              _field(tile.immediate, 16, "immediate"), _field(tile.reserved, 5, "reserved"))
    if fields[-1] != 0:
        raise ImageValidationError("tile reserved bits must be zero")
    if a == OPERANDS["LINK"] and fields[3] > 3:
        raise ImageValidationError("srcA LINK selector must be 0..3")
    if b == OPERANDS["LINK"] and fields[4] > 3:
        raise ImageValidationError("srcB LINK selector must be 0..3")
    if opcode == OPCODES["ROUTE"]:
        if not any(routes):
            raise ImageValidationError("ROUTE instruction needs a route direction")
        if a not in (OPERANDS["ACC"], OPERANDS["LINK"], OPERANDS["NONE"]):
            raise ImageValidationError("ROUTE source must be ACC, LINK, or NONE")
    # Route fields are an independent registered-router sideband.  They may
    # coexist with an ALU opcode (the old restriction was only a prototype
    # simplification, not a v4 ABI rule).
    if opcode == OPCODES["NOP"] and any(fields[1:-1]):
        raise ImageValidationError("NOP must have zero payload fields")
    if opcode == OPCODES["HALT"] and any(routes):
        raise ImageValidationError("HALT cannot route")
    return fields


def pack_tile(tile: TileInstruction) -> bytes:
    widths = tuple(width for _, width in TILE_FIELDS)
    value = 0
    offset = 0
    for item, width in zip(_tile_values(tile), widths):
        value |= item << offset
        offset += width
    return value.to_bytes(TILE_BYTES, "little")


def unpack_tile(payload: bytes) -> TileInstruction:
    if not isinstance(payload, (bytes, bytearray)) or len(payload) != TILE_BYTES:
        raise ImageValidationError("tile word must be exactly 8 bytes")
    raw = int.from_bytes(payload, "little")
    widths = tuple(width for _, width in TILE_FIELDS)
    values, offset = [], 0
    for width in widths:
        values.append((raw >> offset) & ((1 << width) - 1))
        offset += width
    (opcode, a, b, a_reg, b_reg, dst, rf, acc, pred, fmt, n, e, s, w,
     immediate, reserved) = values
    # Reuse all semantic validation, including unknown enum and reserved checks.
    tile = TileInstruction(_enum_name(opcode, OPCODES), _enum_name(a, OPERANDS),
                           _enum_name(b, OPERANDS), a_reg, b_reg, dst, rf, acc, pred,
                           _enum_name(fmt, FORMATS), _enum_name(n, ROUTES),
                           _enum_name(e, ROUTES), _enum_name(s, ROUTES),
                           _enum_name(w, ROUTES), immediate, reserved)
    _tile_values(tile)
    return tile


CONTROL_FIELDS = (("kind", 4), ("flags", 4), ("repeat", 8), ("count", 16),
                   ("loop_target", 8), ("branch_target", 8), ("predicate", 3),
                   ("address_mode", 3), ("immediate_address", 24), ("stride", 16),
                   ("immediate", 32), ("reserved", 130))


def _control_values(control: ControlInstruction) -> tuple[int, ...]:
    values = [_enum(control.kind, CONTROL_KINDS, "control kind"),
              _field(control.flags, 4, "flags"), _field(control.repeat, 8, "repeat"),
              _field(control.count, 16, "count"), _field(control.loop_target, 8, "loop_target"),
              _field(control.branch_target, 8, "branch_target"),
              _field(control.predicate, 3, "predicate"),
              _enum(control.address_mode, ADDRESS_MODES, "address_mode"),
              _field(control.immediate_address, 24, "immediate_address"),
              _field(control.stride, 16, "stride"), _field(control.immediate, 32, "immediate"),
              _field(control.reserved, 130, "reserved")]
    if values[-1] != 0:
        raise ImageValidationError("control reserved bits must be zero")
    kind = values[0]
    if kind == CONTROL_KINDS["LOOP_BEGIN"] and (values[3] == 0 or values[4] >= DEPTH):
        raise ImageValidationError("LOOP_BEGIN needs nonzero count and valid target")
    if kind == CONTROL_KINDS["LOOP_END"] and values[4] >= DEPTH:
        raise ImageValidationError("LOOP_END target outside context")
    if kind == CONTROL_KINDS["BRANCH"] and values[5] >= DEPTH:
        raise ImageValidationError("BRANCH target outside context")
    return tuple(values)


def pack_control(control: ControlInstruction) -> bytes:
    value = 0
    offset = 0
    for item, (_, width) in zip(_control_values(control), CONTROL_FIELDS):
        value |= item << offset
        offset += width
    return value.to_bytes(CONTROL_BYTES, "little")


def unpack_control(payload: bytes) -> ControlInstruction:
    if not isinstance(payload, (bytes, bytearray)) or len(payload) != CONTROL_BYTES:
        raise ImageValidationError("control word must be exactly 32 bytes")
    raw = int.from_bytes(payload, "little")
    values, offset = [], 0
    for _, width in CONTROL_FIELDS:
        values.append((raw >> offset) & ((1 << width) - 1))
        offset += width
    control = ControlInstruction(_enum_name(values[0], CONTROL_KINDS), values[1], values[2],
                                 values[3], values[4], values[5], values[6],
                                 _enum_name(values[7], ADDRESS_MODES), values[8],
                                 values[9], values[10], values[11])
    _control_values(control)
    return control


def validate_image(image: ContextImage) -> None:
    if not isinstance(image, ContextImage):
        raise ImageValidationError("expected ContextImage")
    if len(image.tiles) != DEPTH or len(image.controls) != DEPTH:
        raise ImageValidationError("context depth must be exactly 256 issue words")
    for issue, slots in enumerate(image.tiles):
        if len(slots) != PE_SLOTS:
            raise ImageValidationError(f"issue {issue} does not contain 32 PE slots")
        for pe, tile in enumerate(slots):
            _tile_values(tile)
            local = pe % 16
            row, col = divmod(local, 4)
            for source, direction, name in ((tile.srcA_kind, tile.srcA_reg, "srcA"),
                                            (tile.srcB_kind, tile.srcB_reg, "srcB")):
                if _enum(source, OPERANDS, name + "_kind") == OPERANDS["LINK"]:
                    if direction not in LINK_DIRECTIONS:
                        raise ImageValidationError(f"{name} LINK selector must be 0..3")
                    if ((direction == 0 and row == 0) or
                            (direction == 1 and col == 3) or
                            (direction == 2 and row == 3) or
                            (direction == 3 and col == 0)):
                        raise ImageValidationError(f"{name} LINK read crosses cluster boundary")
            routes = tuple(_enum(value, ROUTES, name) for value, name in
                           ((tile.routeN, "routeN"), (tile.routeE, "routeE"),
                            (tile.routeS, "routeS"), (tile.routeW, "routeW")))
            if routes[0] != ROUTES["NONE"] and row == 0:
                raise ImageValidationError("route crosses north cluster boundary")
            if routes[1] != ROUTES["NONE"] and col == 3:
                raise ImageValidationError("route crosses east cluster boundary")
            if routes[2] != ROUTES["NONE"] and row == 3:
                raise ImageValidationError("route crosses south cluster boundary")
            if routes[3] != ROUTES["NONE"] and col == 0:
                raise ImageValidationError("route crosses west cluster boundary")
        _control_values(image.controls[issue])


def pack_context(tiles: Sequence[Sequence[TileInstruction]],
                 controls: Sequence[ControlInstruction] | None = None,
                 *, metadata: dict | None = None) -> ContextImage:
    if len(tiles) > DEPTH or (controls is not None and len(controls) > DEPTH):
        raise ImageValidationError("context exceeds 256 issue words")
    controls = tuple(controls or ())
    if controls and len(controls) != len(tiles):
        raise ImageValidationError("tile and control issue counts differ")
    empty_tile = tuple(TileInstruction() for _ in range(PE_SLOTS))
    tile_rows = []
    for issue, row in enumerate(tiles):
        if len(row) != PE_SLOTS:
            raise ImageValidationError(f"issue {issue} does not contain 32 PE slots")
        tile_rows.append(tuple(row))
    while len(tile_rows) < DEPTH:
        tile_rows.append(empty_tile)
    control_rows = list(controls) if controls else [ControlInstruction() for _ in tiles]
    while len(control_rows) < DEPTH:
        control_rows.append(ControlInstruction())
    image = ContextImage(tuple(tile_rows), tuple(control_rows), dict(metadata or {}))
    validate_image(image)
    return image


def _hex_file(path: Path, payload: bytes, width: int) -> None:
    path.write_text("".join(payload[i:i + width].hex() + "\n"
                                for i in range(0, len(payload), width)), encoding="ascii")


def write_image(image: ContextImage, directory: str | Path) -> dict:
    validate_image(image)
    target = Path(directory)
    target.mkdir(parents=True, exist_ok=True)
    files = {}
    for pe in range(PE_SLOTS):
        name = f"tile_{pe:02d}.hex"
        _hex_file(target / name, image.tile_payload(pe), TILE_BYTES)
        files[name] = hashlib.sha256((target / name).read_bytes()).hexdigest()
    _hex_file(target / "control.hex", image.control_payload(), CONTROL_BYTES)
    files["control.hex"] = hashlib.sha256((target / "control.hex").read_bytes()).hexdigest()
    counts = used_word_counts(image)
    manifest = {"schema": "cscgra-v4-context-image", "revision": REVISION,
                "depth": DEPTH, "pe_slots": PE_SLOTS, "active_images": 1,
                "execution_status": "NOT_EXECUTED", "execution_proof": "NOT_PROVEN",
                "program_capacity_validated": False,
                "all_eleven_programs_simultaneously_resident": False,
                "files": files,
                "metadata": image.metadata, "used_word_counts": counts,
                "disassembly": image.disassembly()}
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                           encoding="utf-8")
    return manifest


def load_image(directory: str | Path) -> ContextImage:
    target = Path(directory)
    manifest_path = target / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("revision") != REVISION or manifest.get("depth") != DEPTH or manifest.get("pe_slots") != PE_SLOTS:
        raise ImageValidationError("unsupported context image manifest")
    expected_names = {f"tile_{pe:02d}.hex" for pe in range(PE_SLOTS)} | {"control.hex"}
    declared_files = manifest.get("files")
    if not isinstance(declared_files, dict) or set(declared_files) != expected_names:
        raise ImageValidationError("manifest must hash all tile and control payloads")
    for name, expected in declared_files.items():
        actual = hashlib.sha256((target / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ImageValidationError(f"hash mismatch for {name}")
    tiles = [[None] * PE_SLOTS for _ in range(DEPTH)]
    for pe in range(PE_SLOTS):
        raw = bytes.fromhex("".join(target.joinpath(f"tile_{pe:02d}.hex").read_text(encoding="ascii").split()))
        if len(raw) != DEPTH * TILE_BYTES:
            raise ImageValidationError("tile payload has wrong length")
        for issue in range(DEPTH):
            tiles[issue][pe] = unpack_tile(raw[issue * TILE_BYTES:(issue + 1) * TILE_BYTES])
    raw = bytes.fromhex("".join((target / "control.hex").read_text(encoding="ascii").split()))
    if len(raw) != DEPTH * CONTROL_BYTES:
        raise ImageValidationError("control payload has wrong length")
    controls = tuple(unpack_control(raw[i * CONTROL_BYTES:(i + 1) * CONTROL_BYTES]) for i in range(DEPTH))
    image = ContextImage(tuple(tuple(row) for row in tiles), controls, manifest.get("metadata", {}))
    validate_image(image)
    return image


def build_gemv_template(reduction_lanes: int, *, output_count: int = 128,
                        reduction_count: int = 1024) -> ContextImage:
    """Build a bounded, dimension-free GEMV template for R1 or R4.

    The loop body explicitly exposes the one-cycle read-to-MAC latency.  The
    template is a compiler/loader artifact with ``NOT_EXECUTED`` status; it is
    not an RTL equivalence proof and is not a claim that all programs fit.
    """
    if (isinstance(reduction_lanes, bool) or not isinstance(reduction_lanes, int) or
            reduction_lanes not in (1, 4) or
            isinstance(output_count, bool) or not isinstance(output_count, int) or output_count < 1 or
            isinstance(reduction_count, bool) or not isinstance(reduction_count, int) or reduction_count < 1):
        raise ImageValidationError("GEMV template needs R=1/R=4 and positive dimensions")
    lanes = 32 // reduction_lanes
    outer_count = (output_count + lanes - 1) // lanes
    reduction_iterations = (reduction_count + reduction_lanes - 1) // reduction_lanes
    rows = [list(TileInstruction() for _ in range(PE_SLOTS)) for _ in range(16)]
    ctl = [ControlInstruction() for _ in range(16)]
    for pe in range(PE_SLOTS):
        rows[0][pe] = TileInstruction("CLEAR", "MATRIX", "NONE", dst_reg=0, acc_write=1,
                                       format="FIXED")
    ctl[0] = ControlInstruction("LOOP_BEGIN", count=outer_count, loop_target=1,
                                address_mode="MATRIX", immediate_address=0, stride=1)
    ctl[1] = ControlInstruction("LOOP_BEGIN", count=reduction_iterations, loop_target=2)
    for pe in range(PE_SLOTS):
        rows[2][pe] = TileInstruction("READ", "MATRIX", "NONE", dst_reg=1, rf_write=1,
                                       format="ADDRESS")
        rows[3][pe] = TileInstruction("MAC", "RF", "VECTOR", srcA_reg=1, srcB_reg=0,
                                       dst_reg=0, acc_write=1, format="FIXED")
    ctl[2] = ControlInstruction("ADDRESS", address_mode="MATRIX", immediate_address=1,
                                stride=reduction_lanes)
    ctl[4] = ControlInstruction("LOOP_END", loop_target=1)
    if reduction_lanes == 1:
        for pe in range(PE_SLOTS):
            rows[5][pe] = TileInstruction("STORE", "ACC", "NONE", srcA_reg=0, format="FIXED")
        ctl[6] = ControlInstruction("LOOP_END", loop_target=0)
        ctl[7] = ControlInstruction("HALT")
    else:
        # R4 reduction phases mirror mapping.py: pair route/add, two cross
        # routes, final add, store.  Only west links are used by this template.
        for pe in range(PE_SLOTS):
            if pe % 4 in (1, 3):
                rows[5][pe] = TileInstruction("ROUTE", "ACC", "NONE", routeW="ACC")
            if pe % 4 in (0, 2):
                rows[6][pe] = TileInstruction("ADD", "ACC", "LINK", srcB_reg=1,
                                               acc_write=1, format="FIXED")
            if pe % 4 == 2:
                rows[7][pe] = TileInstruction("ROUTE", "ACC", "NONE", routeW="ACC")
            if pe % 4 == 1:
                rows[8][pe] = TileInstruction("ROUTE", "LINK", "NONE", srcA_reg=1,
                                               routeW="VALUE")
            if pe % 4 == 0:
                rows[9][pe] = TileInstruction("ADD", "ACC", "LINK", srcB_reg=1,
                                               acc_write=1, format="FIXED")
                rows[10][pe] = TileInstruction("STORE", "ACC", "NONE", srcA_reg=0, format="FIXED")
        ctl[10] = ControlInstruction("LOOP_END", loop_target=0)
        ctl[11] = ControlInstruction("HALT")
    metadata = {"template": "GEMV", "reduction_lanes": reduction_lanes,
                "output_count": output_count, "reduction_count": reduction_count,
                "outer_loop_count": outer_count,
                "inner_loop_count": reduction_iterations,
                "reduction_issue_stride": reduction_lanes,
                "tail_semantics": ("EXACT" if reduction_count % reduction_lanes == 0 else
                                    "UNRESOLVED_FEEDER_PREDICATE_FOR_FINAL_PARTIAL_BLOCK"),
                "execution_status": "NOT_EXECUTED", "equivalence": "NOT_PROVEN",
                "pipeline": {"matrix_read_latency_cycles": 1,
                             "first_read": "clear_issue_prefetch_descriptor",
                             "last_read": "read_issue_immediately_before_final_mac",
                             "registered_links": reduction_lanes == 4,
                             "template_initiation_interval": "UNKNOWN",
                             "reference_mapping_initiation_interval": 1,
                             "template_read_mac_serialized": True},
                "expanded_issue_contract": "dimension-free loop template; expanded schedule may exceed 256",
                "phases": ["clear", "read", "mac"] + (["pair_route", "pair_add",
                             "cross_route_1", "cross_route_2", "final_add", "store"] if reduction_lanes == 4 else ["store"])}
    return pack_context(rows, ctl, metadata=metadata)


gemv_context_template = build_gemv_template

# Descriptive aliases keep callers independent of whether they call the
# artifact an image or a context while retaining one implementation.
pack_image = pack_context
read_image = load_image
export_image = write_image


def used_word_counts(image: ContextImage) -> dict[str, int]:
    validate_image(image)
    used_issues = [i for i, row in enumerate(image.tiles)
                   if any(tile.opcode != "NOP" for tile in row) or image.controls[i].kind != "NOP"]
    used_tiles = sum(tile.opcode != "NOP" for row in image.tiles for tile in row)
    used_controls = sum(control.kind != "NOP" for control in image.controls)
    return {"issue_words": (max(used_issues) + 1) if used_issues else 0,
            "tile_words": used_tiles, "control_words": used_controls}


def _main() -> int:
    parser = argparse.ArgumentParser(description="Export a bounded v4 GEMV context image")
    parser.add_argument("--reduction-lanes", type=int, choices=(1, 4), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    image = build_gemv_template(args.reduction_lanes)
    manifest = write_image(image, args.output)
    print(json.dumps({"output": str(args.output),
                      "used_word_counts": manifest["used_word_counts"],
                      "sha256": manifest["files"]}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
