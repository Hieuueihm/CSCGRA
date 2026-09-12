"""Deterministic SoC-side AXI fixtures for complete V4 recovery programs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np

from compiler.v4 import recovery_program as asm
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE, compile_recovery
from models.v4.fixed import Arithmetic, Format
from models.v4.lfsr_operator import LFSR32_DEFAULT_SEED, lfsr32_matrix
from models.v4.proximal import Policy as ProximalPolicy
from models.v4.proximal import run as proximal_run
from models.v4.recovery import Policy
from models.v4.recovery import run as recovery_run
from verification.v4.recovery_program_vm import execute


SCHEMA = "soc_axi_fixture_v1"
ACTIVE_ALGORITHMS = (
    "MP",
    "OMP",
    "GOMP",
    "CoSaMP",
    "SP",
    "IHT",
    "HTP",
    "GP",
    "FISTA",
    "PDHG",
)
QR_ALGORITHMS = frozenset(("OMP", "GOMP", "CoSaMP", "SP", "HTP"))
PROXIMAL_ALGORITHMS = frozenset(("FISTA", "PDHG"))
DEFAULT_ROWS = 16
DEFAULT_COLUMNS = 32
DEFAULT_SPARSITY = 2
DEFAULT_ITERATIONS = 8
DEFAULT_SEED = 0x12345678
DEFAULT_SCALE_RAW = 16384
DEFAULT_QR_PROFILE = "reference"
DEFAULT_QR_REFINEMENTS = 2
DEFAULT_INSTRUCTION_LIMIT = 100000
FORMAT_ID = 1
STATE_BITS = 27
STATE_FRAC = 22
DATA_BITS = 18
DATA_FRAC = 14
COEFFICIENT_BITS = 18
COEFFICIENT_FRAC = 16
BLOCK_LANES = 32
BLOCK_MASK = (1 << BLOCK_LANES) - 1
LANE_MASK = (1 << STATE_BITS) - 1
STORAGE_FORMATS = {
    "X24F20": Format(24, 20),
    "D18F14": Format(18, 14),
}


def _canonical_algorithm(algorithm: str) -> str:
    if not isinstance(algorithm, str):
        raise TypeError("algorithm must be a string")
    key = algorithm.strip().upper()
    aliases = {"COSAMP": "CoSaMP"}
    candidate = aliases.get(key, key)
    if candidate not in ACTIVE_ALGORITHMS:
        if key == "ADMM":
            raise ValueError("ADMM is intentionally excluded from the SoC fixture set")
        raise ValueError(f"unsupported algorithm: {algorithm}")
    return candidate


def _positive_int(value: Any, name: str, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"{name} must be an integer")
    if value < 1 or maximum is not None and value > maximum:
        bound = f"..{maximum}" if maximum is not None else ""
        raise ValueError(f"{name} must be in 1{bound}")
    return int(value)


def _u32(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"{name} must be an integer")
    if not 0 <= value <= 0xFFFFFFFF:
        raise ValueError(f"{name} must fit unsigned 32 bits")
    return int(value)


def _jsonify(value: Any) -> Any:
    if isinstance(value, np.generic):
        return _jsonify(value.item())
    if isinstance(value, Path):
        return value.as_posix()
    if isinstance(value, dict):
        return {str(key): _jsonify(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonify(item) for item in value]
    if isinstance(value, float):
        if not np.isfinite(value):
            raise ValueError("fixture metadata must contain finite numbers")
        return float(value)
    return value


def _hash_ints(values: Any, dtype: str) -> str:
    array = np.asarray(values, dtype=dtype)
    return hashlib.sha256(array.tobytes()).hexdigest()


def _pack_lanes(values: list[int]) -> int:
    packed = 0
    for lane, value in enumerate(values):
        packed |= (int(value) & LANE_MASK) << (STATE_BITS * lane)
    return packed


def _physical_lanes(block: int, values: list[int], lane_mask: int) -> list[dict[str, int]]:
    lanes = []
    for lane, value in enumerate(values):
        if not lane_mask & (1 << lane):
            continue
        port = lane // 16
        lanes.append(
            {
                "lane": lane,
                "bank": lane % 16,
                "port": port,
                "word": port * 512 + block,
                "value": int(value),
            }
        )
    return lanes


def _blocks_for_vector(vector: int, name: str, base: int, values: list[int]) -> list[dict[str, Any]]:
    blocks = []
    for offset in range(0, len(values), BLOCK_LANES):
        chunk = values[offset : offset + BLOCK_LANES]
        lane_values = chunk + [0] * (BLOCK_LANES - len(chunk))
        block = base + offset // BLOCK_LANES
        lane_mask = (1 << len(chunk)) - 1
        blocks.append(
            {
                "vector": vector,
                "name": name,
                "block": block,
                "lane_mask": lane_mask,
                "values": lane_values,
                "packed": _pack_lanes(lane_values),
                "lanes": _physical_lanes(block, lane_values, lane_mask),
            }
        )
    return blocks


def _load_records(package: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "kind": int(kind),
            "index": int(index),
            "word": int(word),
            "word_hex": f"{int(word) & ((1 << 128) - 1):032x}",
            "last": int(last),
        }
        for kind, index, word, last in asm.load_records(package)
    ]


def _measurement(matrix: np.ndarray) -> tuple[np.ndarray, list[int], list[float]]:
    columns = matrix.shape[1]
    truth_support = sorted({columns // 4, min(columns - 1, (3 * columns) // 8)})
    truth_values = [0.5, -0.75][: len(truth_support)]
    truth = np.zeros(columns, dtype=float)
    truth[truth_support] = truth_values
    values = np.rint((matrix @ truth) * (1 << DATA_FRAC)).astype(int)
    if not np.any(values):
        values[0] = 1
    return values, truth_support, truth_values


def _model_expected(
    algorithm: str,
    matrix: np.ndarray,
    measurement: np.ndarray,
    policy: Policy | ProximalPolicy,
    qr_refinements: int,
) -> Any:
    if algorithm in PROXIMAL_ALGORITHMS:
        return proximal_run(algorithm, matrix, measurement, policy, PROFILE)
    return recovery_run(
        algorithm,
        matrix,
        measurement,
        policy,
        PROFILE,
        ls_solver="qr" if algorithm in QR_ALGORITHMS else "lsqr",
        solution_format=Format(24, 20),
        qr_max_refinements=qr_refinements if algorithm in QR_ALGORITHMS else 0,
    )


def _status_code(status: str) -> int:
    key = status.upper()
    if key not in asm.ABI["statuses"]:
        raise ValueError(f"status is not in the V4 ABI: {status}")
    return int(asm.ABI["statuses"][key])


def build_case(
    algorithm: str,
    rows: int = DEFAULT_ROWS,
    columns: int = DEFAULT_COLUMNS,
    sparsity: int = DEFAULT_SPARSITY,
    iterations: int = DEFAULT_ITERATIONS,
    seed: int = DEFAULT_SEED,
    qr_profile: str = DEFAULT_QR_PROFILE,
    *,
    n: int | None = None,
    scale_raw: int = DEFAULT_SCALE_RAW,
    inner_max_iterations: int = DEFAULT_ITERATIONS,
    qr_max_refinements: int = DEFAULT_QR_REFINEMENTS,
    group_size: int = 2,
) -> dict[str, Any]:
    """Build one deterministic, JSON-serializable SoC integration case."""
    algorithm = _canonical_algorithm(algorithm)
    if n is not None:
        if columns != DEFAULT_COLUMNS and columns != n:
            raise ValueError("columns and n disagree")
        columns = n
    rows = _positive_int(rows, "rows", 128)
    columns = _positive_int(columns, "columns", 1024)
    sparsity = _positive_int(sparsity, "sparsity", columns)
    iterations = _positive_int(iterations, "iterations", DEFAULT_ITERATIONS)
    inner_max_iterations = _positive_int(
        inner_max_iterations, "inner_max_iterations", DEFAULT_ITERATIONS
    )
    if isinstance(qr_max_refinements, bool) or not isinstance(qr_max_refinements, int):
        raise TypeError("qr_max_refinements must be an integer")
    if not 0 <= qr_max_refinements <= DEFAULT_QR_REFINEMENTS:
        raise ValueError("qr_max_refinements must be in 0..2")
    group_size = _positive_int(group_size, "group_size", columns)
    seed = _u32(seed, "seed")
    if not isinstance(qr_profile, str):
        raise TypeError("qr_profile must be a string")
    if algorithm in QR_ALGORITHMS and qr_profile not in (
        "reference",
        "balanced",
        "panel",
        "reuse",
        "resident",
        "compact",
        "streamed",
        "view",
    ):
        raise ValueError("unsupported QR profile")
    if isinstance(scale_raw, bool) or not isinstance(scale_raw, int):
        raise TypeError("scale_raw must be an integer")
    if not 1 <= scale_raw <= (1 << (COEFFICIENT_BITS - 1)) - 1:
        raise ValueError("scale_raw must be a positive C18 value")

    phi_seed = LFSR32_DEFAULT_SEED if seed == 0 else seed
    raw_phi = lfsr32_matrix(phi_seed, rows, columns, scale=scale_raw).astype(int)
    matrix = raw_phi.astype(float) / float(1 << COEFFICIENT_FRAC)
    raw_measurement, truth_support, truth_values = _measurement(matrix)
    measurement = raw_measurement.astype(float) / float(1 << DATA_FRAC)
    if algorithm in PROXIMAL_ALGORITHMS:
        policy: Policy | ProximalPolicy = ProximalPolicy(
            max_iterations=iterations,
            inner_max_iterations=inner_max_iterations,
        )
    else:
        policy = Policy(
            sparsity=sparsity,
            max_iterations=iterations,
            group_size=group_size,
        )

    if algorithm in QR_ALGORITHMS:
        package = compile_greedy_qr(
            algorithm,
            matrix,
            policy,
            qr_profile=qr_profile,
            max_refinements=qr_max_refinements,
        )
    else:
        package = compile_recovery(algorithm, matrix, policy)
    vm = execute(package, matrix, measurement, limit=DEFAULT_INSTRUCTION_LIMIT)
    model = _model_expected(algorithm, matrix, measurement, policy, qr_max_refinements)
    model_status = {"qr_not_converged": "ls_not_converged", "rank_deficient": "numeric_fault"}.get(
        model.status, model.status
    )
    model_x = [round(float(value) * (1 << STATE_FRAC)) for value in model.x]
    model_residual = [round(float(value) * (1 << STATE_FRAC)) for value in model.residual]
    if list(map(int, vm["x"])) != model_x or list(map(int, vm["residual"])) != model_residual:
        raise AssertionError(f"integer VM/model mismatch for {algorithm}")
    if vm["status"] != model_status:
        raise AssertionError(f"status mismatch for {algorithm}: {vm['status']} != {model_status}")
    if int(vm["outer"]) != sum(entry["phase"] == "COMMIT" for entry in model.trace):
        raise AssertionError(f"outer iteration mismatch for {algorithm}")
    if algorithm not in PROXIMAL_ALGORITHMS and list(map(int, vm["support"])) != list(model.support):
        raise AssertionError(f"support mismatch for {algorithm}")

    arithmetic = Arithmetic(PROFILE)
    measurement_state = [
        int(value)
        for value in arithmetic.rescale(
            arithmetic.quantize(measurement, PROFILE.data), PROFILE.data.frac, PROFILE.state
        )
    ]
    storage_name = str(package["candidate_storage"])
    storage_format = STORAGE_FORMATS[storage_name]
    storage_values = [
        int(value)
        for value in arithmetic.rescale(vm["x"], PROFILE.state.frac, storage_format)
    ]
    phi_hash = _hash_ints(raw_phi, "<i4")
    key = int(phi_hash[:32], 16)
    vectors = _jsonify(package["vectors"])
    measurement_vector = int(package["measurement_vector"])
    vector_preloads = []
    for vector_index, descriptor in enumerate(vectors):
        values = measurement_state if vector_index == measurement_vector else []
        vector_preloads.append(
            {
                "vector": vector_index,
                "name": str(descriptor["name"]),
                "base_block": int(descriptor["base"]),
                "capacity": int(descriptor["capacity"]),
                "length": len(values),
                "values": values,
                "blocks": _blocks_for_vector(
                    vector_index,
                    str(descriptor["name"]),
                    int(descriptor["base"]),
                    values,
                ),
            }
        )
    start_storage_mode = 2 if storage_name == "D18F14" else 1
    expected_support = [] if algorithm in PROXIMAL_ALGORITHMS else [int(v) for v in vm["support"]]
    case_id = f"{algorithm.lower()}_{rows}x{columns}_k{sparsity}_i{iterations}_s{phi_seed:08x}"
    package_json = _jsonify(package)
    load_records = _load_records(package)
    package_json["load_records"] = load_records
    result = {
        "schema": SCHEMA,
        "case": {
            "id": case_id,
            "algorithm": algorithm,
            "rows": rows,
            "columns": columns,
            "sparsity": sparsity,
            "iterations_requested": iterations,
            "inner_iterations_bound": inner_max_iterations,
            "seed": phi_seed,
            "qr_profile": qr_profile if algorithm in QR_ALGORITHMS else None,
            "qr_max_refinements": qr_max_refinements,
            "scale_raw": int(scale_raw),
            "exponent": 0,
            "instruction_limit": DEFAULT_INSTRUCTION_LIMIT,
        },
        "host": {
            "format": FORMAT_ID,
            "storage_mode": start_storage_mode,
            "exponent": 0,
            "active_support": int(algorithm not in PROXIMAL_ALGORITHMS),
            "load_begin": {
                "revision": int(package["revision"]),
                "program_count": len(package["program"]),
                "constant_count": len(package["constants"]),
                "template_count": len(package["templates"]),
                "vector_count": len(package["vectors"]),
                "verified": 1,
            },
            "phi": {
                "seed": phi_seed,
                "rows": rows,
                "columns": columns,
                "scale_raw": int(scale_raw),
                "format": FORMAT_ID,
                "generation": 1,
                "job": 1,
                "tag": 1,
                "key": key,
            },
            "start": {
                "rows": rows,
                "columns": columns,
                "scale_raw": int(scale_raw),
                "format": FORMAT_ID,
                "generation": 1,
                "job": 1,
                "tag": 1,
                "key": key,
                "storage_mode": start_storage_mode,
                "exponent": 0,
                "active_support": int(algorithm not in PROXIMAL_ALGORITHMS),
                "instruction_limit": DEFAULT_INSTRUCTION_LIMIT,
            },
        },
        "package": package_json,
        "load_records": load_records,
        "phi": {
            "seed": phi_seed,
            "scale_raw": int(scale_raw),
            "rows": rows,
            "columns": columns,
            "format": {"width": COEFFICIENT_BITS, "frac": COEFFICIENT_FRAC},
            "values": [int(value) for value in raw_phi.ravel()],
            "sha256": phi_hash,
            "key": key,
        },
        "measurement": {
            "data_format": {"width": DATA_BITS, "frac": DATA_FRAC},
            "state_format": {"width": STATE_BITS, "frac": STATE_FRAC},
            "values_data": [int(value) for value in raw_measurement],
            "values_state": measurement_state,
            "sha256": _hash_ints(raw_measurement, "<i4"),
            "truth_support": truth_support,
            "truth_values": truth_values,
        },
        "preload": {
            "format": {"width": STATE_BITS, "frac": STATE_FRAC, "lanes": BLOCK_LANES},
            "measurement_vector": measurement_vector,
            "vectors": vector_preloads,
            "writes": [block for vector in vector_preloads for block in vector["blocks"]],
        },
        "expected": {
            "x": [int(value) for value in vm["x"]],
            "x_storage": storage_values,
            "residual": [int(value) for value in vm["residual"]],
            "support": expected_support,
            "status": str(vm["status"]),
            "status_code": _status_code(str(vm["status"])),
            "iterations": int(vm["outer"]),
            "inner_iterations": int(vm["inner"]),
            "exponent": 0,
            "storage": storage_name,
            "x_format": {"width": STATE_BITS, "frac": STATE_FRAC},
            "storage_format": {"width": storage_format.width, "frac": storage_format.frac},
            "committed": True,
            "active_support": int(algorithm not in PROXIMAL_ALGORITHMS),
        },
        "verification": {
            "golden": "verification.v4.recovery_program_vm.execute",
            "rtl_executed": False,
            "model_crosscheck": "models.v4.fixed plus existing integer algorithm model",
            "trace_length": len(vm["trace"]),
        },
    }
    return _jsonify(result)


def render_fixture(case: dict[str, Any]) -> str:
    """Render a case as the line-oriented SOC_AXI_FIXTURE_V1 format."""
    if not isinstance(case, dict) or case.get("schema") != SCHEMA:
        raise ValueError("case must be a soc_axi_fixture_v1 dictionary")
    metadata = case["case"]
    host = case["host"]
    phi = case["phi"]
    package = case["package"]
    lines = ["SOC_AXI_FIXTURE_V1"]
    for key in (
        "id",
        "algorithm",
        "rows",
        "columns",
        "sparsity",
        "iterations_requested",
        "seed",
        "scale_raw",
        "exponent",
        "instruction_limit",
    ):
        lines.append(f"META {key}={metadata[key]}")
    lines.append(f"META qr_profile={metadata['qr_profile']}")
    lines.append(f"META qr_max_refinements={metadata['qr_max_refinements']}")
    lines.append(
        "PHI "
        f"seed={phi['seed']} scale_raw={phi['scale_raw']} rows={phi['rows']} "
        f"columns={phi['columns']} format_width={phi['format']['width']} "
        f"format_frac={phi['format']['frac']} key={phi['key']} generation={host['phi']['generation']} "
        f"job={host['phi']['job']} tag={host['phi']['tag']} format_id={host['phi']['format']}"
    )
    lines.append(
        "PHI_BEGIN "
        f"seed={host['phi']['seed']} rows={host['phi']['rows']} columns={host['phi']['columns']} "
        f"key={host['phi']['key']} generation={host['phi']['generation']} job={host['phi']['job']} "
        f"tag={host['phi']['tag']} format={host['phi']['format']}"
    )
    for index, value in enumerate(phi["values"]):
        lines.append(f"PHI_DATA index={index} value={value}")
    load_begin = host["load_begin"]
    lines.append(
        "LOAD_BEGIN "
        f"revision={load_begin['revision']} program_count={load_begin['program_count']} "
        f"constant_count={load_begin['constant_count']} template_count={load_begin['template_count']} "
        f"vector_count={load_begin['vector_count']} verified={load_begin['verified']}"
    )
    for vector_index, descriptor in enumerate(package["vectors"]):
        lines.append(
            f"VECTOR vector={vector_index} name={descriptor['name']} "
            f"base_block={descriptor['base']} capacity={descriptor['capacity']}"
        )
    for index, template in enumerate(package["templates"]):
        lines.append(
            f"TEMPLATE template={index} name={template['name']} descriptor={template['descriptor']} "
            f"bind_a={template['bind_a']} bind_b={template['bind_b']}"
        )
        for lane, context in enumerate(template["contexts"]):
            lines.append(f"CONTEXT template={index} lane={lane} word={int(context):016x}")
    for index, value in enumerate(package["constants"]):
        lines.append(f"CONST index={index} value={int(value)}")
    for record in case["load_records"]:
        lines.append(
            f"LOAD kind={record['kind']} index={record['index']} data={record['word_hex']} last={record['last']}"
        )
    for program_counter, word in enumerate(package["program"]):
        lines.append(f"PROG pc={program_counter} word={int(word) & ((1 << 128) - 1):032x}")
    start = host["start"]
    lines.append(
        "START "
        f"rows={start['rows']} columns={start['columns']} key={start['key']} "
        f"generation={start['generation']} scale_raw={start['scale_raw']} job={start['job']} "
        f"tag={start['tag']} format={start['format']} storage_mode={start['storage_mode']} "
        f"exponent={start['exponent']} active_support={start['active_support']} "
        f"instruction_limit={start['instruction_limit']}"
    )
    for vector in case["preload"]["vectors"]:
        lines.append(
            f"VEC vector={vector['vector']} name={vector['name']} base_block={vector['base_block']} "
            f"capacity={vector['capacity']} length={vector['length']}"
        )
        for index, value in enumerate(vector["values"]):
            lines.append(f"VEC_DATA vector={vector['vector']} index={index} value={value}")
        for block in vector["blocks"]:
            lines.append(
                f"BLOCK vector={block['vector']} block={block['block']} lane_mask={block['lane_mask']:08x} "
                f"data={block['packed']:0216x}"
            )
            for lane in block["lanes"]:
                lines.append(
                    f"LANE vector={block['vector']} block={block['block']} lane={lane['lane']} "
                    f"bank={lane['bank']} port={lane['port']} word={lane['word']} value={lane['value']}"
                )
    expected = case["expected"]
    lines.append("EXPECT x=" + ",".join(str(value) for value in expected["x"]))
    lines.append("EXPECT x_storage=" + ",".join(str(value) for value in expected["x_storage"]))
    lines.append("EXPECT residual=" + ",".join(str(value) for value in expected["residual"]))
    lines.append("EXPECT support=" + ",".join(str(value) for value in expected["support"]))
    lines.append(
        "EXPECT "
        f"status={expected['status']} status_code={expected['status_code']} "
        f"iterations={expected['iterations']} inner_iterations={expected['inner_iterations']} "
        f"exponent={expected['exponent']} storage={expected['storage']}"
    )
    lines.append("END")
    return "\n".join(lines) + "\n"


def write_fixture(
    case_or_algorithm: dict[str, Any] | str,
    path: str | Path,
    *,
    rows: int = DEFAULT_ROWS,
    columns: int = DEFAULT_COLUMNS,
    sparsity: int = DEFAULT_SPARSITY,
    iterations: int = DEFAULT_ITERATIONS,
    seed: int = DEFAULT_SEED,
    qr_profile: str = DEFAULT_QR_PROFILE,
    n: int | None = None,
    scale_raw: int = DEFAULT_SCALE_RAW,
    inner_max_iterations: int = DEFAULT_ITERATIONS,
    qr_max_refinements: int = DEFAULT_QR_REFINEMENTS,
    group_size: int = 2,
) -> Path:
    """Build or serialize one fixture for consumption by a SystemVerilog TB."""
    case = (
        build_case(
            case_or_algorithm,
            rows=rows,
            columns=columns,
            sparsity=sparsity,
            iterations=iterations,
            seed=seed,
            qr_profile=qr_profile,
            n=n,
            scale_raw=scale_raw,
            inner_max_iterations=inner_max_iterations,
            qr_max_refinements=qr_max_refinements,
            group_size=group_size,
        )
        if isinstance(case_or_algorithm, str)
        else case_or_algorithm
    )
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_fixture(case), encoding="ascii")
    return output


def main(argv: list[str] | None = None) -> int:
    """Generate one or all default fixtures from the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--algorithm", action="append", dest="algorithms")
    parser.add_argument("--rows", type=int, default=DEFAULT_ROWS)
    parser.add_argument("--n", type=int, default=DEFAULT_COLUMNS)
    parser.add_argument("--sparsity", type=int, default=DEFAULT_SPARSITY)
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED)
    parser.add_argument("--scale-raw", type=int, default=DEFAULT_SCALE_RAW)
    parser.add_argument("--qr-profile", default=DEFAULT_QR_PROFILE)
    args = parser.parse_args(argv)
    algorithms = ACTIVE_ALGORITHMS if args.algorithms is None else tuple(args.algorithms)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for algorithm in algorithms:
        case = build_case(
            algorithm,
            rows=args.rows,
            n=args.n,
            sparsity=args.sparsity,
            iterations=args.iterations,
            seed=args.seed,
            scale_raw=args.scale_raw,
            qr_profile=args.qr_profile,
        )
        output = args.output_dir / f"{case['case']['id']}.fixture"
        write_fixture(case, output)
        print(output)
    return 0


__all__ = [
    "ACTIVE_ALGORITHMS",
    "build_case",
    "main",
    "render_fixture",
    "write_fixture",
]


if __name__ == "__main__":
    raise SystemExit(main())
