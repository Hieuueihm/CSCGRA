#!/usr/bin/env python3
"""Software-owned M11 phase program images."""
from __future__ import annotations

import zlib
from dataclasses import replace
from typing import Any

from compiler.v3 import architecture_configuration as architecture
from compiler.v3 import context_isa as isa
from compiler.v3 import reconstruction_graphs as graphs
from compiler.v3 import scheduled_context_compiler as context_compiler


PROGRAM_ABI = {
    0: "omp",
    1: "cosamp",
    2: "iht",
    3: "htp",
    4: "sp",
    5: "gp",
    6: "gomp",
    7: "mp",
    15: "m3_control_test",
}

IHT_DEFAULT_STEP_SIZE_S27F19_RAW = 489631
HTP_DEFAULT_STEP_SIZE_S27F19_RAW = 489631

PROGRAM_NAMES = {
    0: "OMP", 1: "CoSaMP", 2: "IHT", 3: "HTP",
    4: "SP", 5: "GP", 6: "GOMP", 7: "MP",
}

QUALIFIED_PROGRAM_IDS = (0, 1, 2, 3, 4, 5, 6, 7)

PROGRAM_QUALIFICATION_EVIDENCE = {
    0: [
        "reports/v3/M11_OMP_STATUS.md",
        "reports/v3/context_images/program_00_phase.mem",
        "reports/v3/m8_vivado/summary.txt",
    ],
    1: [
        "reports/v3/M11_COSAMP_STATUS.md",
        "reports/v3/context_images/program_01_phase.mem",
        "reports/v3/m11_vivado/cosamp_phase_xsim.log",
        "reports/v3/m11_vivado/cosamp_phase_property_xsim.log",
        "reports/v3/m8_vivado/m8_xsim.log",
        "reports/v3/m8_vivado/m8_xsim_properties.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
    2: [
        "reports/v3/M11_IHT_STATUS.md",
        "reports/v3/context_images/program_02_phase.mem",
        "reports/v3/m11_vivado/iht_phase_xsim.log",
        "reports/v3/m11_vivado/iht_phase_property_xsim.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
    3: [
        "reports/v3/M11_HTP_STATUS.md",
        "reports/v3/context_images/program_03_phase.mem",
        "reports/v3/m11_vivado/htp_phase_xsim.log",
        "reports/v3/m11_vivado/htp_phase_property_xsim.log",
        "reports/v3/m8_vivado/m8_xsim.log",
        "reports/v3/m8_vivado/m8_xsim_properties.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
    4: [
        "reports/v3/M11_SP_STATUS.md",
        "reports/v3/context_images/program_04_phase.mem",
        "reports/v3/m11_vivado/sp_phase_xsim.log",
        "reports/v3/m11_vivado/sp_phase_property_xsim.log",
        "reports/v3/m8_vivado/m8_xsim.log",
        "reports/v3/m8_vivado/m8_xsim_properties.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
    5: [
        "reports/v3/M11_GP_STATUS.md",
        "reports/v3/context_images/program_05_phase.mem",
        "reports/v3/m11_vivado/gp_phase_xsim.log",
        "reports/v3/m11_vivado/gp_phase_property_xsim.log",
        "reports/v3/m8_vivado/m8_xsim.log",
        "reports/v3/m8_vivado/m8_xsim_properties.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
    6: [
        "reports/v3/M11_GOMP_STATUS.md",
        "reports/v3/context_images/program_06_phase.mem",
        "reports/v3/m11_vivado/gomp_phase_xsim.log",
        "reports/v3/m11_vivado/gomp_phase_property_xsim.log",
        "reports/v3/m8_vivado/m8_xsim.log",
        "reports/v3/m8_vivado/m8_xsim_properties.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
    7: [
        "reports/v3/M11_MP_STATUS.md",
        "reports/v3/context_images/program_07_phase.mem",
        "reports/v3/m11_vivado/mp_phase_xsim.log",
        "reports/v3/m11_vivado/mp_phase_property_xsim.log",
        "reports/v3/m8_vivado/m8_xsim.log",
        "reports/v3/m8_vivado/m8_xsim_properties.log",
        "reports/v3/m8_vivado/summary.txt",
    ],
}

PROGRAM_BLOCKERS = {}


def _launch(entry_pc: int, event_id: int) -> isa.PhaseInstruction:
    return isa.PhaseInstruction(
        operation=isa.PhaseOperation.LAUNCH_ARRAY,
        array_entry_pc=entry_pc, event_id=event_id, trace_emit=1)


def _wait(event_id: int) -> isa.PhaseInstruction:
    return isa.PhaseInstruction(
        operation=isa.PhaseOperation.WAIT_CONDITION,
        condition_select=isa.PhaseCondition.ARRAY_ROUTINE_DONE,
        event_id=event_id, trace_emit=1)


def _branch(condition: isa.PhaseCondition, target_pc: int) -> isa.PhaseInstruction:
    return isa.PhaseInstruction(
        operation=isa.PhaseOperation.BRANCH,
        condition_select=condition, target_pc=target_pc, trace_emit=1)


def _complete(stop_reason: int) -> isa.PhaseInstruction:
    return isa.PhaseInstruction(
        operation=isa.PhaseOperation.COMPLETE,
        terminal_code=stop_reason, safe_abort_point=1, trace_emit=1)


def _with_initial_array_routine(
        instructions: list[isa.PhaseInstruction],
        entry_pc: int,
        event_id: int) -> list[isa.PhaseInstruction]:
    prefix = [_launch(entry_pc, event_id), _wait(event_id)]
    rewritten = []
    for instruction in instructions:
        if instruction.operation == isa.PhaseOperation.BRANCH:
            instruction = replace(
                instruction, target_pc=instruction.target_pc + len(prefix))
        rewritten.append(instruction)
    return prefix + rewritten


def _with_residual_measure(instructions: list[isa.PhaseInstruction],
                           residual_entry_pc: int,
                           measure_entry_pc: int,
                           internal_restart_entry_pc: int | None = None
                           ) -> list[isa.PhaseInstruction]:
    expanded: list[tuple[int | None, isa.PhaseInstruction]] = []
    old_to_new: dict[int, int] = {}
    for old_pc, instruction in enumerate(instructions):
        old_to_new[old_pc] = len(expanded)
        expanded.append((old_pc, instruction))
        if (instruction.operation == isa.PhaseOperation.WAIT_CONDITION and
                old_pc > 0 and
                instructions[old_pc - 1].operation ==
                    isa.PhaseOperation.LAUNCH_ARRAY and
                instructions[old_pc - 1].array_entry_pc == residual_entry_pc and
                not (internal_restart_entry_pc is not None and
                     old_pc + 1 < len(instructions) and
                     instructions[old_pc + 1].operation ==
                         isa.PhaseOperation.LAUNCH_ARRAY and
                     instructions[old_pc + 1].array_entry_pc ==
                         internal_restart_entry_pc)):
            expanded.append((None, _launch(measure_entry_pc,
                                            instruction.event_id)))
            expanded.append((None, _wait(instruction.event_id)))
    rewritten = []
    for old_pc, instruction in expanded:
        if (old_pc is not None and
                instruction.operation == isa.PhaseOperation.BRANCH):
            instruction = replace(instruction,
                                  target_pc=old_to_new[instruction.target_pc])
        rewritten.append(instruction)
    return rewritten


def _with_refinement_restart(
        instructions: list[isa.PhaseInstruction],
        lookup: dict[str, dict[str, Any]]) -> list[isa.PhaseInstruction]:
    certificate_pc = lookup["restricted_refinement_certificate"]["entry_pc"]
    continuation_pc = lookup["restricted_refinement_continuation"]["entry_pc"]
    occurrences = []
    for pc in range(len(instructions) - 6):
        window = instructions[pc:pc + 7]
        if (window[0].operation == isa.PhaseOperation.LAUNCH_ARRAY and
                window[0].array_entry_pc == certificate_pc and
                window[1].operation == isa.PhaseOperation.WAIT_CONDITION and
                window[2].operation == isa.PhaseOperation.BRANCH and
                window[2].condition_select == isa.PhaseCondition.SOLVER_FAULT and
                window[3].operation == isa.PhaseOperation.BRANCH and
                window[3].condition_select == isa.PhaseCondition.SOLVER_CONVERGED and
                window[4].operation == isa.PhaseOperation.LAUNCH_ARRAY and
                window[4].array_entry_pc == continuation_pc and
                window[5].operation == isa.PhaseOperation.WAIT_CONDITION and
                window[6].operation == isa.PhaseOperation.BRANCH and
                window[6].condition_select == isa.PhaseCondition.ALWAYS):
            occurrences.append(pc)
    if not occurrences:
        return instructions

    insert_before = {pc + 3: pc for pc in occurrences}
    expanded: list[tuple[int | None, isa.PhaseInstruction]] = []
    old_to_new: dict[int, int] = {}
    recompute_branch_pc: dict[int, int] = {}
    for old_pc, instruction in enumerate(instructions):
        if old_pc in insert_before:
            occurrence = insert_before[old_pc]
            recompute_branch_pc[occurrence] = len(expanded)
            expanded.append((None, _branch(
                isa.PhaseCondition.SOLVER_RECOMPUTE_REQUIRED, 0)))
        old_to_new[old_pc] = len(expanded)
        expanded.append((old_pc, instruction))

    rewritten = []
    for old_pc, instruction in expanded:
        if old_pc is not None and instruction.operation == isa.PhaseOperation.BRANCH:
            instruction = replace(instruction,
                                  target_pc=old_to_new[instruction.target_pc])
        rewritten.append(instruction)

    residual_pc = lookup["residual_update"]["entry_pc"]
    residual_restart_pc = lookup[
        "restricted_refinement_restart_residual"]["entry_pc"]
    transpose_pc = lookup["restricted_refinement_transpose"]["entry_pc"]
    direction_restart_pc = lookup[
        "restricted_refinement_restart_direction"]["entry_pc"]
    for occurrence in occurrences:
        event_id = instructions[occurrence].event_id
        fault_target = old_to_new[instructions[occurrence + 2].target_pc]
        converged_target = old_to_new[instructions[occurrence + 3].target_pc]
        continuation_target = old_to_new[occurrence + 4]
        loop_target = old_to_new[instructions[occurrence + 6].target_pc]
        recompute_target = len(rewritten)
        rewritten[recompute_branch_pc[occurrence]] = _branch(
            isa.PhaseCondition.SOLVER_RECOMPUTE_REQUIRED, recompute_target)
        rewritten.extend([
            _launch(residual_pc, event_id), _wait(event_id),
            _launch(residual_restart_pc, event_id), _wait(event_id),
            _launch(transpose_pc, event_id), _wait(event_id),
            _launch(certificate_pc, event_id), _wait(event_id),
            _branch(isa.PhaseCondition.SOLVER_FAULT, fault_target),
            _branch(isa.PhaseCondition.SOLVER_CONVERGED, converged_target),
        ])
        replacement_branch_pc = len(rewritten)
        rewritten.extend([
            _branch(isa.PhaseCondition.SOLVER_REPLACEMENT_REQUIRED, 0),
            _branch(isa.PhaseCondition.ALWAYS, continuation_target),
        ])
        replacement_target = len(rewritten)
        rewritten[replacement_branch_pc] = _branch(
            isa.PhaseCondition.SOLVER_REPLACEMENT_REQUIRED,
            replacement_target)
        rewritten.extend([
            _launch(direction_restart_pc, event_id), _wait(event_id),
            _branch(isa.PhaseCondition.ALWAYS, loop_target),
        ])
    return rewritten


def _phase_crc32(words: list[int]) -> int:
    payload = b"".join(word.to_bytes(8, "little") for word in words)
    return zlib.crc32(payload) & 0xffffffff


def validate_program(program: dict[str, Any],
                     expected_architecture_hash: str | None = None) -> None:
    expected_architecture_hash = (expected_architecture_hash or
        architecture.configuration_hash(architecture.load()))
    if program["architecture_hash"] != expected_architecture_hash:
        raise ValueError("M11 program has a stale architecture hash")
    if program["context_revision"] != isa.CONTEXT_FORMAT_REVISION:
        raise ValueError("M11 program has a stale context revision")
    instructions = program["phase_instructions"]
    if program["phase_instruction_count"] != len(instructions):
        raise ValueError("M11 phase instruction count mismatch")
    if [item["pc"] for item in instructions] != list(range(len(instructions))):
        raise ValueError("M11 phase instruction addresses are not contiguous")
    words = [item["word"] for item in instructions]
    for word in words:
        isa.unpack_phase(word)
    if program["phase_crc32"] != _phase_crc32(words):
        raise ValueError("M11 phase CRC mismatch")
    for preload in program.get("scalar_preloads", []):
        if preload["address"] not in (0, 1):
            raise ValueError("M11 scalar preload address is invalid")
        value = preload["value_s27f19_raw"]
        if not -(1 << 26) <= value < (1 << 26):
            raise ValueError("M11 scalar preload does not fit signed S27F19")


def omp_program(compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "correlation", "omp_support_append_commit",
        "restricted_refinement_initialize", "phi_support_forward",
        "restricted_refinement_pre_transpose",
        "restricted_refinement_transpose",
        "restricted_refinement_certificate",
        "restricted_refinement_continuation",
        "restricted_refinement_restart_residual",
        "restricted_refinement_restart_direction",
        "htp_support_coefficient_scatter", "residual_update",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"OMP program missing resident contexts: {missing}")

    instructions = [
        _launch(lookup["correlation"]["entry_pc"], 1),
        _wait(1),
        _launch(lookup["omp_support_append_commit"]["entry_pc"], 2),
        _wait(2),
        _launch(lookup["restricted_refinement_initialize"]["entry_pc"], 3),
        _wait(3),
        _launch(lookup["phi_support_forward"]["entry_pc"], 4),
        _wait(4),
        _launch(lookup["restricted_refinement_pre_transpose"]["entry_pc"], 5),
        _wait(5),
        _launch(lookup["restricted_refinement_transpose"]["entry_pc"], 6),
        _wait(6),
        _launch(lookup["restricted_refinement_certificate"]["entry_pc"], 7),
        _wait(7),
        _branch(isa.PhaseCondition.SOLVER_FAULT, 28),
        _branch(isa.PhaseCondition.SOLVER_CONVERGED, 19),
        _launch(lookup["restricted_refinement_continuation"]["entry_pc"], 8),
        _wait(8),
        _branch(isa.PhaseCondition.ALWAYS, 6),
        _launch(lookup["htp_support_coefficient_scatter"]["entry_pc"], 9),
        _wait(9),
        _launch(lookup["residual_update"]["entry_pc"], 10),
        _wait(10),
        _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 26),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 27),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _complete(1),
        _complete(2),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.RAISE_ERROR,
            terminal_code=1, safe_abort_point=1, trace_emit=1),
    ]
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("OMP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1",
        "program_id": 0,
        "algorithm": "omp",
        "verification_only": False,
        "hardware_algorithm_decode": False,
        "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"],
        "phase_entry_pc": 0,
        "selection_k": 1,
        "scalar_preloads": [],
        "phase_instruction_count": len(words),
        "phase_crc32": _phase_crc32(words),
        "phase_instructions": [
            {"pc": pc, "word": word}
            for pc, word in enumerate(words)
        ],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {
            name: {"entry_pc": lookup[name]["entry_pc"],
                   "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})
        },
    }
    validate_program(program, compiled["architecture_hash"])
    return program

def iht_program(compiled: dict[str, Any] | None = None,
                step_size_s27f19_raw: int =
                IHT_DEFAULT_STEP_SIZE_S27F19_RAW) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "iht_dense_correlation", "vector_axpy", "topk_stream",
        "iht_support_replace", "iht_dense_rebuild", "iht_support_pack",
        "residual_update",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"IHT program missing resident contexts: {missing}")
    if step_size_s27f19_raw == 0:
        raise ValueError("IHT step size must be nonzero")

    instructions = [
        _launch(lookup["iht_dense_correlation"]["entry_pc"], 1),
        _wait(1),
        _launch(lookup["vector_axpy"]["entry_pc"], 2),
        _wait(2),
        _launch(lookup["topk_stream"]["entry_pc"], 3),
        _wait(3),
        _launch(lookup["iht_support_replace"]["entry_pc"], 4),
        _wait(4),
        _launch(lookup["iht_dense_rebuild"]["entry_pc"], 5),
        _wait(5),
        _launch(lookup["iht_support_pack"]["entry_pc"], 6),
        _wait(6),
        _launch(lookup["residual_update"]["entry_pc"], 7),
        _wait(7),
        _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 18),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 19),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _complete(1),
        _complete(2),
        _complete(3),
    ]
    instructions = _with_initial_array_routine(
        instructions, lookup["iht_dense_rebuild"]["entry_pc"], 0)
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("IHT phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1",
        "program_id": 2,
        "algorithm": "iht",
        "verification_only": False,
        "hardware_algorithm_decode": False,
        "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"],
        "phase_entry_pc": 0,
        "selection_k": "run_configuration.sparsity",
        "scalar_preloads": [{
            "address": 0,
            "value_s27f19_raw": step_size_s27f19_raw,
            "semantic": "iht_step_size",
        }],
        "phase_instruction_count": len(words),
        "phase_crc32": _phase_crc32(words),
        "phase_instructions": [
            {"pc": pc, "word": word}
            for pc, word in enumerate(words)
        ],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {
            name: {"entry_pc": lookup[name]["entry_pc"],
                   "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})
        },
    }
    validate_program(program, compiled["architecture_hash"])
    return program


