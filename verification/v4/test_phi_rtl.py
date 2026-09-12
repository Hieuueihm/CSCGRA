"""Compile real RTL and compare both sides of every edge with the integer oracle."""

from __future__ import annotations

import hashlib
import random
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources
from models.v4.phi_stream import ABI, ADDR_W, BANKS, ROOT, TAGS, PhiCycleModel, lane_mask, sign_word
from scripts.v4.generate_phi_interface import render

RUNS: list[dict] = []
COMMANDS: list[dict] = []
RTL = {
    "g": ROOT / "rtl/v4/operator/phi_sign_generator.sv",
    "c": ROOT / "rtl/v4/memory/phi_sign_cache.sv",
}


def port_map(path: Path) -> dict[str, tuple[str, int]]:
    text = path.read_text(encoding="utf-8")
    defs = dict(re.findall(r"`define (CSR_PHI_\w+) (\d+)$", render(), re.M))
    text = re.sub(r"`(CSR_PHI_\w+)", lambda match: defs.get(match[1], match[0]), text)
    ports = {}
    for direction, size, name in re.findall(r"(input|output)\s+(?:wire|reg)\s*(?:\[([^:]+):0\])?\s*(\w+)\s*[,\)]", text):
        if size and not re.fullmatch(r"[0-9*+ -]+", size):
            raise ValueError("unexpected width expression")
        width = int(eval(size, {"__builtins__": {}})) + 1 if size else 1
        ports[name] = direction, width
    if "clk" not in ports or "fault_code" not in ports:
        raise ValueError("RTL port parser did not find the module interface")
    return ports


PORTS = {prefix: port_map(path) for prefix, path in RTL.items()}
INPUTS = {"rst": 1, "link": 1, "link_gate": 1}
OUTPUTS = {}
for prefix, ports in PORTS.items():
    for name, (direction, width) in ports.items():
        if name not in ("clk", "rst"):
            (INPUTS if direction == "input" else OUTPUTS)[prefix + "_" + name] = width


def bench_source() -> str:
    lines = ["`timescale 1ns/1ps", "module tb_phi;", "reg clk = 0;"]
    for name, width in INPUTS.items():
        lines.append(f"reg [{width - 1}:0] {name} = 0;")
    for name, width in OUTPUTS.items():
        lines.append(f"wire [{width - 1}:0] {name};")
    for prefix, ports in PORTS.items():
        connections = []
        for name, (direction, _) in ports.items():
            signal = name if name in ("clk", "rst") else prefix + "_" + name
            if prefix == "g" and name == "out_ready":
                signal = "link ? (c_fill_ready && link_gate) : g_out_ready"
            elif prefix == "c" and name.startswith("fill_") and direction == "input":
                field = name[5:]
                linked = "(g_out_valid && link_gate)" if field == "valid" else "g_out_" + field
                signal = f"link ? {linked} : {signal}"
            connections.append(f".{name}({signal})")
        lines.append(f"{RTL[prefix].stem} {prefix}_dut (" + ", ".join(connections) + ");")
    lines += ["integer src, dst, count, cycle;", "reg [4095:0] src_path, dst_path;", "initial begin",
              'if (!$value$plusargs("src=%s", src_path)) $fatal(1, "missing input");',
              'if (!$value$plusargs("dst=%s", dst_path)) $fatal(1, "missing output");',
              'src = $fopen(src_path, "r"); dst = $fopen(dst_path, "w");',
              'if (!src || !dst) $fatal(1, "cannot open vector files");', "cycle = 0;", "while (!$feof(src)) begin"]
    fmt = " ".join(["%h"] * len(INPUTS))
    lines.append(f'count = $fscanf(src, "{fmt}", ' + ", ".join(INPUTS) + ");")
    lines.append(f"if (count == {len(INPUTS)}) begin")
    for phase in (0, 1):
        lines.append("#4;" if phase == 0 else "clk = 1; #1;")
        fmt = " ".join(["%h"] * len(OUTPUTS))
        lines.append(f'$fdisplay(dst, "%0d {phase} {fmt}", cycle, ' + ", ".join(OUTPUTS) + ");")
    lines += ["#4; clk = 0; cycle = cycle + 1; end",
              'else if (!$feof(src)) $fatal(1, "bad vector row");',
              'end $fclose(src); $fclose(dst); $display("PASS cycles=%0d", cycle); $finish; end',
              'initial begin #10000000; $fatal(1, "timeout"); end', "endmodule", ""]
    return "\n".join(lines)


