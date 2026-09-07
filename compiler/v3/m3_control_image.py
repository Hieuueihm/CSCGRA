#!/usr/bin/env python3
"""Generate the deterministic M3 control-spine image and cycle trace."""
from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v3 import context_isa as isa


ARRAY_CONTEXT_COUNT = 7
PHASE_INSTRUCTION_COUNT = 5


def _control(**values: int) -> isa.ArrayControlContext:
    return isa.ArrayControlContext(**values)


def _array_contexts() -> list[tuple[isa.ArrayControlContext,
                                    isa.StreamContext,
                                    isa.ResourceContext]]:
    contexts = [
        (_control(next_pc_mode=isa.NextPcMode.SEQUENTIAL,
                  cluster_enable_mask=0b11, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext()),
        (_control(next_pc_mode=isa.NextPcMode.SEQUENTIAL,
                  cluster_enable_mask=0b11),
         isa.StreamContext(
             vector_read_a_enable=1,
             external_a_select=isa.ExternalStreamSource.VECTOR_A,
             advance_vector_streams=1,
             stall_on_input=1),
         isa.ResourceContext()),
        (_control(next_pc=2, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                  loop_counter_select=0, loop_counter_increment=1,
                  loop_limit_select=isa.LoopLimitSource.IMMEDIATE,
                  loop_limit_immediate=3, cluster_enable_mask=0b11,
                  guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext()),
        (_control(next_pc=4, next_pc_mode=isa.NextPcMode.WAIT_EVENT,
                  predicate_select=2, cluster_enable_mask=0b11),
         isa.StreamContext(), isa.ResourceContext()),
        (_control(next_pc=6,
                  next_pc_mode=isa.NextPcMode.PREDICATE_SELECT,
                  predicate_select=1, cluster_enable_mask=0b11,
                  guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext()),
        (_control(next_pc=6, next_pc_mode=isa.NextPcMode.JUMP,
                  cluster_enable_mask=0b11, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext()),
        (_control(next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
                  cluster_enable_mask=0b11, routine_done=1,
                  safe_abort_point=1, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext()),
    ]
    for control, stream, resource in contexts:
        isa.validate_context_bundle(control, stream, resource)
        assert isa.unpack_array_control(isa.pack_array_control(control)) == control
        assert isa.unpack_stream(isa.pack_stream(stream)) == stream
        assert isa.unpack_resource(isa.pack_resource(resource)) == resource
    return contexts


def _phase_instructions() -> list[isa.PhaseInstruction]:
    instructions = [
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.LAUNCH_ARRAY,
            array_entry_pc=0, event_id=3, trace_emit=1),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.WAIT_CONDITION,
            condition_select=isa.PhaseCondition.ARRAY_ROUTINE_DONE,
            event_id=3, trace_emit=1),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.BRANCH,
            condition_select=isa.PhaseCondition.SUPPORT_STABLE,
            target_pc=4, trace_emit=1),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.NOP, trace_emit=1),
        isa.PhaseInstruction(
            operation=isa.PhaseOperation.COMPLETE,
            terminal_code=2, safe_abort_point=1, trace_emit=1),
    ]
    for instruction in instructions:
        assert isa.unpack_phase(isa.pack_phase(instruction)) == instruction
    return instructions


def _memory_configuration() -> isa.MemoryConfiguration:
    configuration = isa.MemoryConfiguration(
        base_word_address=0,
        element_count=32,
        element_stride_words=1,
        bank_base=0,
        bank_count_log2=3,
        bank_mode=isa.BankMode.CYCLIC,
        element_format=isa.ElementFormat.DATA18,
        packing_mode=isa.PackingMode.FOUR,
        read_enable=1,
        write_enable=1,
        memory_space=isa.MemorySpace.VECTOR_SCRATCHPAD,
    )
    assert isa.unpack_memory_configuration(
        isa.pack_memory_configuration(configuration)) == configuration
    return configuration


def payload() -> dict:
    contexts = _array_contexts()
    phases = _phase_instructions()
    array_words = []
    for pc, (control, stream, resource) in enumerate(contexts):
        array_words.append({
            "pc": pc,
            "tile_words": [isa.pack_tile(isa.TileContext())] * 16,
            "array_control_word": isa.pack_array_control(control),
            "stream_word": isa.pack_stream(stream),
            "resource_word": isa.pack_resource(resource),
        })

    # Relative cycle zero is the launch handshake.  The context RAM response is
    # visible one cycle later.  The environment releases each elastic wait
    # after exactly two stalled cycles.
    expected_events = [
        (1, 0, "commit", "guaranteed"),
        (2, 1, "stall", "elastic_stream"),
        (3, 1, "stall", "elastic_stream"),
        (4, 1, "commit", "elastic"),
        (5, 2, "commit", "guaranteed_loop_1"),
        (6, 2, "commit", "guaranteed_loop_2"),
        (7, 2, "commit", "guaranteed_loop_3"),
        (8, 3, "stall", "elastic_event"),
        (9, 3, "stall", "elastic_event"),
        (10, 3, "commit", "elastic"),
        (11, 4, "commit", "guaranteed_branch_false"),
        (12, 5, "commit", "guaranteed_jump"),
        (13, 6, "commit", "guaranteed_return"),
    ]
    return {
        "schema": "cscgra-v3-m3-control-image-v2",
        "context_format_revision": isa.CONTEXT_FORMAT_REVISION,
        "phase_entry_pc": 0,
        "algorithm_binding": "software_defined_context",
        "array_context_count": len(contexts),
        "phase_instruction_count": len(phases),
        "array_contexts": array_words,
        "phase_instructions": [
            {"pc": pc, "word": isa.pack_phase(instruction)}
            for pc, instruction in enumerate(phases)
        ],
        "memory_configurations": [
            {"id": 0, "word": isa.pack_memory_configuration(
                _memory_configuration())}
        ],
        "normal_array_trace": [
            {"relative_cycle": cycle, "pc": pc, "event": event,
             "reason": reason}
            for cycle, pc, event, reason in expected_events
        ],
        "normal_phase_trace": [0, 1, 2, 3, 4],
        "normal_terminal_stop_reason": 2,
    }


def _hex(width: int, value: int) -> str:
    digits = (width + 3) // 4
    return f"{width}'h{value:0{digits}x}"


def sv_include() -> str:
    image = payload()
    contexts = image["array_contexts"]
    phases = image["phase_instructions"]
    events = image["normal_array_trace"]
    lines = [
        "`ifndef M3_CONTROL_IMAGE_VH",
        "`define M3_CONTROL_IMAGE_VH",
        "// Generated by compiler/v3/m3_control_image.py. Do not edit.",
        f"localparam integer M3_ARRAY_CONTEXT_COUNT = {len(contexts)};",
        f"localparam integer M3_PHASE_INSTRUCTION_COUNT = {len(phases)};",
        f"localparam integer M3_EXPECTED_ARRAY_EVENT_COUNT = {len(events)};",
        "function automatic [71:0] m3_generated_image_word;",
        "    input [3:0] plane;",
        "    input [7:0] address;",
        "    begin",
        "        m3_generated_image_word = 72'd0;",
        "        case (plane)",
        "            4'd8: begin",
        "                case (address)",
    ]
    for context in contexts:
        word = (context["stream_word"] << 36) | context["array_control_word"]
        lines.append(
            f"                    8'd{context['pc']}: "
            f"m3_generated_image_word = {_hex(72, word)};")
    lines.extend([
        "                    default: m3_generated_image_word = 72'd0;",
        "                endcase",
        "            end",
        "            4'd9: begin",
        "                case (address)",
    ])
    for context in contexts:
        lines.append(
            f"                    8'd{context['pc']}: "
            f"m3_generated_image_word = "
            f"{{36'd0, {_hex(36, context['resource_word'])}}};")
    lines.extend([
        "                    default: m3_generated_image_word = 72'd0;",
        "                endcase",
        "            end",
        "            4'd10: begin",
        "                case (address)",
    ])
    for phase in phases:
        lines.append(
            f"                    8'd{phase['pc']}: "
            f"m3_generated_image_word = "
            f"{{36'd0, {_hex(36, phase['word'])}}};")
    lines.extend([
        "                    default: m3_generated_image_word = 72'd0;",
        "                endcase",
        "            end",
        "            default: m3_generated_image_word = 72'd0;",
        "        endcase",
        "    end",
        "endfunction",
        "",
        "function automatic [7:0] m3_expected_array_pc;",
        "    input integer event_index;",
        "    begin",
        "        case (event_index)",
    ])
    for index, event in enumerate(events):
        lines.append(
            f"            {index}: m3_expected_array_pc = 8'd{event['pc']};")
    lines.extend([
        "            default: m3_expected_array_pc = 8'hff;",
        "        endcase",
        "    end",
        "endfunction",
        "",
        "function automatic m3_expected_array_commit;",
        "    input integer event_index;",
        "    begin",
        "        case (event_index)",
    ])
    for index, event in enumerate(events):
        value = 1 if event["event"] == "commit" else 0
        lines.append(
            f"            {index}: m3_expected_array_commit = 1'b{value};")
    lines.extend([
        "            default: m3_expected_array_commit = 1'b0;",
        "        endcase",
        "    end",
        "endfunction",
        "",
        "function automatic [7:0] m3_expected_array_relative_cycle;",
        "    input integer event_index;",
        "    begin",
        "        case (event_index)",
    ])
    for index, event in enumerate(events):
        lines.append(
            f"            {index}: m3_expected_array_relative_cycle = "
            f"8'd{event['relative_cycle']};")
    lines.extend([
        "            default: m3_expected_array_relative_cycle = 8'hff;",
        "        endcase",
        "    end",
        "endfunction",
        "",
        f"localparam [63:0] M3_MEMORY_CONFIGURATION_0 = "
        f"{_hex(64, image['memory_configurations'][0]['word'])};",
        "`endif",
        "",
    ])
    return "\n".join(lines)


def generate() -> None:
    report_path = ROOT / "reports" / "v3" / "m3_control_image.json"
    include_path = (ROOT / "verification" / "v3" / "m3" / "generated" /
                    "m3_control_image.vh")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    include_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(payload(), indent=2, sort_keys=True) + "\n",
                           encoding="utf-8", newline="\n")
    include_path.write_text(sv_include(), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    generate()
    print("generated M3 control image and cycle trace")