def cosamp_program(compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "correlation", "cosamp_union_3k", "iht_support_pack",
        "restricted_refinement_initialize", "phi_support_forward",
        "restricted_refinement_pre_transpose",
        "restricted_refinement_transpose",
        "restricted_refinement_certificate",
        "restricted_refinement_continuation",
        "cosamp_coefficient_topk", "cosamp_prune_support",
        "htp_dense_scatter", "residual_update",
        "restricted_refinement_restart_residual",
        "restricted_refinement_restart_direction",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"CoSaMP program missing resident contexts: {missing}")

    instructions = [
        _launch(lookup["correlation"]["entry_pc"], 1),
        _wait(1),
        _launch(lookup["cosamp_union_3k"]["entry_pc"], 2),
        _wait(2),
        _launch(lookup["iht_support_pack"]["entry_pc"], 3),
        _wait(3),
        _launch(lookup["restricted_refinement_initialize"]["entry_pc"], 4),
        _wait(4),
        _launch(lookup["phi_support_forward"]["entry_pc"], 5),
        _wait(5),
        _launch(lookup["restricted_refinement_pre_transpose"]["entry_pc"], 6),
        _wait(6),
        _launch(lookup["restricted_refinement_transpose"]["entry_pc"], 7),
        _wait(7),
        _launch(lookup["restricted_refinement_certificate"]["entry_pc"], 8),
        _wait(8),
        _branch(isa.PhaseCondition.SOLVER_FAULT, 38),
        _branch(isa.PhaseCondition.SOLVER_CONVERGED, 21),
        _launch(lookup["restricted_refinement_continuation"]["entry_pc"], 9),
        _wait(9),
        _branch(isa.PhaseCondition.ALWAYS, 8),
        _launch(lookup["cosamp_coefficient_topk"]["entry_pc"], 10),
        _wait(10),
        _launch(lookup["cosamp_prune_support"]["entry_pc"], 11),
        _wait(11),
        _launch(lookup["iht_support_pack"]["entry_pc"], 12),
        _wait(12),
        _launch(lookup["htp_dense_scatter"]["entry_pc"], 13),
        _wait(13),
        _launch(lookup["residual_update"]["entry_pc"], 14),
        _wait(14),
        _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 35),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 36),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _complete(1),
        _complete(2),
        _complete(3),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.RAISE_ERROR,
            terminal_code=1, safe_abort_point=1, trace_emit=1),
    ]
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("CoSaMP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1",
        "program_id": 1,
        "algorithm": "cosamp",
        "verification_only": False,
        "hardware_algorithm_decode": False,
        "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"],
        "phase_entry_pc": 0,
        "selection_k": "run_configuration.sparsity",
        "scalar_preloads": [],
        "phase_instruction_count": len(words),
        "phase_crc32": _phase_crc32(words),
        "phase_instructions": [
            {"pc": pc, "word": word}
            for pc, word in enumerate(words)
        ],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {
            name: {"entry_pc": lookup[name]["entry_pc"],
                   "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})
        },
    }
    validate_program(program, compiled["architecture_hash"])
    return program