class Scenario:
    def __init__(self, seed: int) -> None:
        self.rng = random.Random(seed)
        self.model = PhiCycleModel()
        self.pins = dict.fromkeys(INPUTS, 0)
        self.rows: list[dict[str, int]] = []
        self.expected: list[dict[str, int]] = []
        self.step(rst=1)
        self.step(rst=0)

    def step(self, **changes: int) -> None:
        self.pins.update(changes)
        for name, value in self.pins.items():
            if not 0 <= value < 1 << INPUTS[name]:
                raise ValueError(f"{name} does not fit: {value}")
        self.rows.append(self.pins.copy())
        self.expected.append(self.model.outputs(self.pins) if len(self.rows) > 1 else {})
        self.model.tick(self.pins)
        self.expected.append(self.model.outputs(self.pins))

    def desc(self, rows: int, cols: int, seed: int = 1, prefix: str = "g_start") -> dict[str, int]:
        values = {"rows": rows, "columns": cols, "job_tag": 0xB123, "op_tag": 0x5678,
                  "format_tag": 0x9A, "generation": 0xFEDCBA98}
        if prefix == "g_start":
            values.update(seed=seed, family=ABI["family"], revision=ABI["generator_revision"])
        else:
            values["key"] = 0x123456789ABCDEF0FEDCBA9876543210
        return {prefix + "_" + name: value for name, value in values.items()}

    def start(self, rows: int, cols: int, seed: int, linked: bool = False) -> None:
        values = self.desc(rows, cols, seed)
        values.update(g_start_valid=1, g_out_ready=0, link=int(linked), link_gate=0,
                      c_rd_valid=0, c_begin_valid=int(linked), c_fill_valid=0)
        if linked:
            values.update(self.desc(rows, cols, prefix="c_begin"))
        self.step(**values)
        self.step(g_start_valid=0, c_begin_valid=0)

    def drain(self, linked: bool = False, random_stall: bool = True) -> None:
        cycles = 0
        while self.model.gen["busy"]:
            ready = int(not random_stall or self.rng.randrange(4) != 0)
            self.step(g_out_ready=ready, link_gate=ready,
                      g_start_seed=self.rng.getrandbits(32), g_start_job_tag=self.rng.getrandbits(16))
            cycles += 1
            if cycles > 30000:
                raise AssertionError("oracle drain timeout")
        if not random_stall and cycles != self.model.gen["cols"] * self.model.gen["blocks"]:
            raise AssertionError("unstalled fill did not match the published schedule")
        self.step(g_out_ready=0, link_gate=0)
        if linked and not self.model.cache["valid"]:
            raise AssertionError("valid stream did not publish")

    def read(self, mask: int, addresses: list[int], generation: int | None = None, stalls: int = 0) -> None:
        cache = self.model.cache
        self.step(c_rd_valid=1, c_rd_bank_mask=mask,
                  c_rd_addresses=sum(addr << (bank * ADDR_W) for bank, addr in enumerate(addresses)),
                  c_rd_generation=cache["generation"] if generation is None else generation,
                  c_rd_tag=self.rng.getrandbits(16), c_rsp_ready=0)
        for _ in range(stalls):
            self.step(c_rd_valid=1, c_rd_addresses=self.rng.getrandbits(BANKS * ADDR_W),
                      c_rd_tag=self.rng.getrandbits(16))
        self.step(c_rd_valid=0, c_rsp_ready=1)
        self.step(c_rsp_ready=0)


class PhiRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        header = ROOT / "rtl/v4/include/phi_interface.vh"
        if header.read_text(encoding="utf-8") != render():
            raise RuntimeError("stale generated Phi interface")
        work = ROOT / "work"
        work.mkdir(exist_ok=True)
        cls.tmp = tempfile.TemporaryDirectory(prefix="v4_phi_", dir=work)
        cls.run_dir = Path(cls.tmp.name)
        cls.bench = cls.run_dir / "tb_phi.sv"
        cls.bench.write_text(bench_source(), encoding="utf-8")
        cls.exe = cls.run_dir / "phi.xsim.json"
        result = compile_rtl(cls.exe, "tb_phi", filelist_sources(ROOT)+[cls.bench], root=ROOT)
        COMMANDS.extend(result.commands)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        cls.compile_output = result.stdout + result.stderr

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def replay(self, scenario: Scenario) -> None:
        name = self._testMethodName
        source = self.run_dir / (name + ".hex")
        trace = self.run_dir / (name + ".trace")
        payload = "".join(" ".join(f"{row[field]:x}" for field in INPUTS) + "\n" for row in scenario.rows)
        source.write_text(payload, encoding="ascii")
        result = run_rtl(self.exe, ["+src="+source.as_posix(), "+dst="+trace.as_posix()], root=ROOT)
        COMMANDS.extend(result.commands)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS cycles={len(scenario.rows)}", result.stdout)
        lines = trace.read_text(encoding="ascii").splitlines()
        self.assertEqual(len(lines), len(scenario.expected))
        checked = 0
        for index, (line, expected) in enumerate(zip(lines, scenario.expected)):
            fields = line.split()
            self.assertEqual([int(fields[0]), int(fields[1])], [index // 2, index % 2])
            actual = dict(zip(OUTPUTS, fields[2:]))
            for signal, value in expected.items():
                self.assertNotRegex(actual[signal], "[xz]", f"unknown {signal} at edge {index // 2}")
                self.assertEqual(int(actual[signal], 16), value,
                                 f"{name} edge={index // 2} phase={index % 2} signal={signal}")
                checked += 1
        RUNS.append({"test": name, "cycles": len(scenario.rows), "signal_checks": checked,
                     "vectors_sha256": hashlib.sha256(payload.encode("ascii")).hexdigest(),
                     "trace_sha256": hashlib.sha256(trace.read_bytes()).hexdigest(), "status": "PASS", "commands": result.commands})

    def test_generator_shapes_seeds_and_stalls(self) -> None:
        scenario = Scenario(101)
        for rows in range(1, 129):
            scenario.start(rows, 3 + rows % 9, (0, 1, 0xFFFFFFFF, 0x12345678)[rows % 4])
            scenario.drain()
        scenario.start(128, 1024, 0)
        scenario.drain(random_stall=False)
        scenario.start(1, 1, 0xFFFFFFFF)
        scenario.drain()
        self.replay(scenario)

    def test_generator_fault_reset_abort_and_priority(self) -> None:
        scenario = Scenario(211)
        for field, value in (("rows", 0), ("rows", 129), ("columns", 0), ("columns", 1025),
                             ("family", 0), ("revision", 3)):
            values = scenario.desc(37, 9)
            values["g_start_" + field] = value
            scenario.step(g_start_valid=1, **values)
            scenario.step(g_start_valid=0)
            scenario.step()
        for cancel in ("rst", "g_cancel"):
            for transfers in (0, 1, 5):
                scenario.start(37, 9, 47)
                for _ in range(transfers):
                    scenario.step(g_out_ready=1)
                for _ in range(3):
                    scenario.step(g_out_ready=0, g_start_valid=1, **scenario.desc(1, 1))
                scenario.step(**{cancel: 1}, g_out_ready=1)
                scenario.step(**{cancel: 0}, g_start_valid=0)
                scenario.step()
        scenario.start(1, 1, 1)
        scenario.step(g_start_valid=1, g_out_ready=1, **scenario.desc(3, 2, 101))
        scenario.step(g_out_ready=0)
        scenario.step(g_start_valid=0)
        scenario.drain()
        self.replay(scenario)

    def test_linked_fill_full_cache_and_banked_reads(self) -> None:
        scenario = Scenario(307)
        for rows, cols, seed in ((128, 1024, 0), (37, 17, 509), (1, 9, 0xFFFFFFFF),
                                 (32, 8, 1), (33, 7, 211), (65, 1024, 47),
                                 (96, 17, 23), (127, 19, 997)):
            scenario.start(rows, cols, seed, linked=True)
            scenario.step(c_rd_valid=1, c_rd_bank_mask=255)
            scenario.drain(linked=True)
            scenario.step(c_rd_valid=0, c_rsp_ready=1)
            scenario.step(c_rsp_ready=0)
            blocks = (rows + 31) // 32
            for group in range((cols + 7) // 8):
                mask = (1 << min(8, cols - group * 8)) - 1
                for block in range(blocks):
                    scenario.read(mask, [group * blocks + block] * 8, stalls=scenario.rng.randrange(4))
            for _ in range(20):
                mask = scenario.rng.randrange(1, 1 << min(8, cols))
                addresses = []
                for bank in range(8):
                    groups = (cols + 7 - bank) // 8
                    addresses.append(scenario.rng.randrange(max(1, groups * blocks)))
                scenario.read(mask, addresses, stalls=4)
        self.replay(scenario)

    def test_cache_descriptor_fill_faults_and_recovery(self) -> None:
        scenario = Scenario(401)
        for rows, cols in ((0, 1), (129, 1), (1, 0), (1, 1025)):
            scenario.step(c_begin_valid=1, **scenario.desc(rows, cols, prefix="c_begin"))
            scenario.step(c_begin_valid=0, c_rd_valid=1, c_fill_valid=1)
        scenario.step(c_rd_valid=0, c_fill_valid=0)
        fields = ("column", "row_block", "mask", "signs", *TAGS, "last")
        for field in fields:
            scenario.step(c_begin_valid=1, **scenario.desc(3, 2, prefix="c_begin"))
            scenario.step(c_begin_valid=0)
            values = {"column": 0, "row_block": 0, "mask": 7,
                      "signs": sign_word(1, 3, 0, 0), "last": 0}
            values.update({tag: scenario.model.cache[tag] for tag in TAGS})
            values[field] ^= 8 if field == "signs" else 1
            scenario.step(c_fill_valid=1, **{"c_fill_" + name: value for name, value in values.items()})
            scenario.step(c_fill_valid=0)
            scenario.step()
        for variant in ("duplicate", "missing_last"):
            scenario.step(c_begin_valid=1, **scenario.desc(3, 2, prefix="c_begin"))
            scenario.step(c_begin_valid=0)
            values = {"column": 0, "row_block": 0, "mask": 7, "signs": 5, "last": 0}
            values.update({tag: scenario.model.cache[tag] for tag in TAGS})
            scenario.step(c_fill_valid=1, **{"c_fill_" + name: value for name, value in values.items()})
            scenario.step(c_fill_column=0 if variant == "duplicate" else 1)
            scenario.step(c_fill_valid=0)
        scenario.start(37, 9, 101, linked=True)
        scenario.drain(linked=True)
        scenario.read(255, [0] * 8)
        self.replay(scenario)

    def test_cache_read_faults_hold_and_begin_priority(self) -> None:
        scenario = Scenario(503)
        scenario.start(37, 9, 997, linked=True)
        scenario.drain(linked=True)
        scenario.read(0, [0] * 8, stalls=3)
        scenario.read(255, [0] * 8, generation=0, stalls=5)
        scenario.read(2, [2] * 8, stalls=3)
        scenario.read(1, [511] * 8, stalls=3)
        scenario.read(255, [0] * 8, stalls=4)
        scenario.step(c_rd_valid=1, c_rd_bank_mask=1, c_rd_addresses=0,
                      c_rd_generation=scenario.model.cache["generation"], c_rsp_ready=0)
        scenario.step(c_begin_valid=1, **scenario.desc(1, 1, prefix="c_begin"))
        scenario.step(c_rsp_ready=1)
        scenario.step(c_rsp_ready=0)
        scenario.step(c_begin_valid=0, c_rd_valid=0, c_invalidate=1)
        scenario.step(c_invalidate=0)
        scenario.start(1, 1, 1, linked=True)
        scenario.drain(linked=True)
        scenario.step(c_begin_valid=1, c_rd_valid=1, **scenario.desc(2, 2, prefix="c_begin"))
        scenario.step(c_begin_valid=0, c_rd_valid=0, c_invalidate=1)
        scenario.step(c_invalidate=0)
        self.replay(scenario)

    def test_linked_cancel_refill_and_stalled_response_reset(self) -> None:
        scenario = Scenario(601)
        for reset in (True, False):
            for stage in ("first", "mid", "final", "response"):
                scenario.start(33, 9, 0, linked=True)
                transfers = {"first": 0, "mid": 5, "final": 17, "response": 18}[stage]
                for _ in range(transfers):
                    scenario.step(link_gate=1)
                scenario.step(link_gate=0)
                if stage == "response":
                    scenario.step(c_rd_valid=1, c_rd_bank_mask=255, c_rd_addresses=0,
                                  c_rd_generation=scenario.model.cache["generation"], c_rsp_ready=0)
                    scenario.step(c_rd_valid=0)
                scenario.step(rst=int(reset), g_cancel=int(not reset), c_invalidate=int(not reset),
                              link_gate=1, c_rsp_ready=1)
                scenario.step(rst=0, g_cancel=0, c_invalidate=0, link_gate=0, c_rsp_ready=0, c_rd_valid=0)
                scenario.step()
                scenario.start(3, 2, 0x12345678, linked=True)
                scenario.drain(linked=True)
                scenario.read(3, [0] * 8, stalls=2)
        self.replay(scenario)


if __name__ == "__main__":
    unittest.main()
