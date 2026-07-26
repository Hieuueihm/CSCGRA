#!/usr/bin/env python3
"""One-time, behavior-preserving extraction of large embedded RTL blocks.

The script is intentionally idempotent.  It keeps generated lookup logic and
secondary module definitions close to their owner while making the hand-written
controller/service files small enough to review.
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "CSCGRA.srcs" / "sources_1" / "new"


def extract_lfsr_jump() -> None:
    controller = RTL / "sparse_loop_controller.v"
    header = RTL / "sparse_loop_lfsr_jump.vh"
    include = '`include "sparse_loop_lfsr_jump.vh"'
    text = controller.read_text(encoding="utf-8")

    if include in text:
        if not header.exists():
            raise RuntimeError(f"{controller}: include exists but {header} is missing")
        return

    start_marker = "function [31:0] lfsr_jump_padded;"
    start = text.index(start_marker)
    end = text.index("endfunction", start) + len("endfunction")
    function_text = text[start:end]

    header_text = (
        "// Generated LFSR jump lookup used only by sparse_loop_controller.\n"
        "// Kept separate so the controller state machine remains reviewable.\n\n"
        f"{function_text}\n"
    )
    header.write_text(header_text, encoding="utf-8", newline="\n")
    controller.write_text(
        text[:start] + include + text[end:],
        encoding="utf-8",
        newline="\n",
    )


def extract_support_set_service() -> None:
    engine = RTL / "sparse_kernel_service_engine.v"
    header = RTL / "support_set_service.vh"
    include = '`include "support_set_service.vh"'
    text = engine.read_text(encoding="utf-8")

    if include in text:
        if not header.exists():
            raise RuntimeError(f"{engine}: include exists but {header} is missing")
        return

    marker = "\nmodule support_set_service #("
    start = text.index(marker) + 1
    module_text = text[start:].rstrip() + "\n"
    header_text = (
        "`ifndef CSCGRA_SUPPORT_SET_SERVICE_VH\n"
        "`define CSCGRA_SUPPORT_SET_SERVICE_VH\n\n"
        "// Support-set storage and update service used by the sparse kernel.\n"
        f"{module_text}\n"
        "`endif\n"
    )
    header.write_text(header_text, encoding="utf-8", newline="\n")
    engine.write_text(
        text[:start].rstrip() + f"\n\n{include}\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    extract_lfsr_jump()
    extract_support_set_service()
    print("RTL layout refactor is present")


if __name__ == "__main__":
    main()