def htp_program(compiled: dict[str, Any] | None = None,
                step_size_s27f19_raw: int =
                HTP_DEFAULT_STEP_SIZE_S27F19_RAW) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "iht_dense_correlation", "vector_axpy", "topk_stream",
        "iht_support_replace", "iht_dense_rebuild", "iht_support_pack",
        "restricted_refinement_initialize", "phi_support_forward",
        "restricted_refinement_pre_transpose",
        "restricted_refinement_transpose",
        "restricted_refinement_certificate",
        "restricted_refinement_continuation",
        "htp_support_coefficient_scatter", "htp_dense_scatter",
        "residual_update", "htp_fresh_refinement_marker",
        "restricted_refinement_restart_residual",
        "restricted_refinement_restart_direction",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"HTP program missing resident contexts: {missing}")
    if step_size_s27f19_raw == 0:
        raise ValueError("HTP step size must be nonzero")

    instructions = [
        _launch(lookup["iht_dense_correlation"]["entry_pc"], 1),
        _wait(1),
        _launch(lookup["vector_axpy"]["entry_pc"], 2),
        _wait(2),
        _launch(lookup["topk_stream"]["entry_pc"], 3),
        _wait(3),
        _launch(lookup["iht_support_replace"]["entry_pc"], 4),
        _wait(4),
        _launch(lookup["htp_fresh_refinement_marker"]["entry_pc"], 5),
        _wait(5),
        _launch(lookup["iht_support_pack"]["entry_pc"], 6),
        _wait(6),
        _launch(lookup["restricted_refinement_restart_residual"]["entry_pc"], 7),
        _wait(7),
        _launch(lookup["restricted_refinement_transpose"]["entry_pc"], 8),
        _wait(8),
        _launch(lookup["restricted_refinement_restart_direction"]["entry_pc"], 9),
        _wait(9),
        _launch(lookup["phi_support_forward"]["entry_pc"], 10),
        _wait(10),
        _launch(lookup["restricted_refinement_pre_transpose"]["entry_pc"], 11),
        _wait(11),
        _launch(lookup["restricted_refinement_transpose"]["entry_pc"], 12),
        _wait(12),
        _launch(lookup["restricted_refinement_certificate"]["entry_pc"], 13),
        _wait(13),
        _branch(isa.PhaseCondition.SOLVER_FAULT, 44),
        _branch(isa.PhaseCondition.SOLVER_CONVERGED, 31),
        _launch(lookup["restricted_refinement_continuation"]["entry_pc"], 14),
        _wait(14),
        _branch(isa.PhaseCondition.ALWAYS, 18),
        _launch(lookup["htp_support_coefficient_scatter"]["entry_pc"], 15),
        _wait(15),
        _launch(lookup["htp_dense_scatter"]["entry_pc"], 1),
        _wait(1),
        _launch(lookup["residual_update"]["entry_pc"], 2),
        _wait(2),
        _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 41),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 42),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _complete(1),
        _complete(2),
        _complete(3),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.RAISE_ERROR,
            terminal_code=1, safe_abort_point=1, trace_emit=1),
    ]
    instructions = _with_initial_array_routine(
        instructions, lookup["iht_dense_rebuild"]["entry_pc"], 0)
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("HTP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1",
        "program_id": 3,
        "algorithm": "htp",
        "verification_only": False,
        "hardware_algorithm_decode": False,
        "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"],
        "phase_entry_pc": 0,
        "selection_k": "run_configuration.sparsity",
        "scalar_preloads": [{
            "address": 0,
            "value_s27f19_raw": step_size_s27f19_raw,
            "semantic": "htp_step_size",
        }],
        "phase_instruction_count": len(words),
        "phase_crc32": _phase_crc32(words),
        "phase_instructions": [
            {"pc": pc, "word": word}
            for pc, word in enumerate(words)
        ],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {
            name: {"entry_pc": lookup[name]["entry_pc"],
                   "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})
        },
    }
    validate_program(program, compiled["architecture_hash"])
    return program


