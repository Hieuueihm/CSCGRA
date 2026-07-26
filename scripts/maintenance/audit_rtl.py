#!/usr/bin/env python3
"""Report RTL modules and internal modules that are not instantiated."""

from __future__ import annotations

import argparse
import pathlib
import re


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", choices=("v1", "v2"), default="v2")
    args = parser.parse_args()

    repo = pathlib.Path(__file__).resolve().parents[2]
    rtl_root = repo / "rtl" / args.version
    rtl_files = sorted(rtl_root.rglob("*.v")) + sorted(rtl_root.rglob("*.vh"))
    texts = {path: path.read_text(errors="ignore") for path in rtl_files}

    modules: dict[str, pathlib.Path] = {}
    for path, text in texts.items():
        for match in re.finditer(
            r"(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b", text
        ):
            modules[match.group(1)] = path

    instances: list[tuple[str, pathlib.Path, int]] = []
    for path, text in texts.items():
        stripped = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        stripped = re.sub(r"//.*", "", stripped)
        for module in modules:
            pattern = re.compile(
                r"(?m)^\s*"
                + re.escape(module)
                + r"\s*(?:#\s*\(|[A-Za-z_][A-Za-z0-9_$]*\s*\()"
            )
            for match in pattern.finditer(stripped):
                nearby = stripped[max(0, match.start() - 20) : match.start() + 50]
                if re.search(
                    r"(?m)^\s*module\s+" + re.escape(module) + r"\b", nearby
                ):
                    continue
                line = stripped.count("\n", 0, match.start()) + 1
                instances.append((module, path, line))

    used = {module for module, _, _ in instances}
    print(f"RTL_VERSION={args.version}")
    print(f"RTL_FILES={len(rtl_files)}")
    print(f"MODULES={len(modules)}")
    print("DEFINED_NOT_INSTANTIATED")
    uninstantiated = 0
    for module, path in sorted(modules.items()):
        if module not in used and module not in ("cgra_soc_top", "cgra_top"):
            uninstantiated += 1
            print(f"{module}\t{path.relative_to(repo)}")
    print(f"UNINSTANTIATED_INTERNAL={uninstantiated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
