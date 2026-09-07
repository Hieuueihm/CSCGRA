#!/usr/bin/env python3
"""Generate the directed full M10 refinement transaction golden."""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v3 import context_isa as isa
from models.v3.hardware import Arithmetic, Events, NumericProfile

OUTPUT = ROOT / "verification" / "v3" / "m10" / "generated" / "m10_full_refinement_golden.vh"


def bits(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def stream(**kwargs: int) -> int:
    return isa.pack_stream(isa.StreamContext(**kwargs))


def resource(**kwargs: int) -> int:
    return isa.pack_resource(isa.ResourceContext(**kwargs))


def main() -> None:
    arithmetic = Arithmetic(NumericProfile(), Events())
    solver_one = 1 << arithmetic.p.solver_f
    measurement_count = 32
    p = [3 * solver_one, solver_one]
    x = [0, 0]
    d_value = p[1] - p[0]
    gamma = sum(value * value for value in p)
    delta = measurement_count * d_value * d_value
    alpha = arithmetic.solver_div(gamma, delta)
    residual_initial = arithmetic.solver_mul(d_value, alpha)
    x_next = [arithmetic.solver(value + arithmetic.solver_mul(direction, alpha))
              for value, direction in zip(x, p)]
    residual_next = [arithmetic.solver(residual_initial -
                                      arithmetic.solver_mul(d_value, alpha))
                     for _ in range(measurement_count)]
    g_next = [sum(residual_next), -sum(residual_next)]
    gamma_next = sum(value * value for value in g_next)

    contexts = {
        "STREAM_PHI_FORWARD_START": stream(
            phi_command=isa.PhiStreamCommand.START, phi_configuration_id=41,
            stall_on_input=1),
        "STREAM_PHI_FORWARD_BODY": stream(
            vector_read_a_enable=1, vector_configuration_a=19,
            external_a_select=isa.ExternalStreamSource.SCALAR_BROADCAST,
            phi_command=isa.PhiStreamCommand.CONSUME,
            advance_vector_streams=1, stall_on_input=1),
        "STREAM_PHI_FORWARD_WRITE": stream(
            vector_write_enable=1, vector_configuration_write=16,
            advance_vector_streams=1, stall_on_output=1),
        "STREAM_PHI_TRANSPOSE_START": stream(
            phi_command=isa.PhiStreamCommand.START, phi_configuration_id=42,
            stall_on_input=1),
        "STREAM_PHI_TRANSPOSE_BODY": stream(
            vector_read_a_enable=1, vector_configuration_a=20,
            external_a_select=isa.ExternalStreamSource.VECTOR_A,
            phi_command=isa.PhiStreamCommand.CONSUME,
            advance_vector_streams=1, stall_on_input=1),
        "STREAM_PHI_TRANSPOSE_WRITE": stream(
            vector_write_enable=1, vector_configuration_write=18,
            advance_vector_streams=1, stall_on_output=1),
        "STREAM_PHI_STOP": stream(phi_command=isa.PhiStreamCommand.STOP),
        "RESOURCE_RESTART_A": resource(
            configuration_id=1, stream_boundary=isa.StreamBoundary.FIRST),
        "RESOURCE_RESTART_ABW": resource(
            configuration_id=7, stream_boundary=isa.StreamBoundary.FIRST),
        "RESOURCE_TRANSPOSE_REDUCE": resource(
            operation=isa.ResourceOperation.REDUCE_SUM,
            input_select=isa.ResourceInput.CLUSTER_REDUCTION,
            output_select=isa.ResourceOutput.MEMORY_STREAM,
            configuration_id=18, lane_mask=0xf, clear_before=1,
            accumulate=1, commit_after=1, wait_for_ready=1),
        "RESOURCE_TRANSPOSE_WAIT": resource(
            operation=isa.ResourceOperation.REDUCE_SUM,
            output_select=isa.ResourceOutput.MEMORY_STREAM,
            wait_for_result=1),
    }

    lines = [
        "`ifndef M10_FULL_REFINEMENT_GOLDEN_VH",
        "`define M10_FULL_REFINEMENT_GOLDEN_VH",
        "// Generated from models/v3/hardware.py and compiler/v3/context_isa.py.",
        f"`define M10_MEASUREMENT_COUNT 9'd{measurement_count}",
        "`define M10_SUPPORT_COUNT 7'd2",
        "`define M10_D_BASE 9'd12",
        "`define M10_X_BASE 9'd20",
        "`define M10_G_BASE 9'd26",
        "`define M10_P_BASE 9'd32",
        "`define M10_R_BASE 9'd38",
        f"`define M10_P0 27'h{bits(p[0], 27):07x}",
        f"`define M10_P1 27'h{bits(p[1], 27):07x}",
        f"`define M10_D 27'h{bits(d_value, 27):07x}",
        f"`define M10_R_INITIAL 27'h{bits(residual_initial, 27):07x}",
        f"`define M10_X0_NEXT 27'h{bits(x_next[0], 27):07x}",
        f"`define M10_X1_NEXT 27'h{bits(x_next[1], 27):07x}",
        f"`define M10_GAMMA 62'h{bits(gamma, 62):016x}",
        f"`define M10_DELTA 62'h{bits(delta, 62):016x}",
        f"`define M10_ALPHA 27'h{bits(alpha, 27):07x}",
        f"`define M10_GAMMA_NEXT 62'h{bits(gamma_next, 62):016x}",
        "`define M10_FORWARD_CYCLES 16'd45",
        "`define M10_ARITHMETIC_CYCLES 16'd45",
        "`define M10_TRANSPOSE_CYCLES 16'd35",
        "`define M10_TRANSACTION_CYCLES 16'd143",
    ]
    for name, word in contexts.items():
        lines.append(f"`define M10_{name} 36'h{word:09x}")
    lines.extend(["`endif", ""])
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