def sp_program(compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "correlation", "iht_support_replace",
        "iht_support_pack", "restricted_refinement_initialize",
        "phi_support_forward", "restricted_refinement_pre_transpose",
        "restricted_refinement_transpose",
        "restricted_refinement_certificate",
        "restricted_refinement_continuation",
        "restricted_refinement_restart_residual",
        "restricted_refinement_restart_direction",
        "htp_support_coefficient_scatter", "htp_dense_scatter",
        "residual_update", "sp_union_2k", "cosamp_coefficient_topk",
        "sp_prune_support", "sp_proposal_coefficient_scatter",
        "sp_accept", "sp_rollback", "htp_fresh_refinement_marker",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"SP program missing resident contexts: {missing}")

    instructions: list[isa.PhaseInstruction] = []
    labels: dict[str, int] = {}
    fixups: list[tuple[int, isa.PhaseCondition, str]] = []

    def label(name: str) -> None:
        labels[name] = len(instructions)

    def launch(name: str, event_id: int) -> None:
        instructions.extend((_launch(lookup[name]["entry_pc"], event_id),
                             _wait(event_id)))

    def branch(condition: isa.PhaseCondition, target: str) -> None:
        fixups.append((len(instructions), condition, target))
        instructions.append(_branch(condition, 0))

    def refinement(prefix: str, coefficient_scatter: str,
                   first_event: int, initialize: bool = True) -> None:
        if initialize:
            launch("restricted_refinement_initialize", first_event)
        label(f"{prefix}_refine")
        launch("phi_support_forward", first_event + 1)
        launch("restricted_refinement_pre_transpose", first_event + 2)
        launch("restricted_refinement_transpose", first_event + 3)
        launch("restricted_refinement_certificate", first_event + 4)
        branch(isa.PhaseCondition.SOLVER_FAULT, "error")
        branch(isa.PhaseCondition.SOLVER_CONVERGED, f"{prefix}_refined")
        launch("restricted_refinement_continuation", first_event + 5)
        branch(isa.PhaseCondition.ALWAYS, f"{prefix}_refine")
        label(f"{prefix}_refined")
        launch(coefficient_scatter, first_event + 6)

    label("init")
    launch("htp_fresh_refinement_marker", 4)
    launch("correlation", 1)
    launch("iht_support_replace", 3)
    launch("iht_support_pack", 5)
    launch("htp_fresh_refinement_marker", 4)
    refinement("init", "htp_support_coefficient_scatter", 9)
    launch("htp_dense_scatter", 1)
    launch("residual_update", 2)

    label("iterate")
    launch("htp_fresh_refinement_marker", 4)
    launch("correlation", 1)
    launch("sp_union_2k", 2)
    launch("iht_support_pack", 3)
    refinement("proposal_2k", "sp_proposal_coefficient_scatter", 4)
    launch("cosamp_coefficient_topk", 11)
    launch("sp_prune_support", 12)
    launch("iht_support_pack", 13)
    launch("htp_dense_scatter", 14)
    launch("residual_update", 15)
    launch("restricted_refinement_restart_residual", 6)
    launch("restricted_refinement_transpose", 7)
    launch("restricted_refinement_restart_direction", 8)
    refinement("proposal_k", "sp_proposal_coefficient_scatter", 4, False)
    launch("htp_dense_scatter", 11)
    launch("residual_update", 12)
    branch(isa.PhaseCondition.RESIDUAL_DECREASED, "accept")

    label("reject")
    launch("sp_rollback", 13)
    launch("htp_dense_scatter", 14)
    launch("residual_update", 15)
    instructions.append(_complete(4))

    label("accept")
    launch("sp_accept", 13)
    branch(isa.PhaseCondition.RESIDUAL_LIMIT, "residual_stop")
    branch(isa.PhaseCondition.ITERATION_LIMIT, "iteration_stop")
    branch(isa.PhaseCondition.ALWAYS, "iterate")
    branch(isa.PhaseCondition.ALWAYS, "iterate")

    label("residual_stop")
    instructions.append(_complete(1))
    label("iteration_stop")
    instructions.append(_complete(2))
    label("support_stop")
    instructions.append(_complete(3))
    label("error")
    instructions.append(isa.PhaseInstruction(
        operation=isa.PhaseOperation.RAISE_ERROR,
        terminal_code=1, safe_abort_point=1, trace_emit=1))

    for pc, condition, target in fixups:
        instructions[pc] = _branch(condition, labels[target])
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"],
        lookup["restricted_refinement_restart_residual"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("SP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1",
        "program_id": 4,
        "algorithm": "sp",
        "verification_only": False,
        "hardware_algorithm_decode": False,
        "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"],
        "phase_entry_pc": 0,
        "selection_k": "run_configuration.sparsity",
        "scalar_preloads": [],
        "phase_instruction_count": len(words),
        "phase_crc32": _phase_crc32(words),
        "phase_instructions": [
            {"pc": pc, "word": word}
            for pc, word in enumerate(words)
        ],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {
            name: {"entry_pc": lookup[name]["entry_pc"],
                   "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})
        },
    }
    validate_program(program, compiled["architecture_hash"])
    return program

def gp_program(compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "iht_dense_correlation", "gp_top1_stream", "gp_support_policy",
        "gomp_support_union",
        "iht_support_pack",
        "gp_direction_pack", "phi_support_forward", "gp_line_search",
        "gp_update", "htp_support_coefficient_scatter",
        "htp_dense_scatter", "residual_update",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"GP program missing resident contexts: {missing}")

    instructions = [
        _launch(lookup["iht_dense_correlation"]["entry_pc"], 1),
        _wait(1),
        _launch(lookup["gp_top1_stream"]["entry_pc"], 2),
        _wait(2),
        _launch(lookup["gp_support_policy"]["entry_pc"], 3),
        _wait(3),
        _launch(lookup["iht_support_pack"]["entry_pc"], 4),
        _wait(4),
        _launch(lookup["gp_direction_pack"]["entry_pc"], 5),
        _wait(5),
        _launch(lookup["phi_support_forward"]["entry_pc"], 6),
        _wait(6),
        _launch(lookup["gp_line_search"]["entry_pc"], 7),
        _wait(7),
        _launch(lookup["gp_update"]["entry_pc"], 8),
        _wait(8),
        _launch(lookup["htp_support_coefficient_scatter"]["entry_pc"], 9),
        _wait(9),
        _launch(lookup["htp_dense_scatter"]["entry_pc"], 10),
        _wait(10),
        _launch(lookup["residual_update"]["entry_pc"], 11),
        _wait(11),
        _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 25),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 26),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _complete(1),
        _complete(2),
    ]
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("GP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1",
        "program_id": 5,
        "algorithm": "gp",
        "verification_only": False,
        "hardware_algorithm_decode": False,
        "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"],
        "phase_entry_pc": 0,
        "selection_k": 1,
        "scalar_preloads": [],
        "phase_instruction_count": len(words),
        "phase_crc32": _phase_crc32(words),
        "phase_instructions": [
            {"pc": pc, "word": word}
            for pc, word in enumerate(words)
        ],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {
            name: {"entry_pc": lookup[name]["entry_pc"],
                   "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})
        },
    }
    validate_program(program, compiled["architecture_hash"])
    return program

def gomp_program(compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "iht_dense_correlation", "gomp_top2_stream", "gomp_support_union",
        "iht_support_pack", "restricted_refinement_initialize",
        "phi_support_forward", "restricted_refinement_pre_transpose",
        "restricted_refinement_transpose", "restricted_refinement_certificate",
        "restricted_refinement_continuation",
        "htp_support_coefficient_scatter", "htp_dense_scatter",
        "residual_update",
        "restricted_refinement_restart_residual",
        "restricted_refinement_restart_direction",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"GOMP program missing resident contexts: {missing}")
    sequence = [
        "iht_dense_correlation", "gomp_top2_stream", "gomp_support_union",
        "iht_support_pack", "restricted_refinement_initialize",
        "phi_support_forward", "restricted_refinement_pre_transpose",
        "restricted_refinement_transpose", "restricted_refinement_certificate",
    ]
    instructions = []
    for event_id, name in enumerate(sequence, 1):
        instructions.extend([_launch(lookup[name]["entry_pc"], event_id),
                             _wait(event_id)])
    instructions.extend([
        _branch(isa.PhaseCondition.SOLVER_FAULT, 36),
        _branch(isa.PhaseCondition.SOLVER_CONVERGED, 23),
        _launch(lookup["restricted_refinement_continuation"]["entry_pc"], 10),
        _wait(10), _branch(isa.PhaseCondition.ALWAYS, 10),
        _launch(lookup["htp_support_coefficient_scatter"]["entry_pc"], 11),
        _wait(11), _launch(lookup["htp_dense_scatter"]["entry_pc"], 12),
        _wait(12), _launch(lookup["residual_update"]["entry_pc"], 13),
        _wait(13), _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 33),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 34),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _branch(isa.PhaseCondition.ALWAYS, 0), _complete(1), _complete(2),
        _complete(3), isa.PhaseInstruction(operation=isa.PhaseOperation.RAISE_ERROR,
            terminal_code=1, safe_abort_point=1, trace_emit=1),
    ])
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("GOMP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1", "program_id": 6,
        "algorithm": "gomp", "verification_only": False,
        "hardware_algorithm_decode": False, "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"], "phase_entry_pc": 0,
        "selection_k": 2, "scalar_preloads": [],
        "phase_instruction_count": len(words), "phase_crc32": _phase_crc32(words),
        "phase_instructions": [{"pc": pc, "word": word}
                               for pc, word in enumerate(words)],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {name: {"entry_pc": lookup[name]["entry_pc"],
            "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})},
    }
    validate_program(program, compiled["architecture_hash"])
    return program

def mp_program(compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    lookup = {item["kernel"]: item for item in
              compiled["kernels"] + compiled["resident_segments"]}
    required = {
        "iht_dense_correlation", "gp_top1_stream", "gp_support_policy",
        "iht_support_pack", "mp_direction_pack", "phi_support_forward",
        "gp_line_search", "gp_update", "htp_support_coefficient_scatter",
        "htp_dense_scatter", "residual_update",
    }
    missing = sorted(required - set(lookup))
    if missing:
        raise ValueError(f"MP program missing resident contexts: {missing}")
    sequence = [
        "iht_dense_correlation", "gp_top1_stream", "gp_support_policy",
        "iht_support_pack", "mp_direction_pack", "phi_support_forward",
        "gp_line_search", "gp_update", "htp_support_coefficient_scatter",
        "htp_dense_scatter", "residual_update",
    ]
    instructions = []
    for event_id, name in enumerate(sequence, 1):
        instructions.extend([_launch(lookup[name]["entry_pc"], event_id),
                             _wait(event_id)])
    instructions.extend([
        _branch(isa.PhaseCondition.RESIDUAL_LIMIT, 25),
        _branch(isa.PhaseCondition.ITERATION_LIMIT, 26),
        _branch(isa.PhaseCondition.ALWAYS, 0),
        _complete(1), _complete(2),
    ])
    instructions = _with_residual_measure(instructions,
        lookup["residual_update"]["entry_pc"],
        lookup["residual_measure"]["entry_pc"])
    instructions = _with_refinement_restart(instructions, lookup)
    words = [isa.pack_phase(item) for item in instructions]
    if [isa.unpack_phase(word) for word in words] != instructions:
        raise ValueError("MP phase instruction round-trip failed")
    program = {
        "schema": "cscgra-v3-m11-program-image-v1", "program_id": 7,
        "algorithm": "mp", "verification_only": False,
        "hardware_algorithm_decode": False, "software_defined_context": True,
        "architecture_hash": compiled["architecture_hash"],
        "context_revision": compiled["context_revision"], "phase_entry_pc": 0,
        "selection_k": 1, "scalar_preloads": [],
        "phase_instruction_count": len(words), "phase_crc32": _phase_crc32(words),
        "phase_instructions": [{"pc": pc, "word": word}
                               for pc, word in enumerate(words)],
        "array_context_count": compiled["array_context_count"],
        "array_context_ranges": {name: {"entry_pc": lookup[name]["entry_pc"],
            "context_count": lookup[name]["context_count"]}
            for name in sorted(required | {"residual_measure"})},
    }
    validate_program(program, compiled["architecture_hash"])
    return program

def payload() -> dict[str, Any]:
    configuration = architecture.load()
    compiled = context_compiler.payload()
    programs = [omp_program(compiled), cosamp_program(compiled), iht_program(compiled),
                htp_program(compiled), sp_program(compiled), gp_program(compiled),
                gomp_program(compiled), mp_program(compiled)]
    return {
        "schema": "cscgra-v3-m11-program-library-v1",
        "architecture_hash": architecture.configuration_hash(configuration),
        "context_revision": isa.CONTEXT_FORMAT_REVISION,
        "program_abi": {str(key): value for key, value in PROGRAM_ABI.items()},
        "scalar_preload_contract": {
            "ownership": "software_program_image",
            "hardware_algorithm_decode": False,
            "register_count": 2,
            "value_format": "signed_S27F19_raw_sign_extended_to_ACC62",
            "load_time": "after_active_configuration_before_first_array_launch",
        },
        "implemented_program_ids": list(QUALIFIED_PROGRAM_IDS),
        "programs": programs,
    }

def readiness_payload(library: dict[str, Any] | None = None,
                      compiled: dict[str, Any] | None = None) -> dict[str, Any]:
    library = library or payload()
    compiled = compiled or context_compiler.payload()
    context_compiler.validate_compiled(compiled)
    programs = {item["program_id"]: item for item in library["programs"]}
    implemented = set(library["implemented_program_ids"])
    callable_targets = sorted(item["kernel"] for item in
                              compiled["kernels"] + compiled["resident_segments"])
    ready_lowerings = {
        0: {
            "CORR": {"kind": "array_ddg", "target": "correlation"},
            "SELECT": {"kind": "fused_or_resident_override",
                       "target": "correlation"},
            "APPEND": {"kind": "resident_segment",
                       "target": "omp_support_append_commit"},
            "LS": {"kind": "resident_sequence", "targets": [
                "restricted_refinement_initialize", "phi_support_forward",
                "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
        1: {
            "CORR": {"kind": "array_ddg", "target": "correlation"},
            "IDENTIFY_2K": {"kind": "fused_or_resident_override",
                             "target": "correlation"},
            "UNION_3K": {"kind": "resident_segment",
                          "target": "cosamp_union_3k"},
            "LS_3K": {"kind": "resident_sequence", "targets": [
                "iht_support_pack", "restricted_refinement_initialize",
                "phi_support_forward", "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation"]},
            "PRUNE_K": {"kind": "resident_sequence", "targets": [
                "cosamp_coefficient_topk", "cosamp_prune_support",
                "iht_support_pack", "htp_dense_scatter"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
        2: {
            "CORR": {"kind": "resident_segment",
                     "target": "iht_dense_correlation"},
            "GRADIENT_STEP": {"kind": "resident_segment",
                              "target": "vector_axpy"},
            "TOP_K": {"kind": "resident_sequence", "targets": [
                "topk_stream", "iht_support_replace", "iht_dense_rebuild",
                "iht_support_pack"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
        3: {
            "CORR": {"kind": "resident_segment",
                     "target": "iht_dense_correlation"},
            "GRADIENT_STEP": {"kind": "resident_segment",
                              "target": "vector_axpy"},
            "TOP_K": {"kind": "resident_sequence", "targets": [
                "topk_stream", "iht_support_replace", "iht_support_pack"]},
            "LS": {"kind": "resident_sequence", "targets": [
                "restricted_refinement_initialize", "phi_support_forward",
                "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation",
                "htp_support_coefficient_scatter", "htp_dense_scatter"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
        4: {
            "INIT_CORR": {"kind": "array_ddg", "target": "correlation"},
            "INIT_TOP_K": {"kind": "resident_segment", "target": "topk_stream"},
            "INIT_LS_K": {"kind": "resident_sequence", "targets": [
                "iht_support_replace", "iht_support_pack",
                "restricted_refinement_initialize", "phi_support_forward",
                "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation"]},
            "INIT_RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
            "CORR": {"kind": "array_ddg", "target": "correlation"},
            "TOP_K": {"kind": "fused_or_resident_override", "target": "correlation"},
            "UNION_2K": {"kind": "resident_segment", "target": "sp_union_2k"},
            "LS_2K": {"kind": "resident_sequence", "targets": [
                "iht_support_pack", "restricted_refinement_initialize",
                "phi_support_forward", "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation",
                "sp_proposal_coefficient_scatter"]},
            "PRUNE_K": {"kind": "resident_sequence", "targets": [
                "cosamp_coefficient_topk", "sp_prune_support"]},
            "LS_K": {"kind": "resident_sequence", "targets": [
                "iht_support_pack", "restricted_refinement_initialize",
                "phi_support_forward", "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation",
                "sp_proposal_coefficient_scatter"]},
            "RESIDUAL_CHECK": {"kind": "array_ddg", "target": "residual_update"},
            "NON_DECREASE": {"kind": "resident_sequence", "targets": [
                "sp_rollback", "htp_dense_scatter", "residual_update"]},
        },
        5: {
            "CORR": {"kind": "resident_sequence", "targets": [
                "iht_dense_correlation", "gp_top1_stream"]},
            "SUPPORT": {"kind": "resident_segment", "target": "gp_support_policy"},
            "DIRECTION": {"kind": "resident_sequence", "targets": [
                "iht_support_pack", "gp_direction_pack"]},
            "PHI_DIRECTION": {"kind": "array_ddg", "target": "phi_support_forward"},
            "LINE_SEARCH": {"kind": "resident_segment", "target": "gp_line_search"},
            "UPDATE": {"kind": "resident_sequence", "targets": [
                "gp_update", "htp_support_coefficient_scatter",
                "htp_dense_scatter"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
        6: {
            "CORR": {"kind": "resident_segment",
                     "target": "iht_dense_correlation"},
            "TOP_L": {"kind": "resident_segment",
                      "target": "gomp_top2_stream"},
            "APPEND": {"kind": "resident_segment",
                       "target": "gomp_support_union"},
            "LS": {"kind": "resident_sequence", "targets": [
                "iht_support_pack", "restricted_refinement_initialize",
                "phi_support_forward", "restricted_refinement_pre_transpose",
                "restricted_refinement_transpose",
                "restricted_refinement_certificate",
                "restricted_refinement_continuation",
                "htp_support_coefficient_scatter", "htp_dense_scatter"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
        7: {
            "CORR": {"kind": "resident_segment",
                     "target": "iht_dense_correlation"},
            "ARGMAX": {"kind": "resident_segment",
                       "target": "gp_top1_stream"},
            "RANK1_UPDATE": {"kind": "resident_sequence", "targets": [
                "gp_support_policy", "iht_support_pack", "mp_direction_pack",
                "phi_support_forward", "gp_line_search", "gp_update",
                "htp_support_coefficient_scatter", "htp_dense_scatter"]},
            "RESIDUAL": {"kind": "array_ddg", "target": "residual_update"},
        },
    }
    cfgs = graphs.build_phase_cfgs()
    readiness = []
    for program_id, algorithm in PROGRAM_NAMES.items():
        packaged = program_id in programs
        ready = program_id in implemented
        phases = []
        for node in cfgs[algorithm].nodes:
            control_only = node.routine in {"residual_stop", "commit_result"}
            lowering = ({"kind": "control_only"} if control_only else
                        ready_lowerings.get(program_id, {}).get(node.name,
                            {"kind": "unpackaged"}))
            callable_phase = ready or control_only
            phases.append({
                "phase": node.name,
                "routine": node.routine,
                "lowering": lowering,
                "hardware_callable": callable_phase,
                "blocker": None if callable_phase else
                    "program-specific lowering not packaged",
            })
        program = programs.get(program_id)
        blockers = [] if ready else [
            *PROGRAM_BLOCKERS.get(program_id, []),
            *([] if packaged else ["software phase image not packaged"]),
        ]
        readiness.append({
            "program_id": program_id,
            "algorithm": algorithm,
            "status": "READY" if ready else "BLOCKED",
            "hardware_algorithm_decode": False,
            "software_defines_context": True,
            "phase_image_packaged": packaged,
            "phase_crc32": program["phase_crc32"] if program else None,
            "qualification_evidence": PROGRAM_QUALIFICATION_EVIDENCE.get(
                program_id, []),
            "blockers": blockers,
            "phases": phases,
        })
    return {
        "schema": "cscgra-v3-m11-program-readiness-v1",
        "context_revision": compiled["context_revision"],
        "array_context_count": compiled["array_context_count"],
        "callable_targets": callable_targets,
        "implemented_program_ids": library["implemented_program_ids"],
        "programs": readiness,
    }


def mem_files(library: dict[str, Any] | None = None) -> dict[str, str]:
    library = library or payload()
    result = {}
    for program in library["programs"]:
        words = [item["word"] for item in program["phase_instructions"]]
        result[f"program_{program['program_id']:02d}_phase.mem"] = "".join(
            f"{word:09x}\n" for word in words)
    return result
