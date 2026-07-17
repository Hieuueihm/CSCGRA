from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

SNR_TB = ROOT / "tests/tb_noisy24_k8_rep_final.v"
SNR_C_FILES = [
    (ROOT / "sdk_app/src/main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c", "SNR LS C"),
]
SWEEP_TB = ROOT / "tests/run1/tb_run1_k_sweep.v"
NOISY_MU_TB = ROOT / "tests/tb_soc_program_noisy24_mu.v"
NOISY_MU_VH = ROOT / "tests/noisy_lfsr_24bit_cases.vh"
NOISY_MU_GP_JSON = Path(r"D:/vivado_pj/analysis/reconstruction_quality_noisy24/noisy_lfsr_24bit_gp_grad_step_fixed_k16_seed434.json")
SWEEP_C_FILES = [
    (ROOT / "sdk_app/src/main_tb_soc_program_k_sweep_all_ls_serial_write.c", "sweep LS C"),
]
SWEEP_H = ROOT / "sdk_app/src/cscgra_k_sweep_golden.h"
SWEEP_VH = ROOT / "tests/run1/k_sweep_golden_mu3.vh"

ALG_ORDER = ["OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"]
SWEEP_CASES = [
    (64, 256, 16),
    (64, 256, 8),
    (64, 256, 4),
    (32, 128, 8),
    (32, 128, 4),
    (32, 128, 2),
    (16, 64, 4),
    (16, 64, 2),
]

errors = []
warnings = []


def read(path: Path) -> str:
    if not path.exists():
        errors.append(f"missing file: {path}")
        return ""
    return path.read_text(errors="replace")


def require(cond: bool, msg: str):
    if not cond:
        errors.append(msg)


def warn(cond: bool, msg: str):
    if not cond:
        warnings.append(msg)


def find_first(pattern: str, text: str):
    return re.search(pattern, text, re.S)


def find_alg_map_sv(text: str):
    match = re.search(
        r"localparam\s+ALG_OMP\s*=\s*(\d+)\s*,\s*"
        r"ALG_COSAMP\s*=\s*(\d+)\s*,\s*"
        r"ALG_IHT\s*=\s*(\d+)\s*,\s*"
        r"ALG_HTP\s*=\s*(\d+)\s*,\s*"
        r"ALG_SP\s*=\s*(\d+)\s*,\s*"
        r"ALG_GP\s*=\s*(\d+)\s*,\s*"
        r"ALG_GOMP\s*=\s*(\d+)\s*,\s*"
        r"ALG_MP\s*=\s*(\d+)",
        text,
    )
    return tuple(map(int, match.groups())) if match else None


def find_alg_map_c(text: str):
    names = ["OMP", "COSAMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"]
    vals = []
    for name in names:
        match = re.search(rf"#define\s+ALG_{name}\s+(\d+)U", text)
        if not match:
            return None
        vals.append(int(match.group(1)))
    return tuple(vals)


def check_snr_file(c_path: Path, label: str):
    tb = read(SNR_TB)
    c = read(c_path)
    require("localparam M=64; localparam N=256; localparam K=8;" in tb, "SNR TB is not M64/N256/K8")
    require("NOISY24_CASE = m64n256k8" in c, f"{label} label is not m64n256k8")
    require("noisy_lfsr_24bit_per_algorithm_seed_k8_gp_scaled.json" in c, f"{label} source tag is not GP-scaled K8 JSON")
    require(find_alg_map_sv(tb) == (0, 1, 2, 3, 4, 5, 6, 7), "SNR TB alg map unexpected")
    require(find_alg_map_c(c) == (0, 1, 2, 3, 4, 5, 6, 7), f"{label} alg map unexpected")
    for name in ALG_ORDER:
        require(f'"{name}"' in c, f"{label} missing alg name {name}")
    for token in ["SOP_REFINE_SPARSE", "SOP_CORR", "SOP_IHT_UPDATE", "SOP_PRUNE_X", "SOP_GRAD_STEP", "SOP_MP_UPDATE"]:
        require(token in c, f"{label} missing opcode token {token}")

    gp_c = find_first(r"case\s+ALG_GP:\s*(.*?)\s*break;", c)
    require(gp_c is not None, f"{label} missing GP case block")
    if gp_c is not None:
        gp_c_block = gp_c.group(1)
        for token in [
            "emit_select_append(&pc);",
            "sparse_op_ctx(SOP_GRAD_STEP, 0)",
            "candidate_meta_depth_ctx(0U, 0U, 0)",
            "emit_reduce_append_loop(&pc, reduce_x_ctx(0), candidate_append_path_ctx(0U, 0), (uint8_t)NOISY24_K, 1U);",
            "sparse_op_ctx(SOP_PRUNE_X, 0)",
            "sparse_op_ctx(SOP_RESID, 0)",
        ]:
            require(token in gp_c_block, f"{label} GP block missing {token}")

    require(
        "ALG_GP: begin emit_select_append(); write_ctx(pc[10:0],sparse_op_ctx(SOP_GRAD_STEP,0)); pc=pc+1; write_ctx(pc[10:0],candidate_meta_depth_ctx(0,0,0)); pc=pc+1; emit_reduce_append_loop(reduce_x_ctx(0),candidate_append_path_ctx(0,0),K); write_ctx(pc[10:0],sparse_op_ctx(SOP_PRUNE_X,0)); pc=pc+1; write_ctx(pc[10:0],sparse_op_ctx(SOP_RESID,0)); pc=pc+1; end" in tb,
        "SNR TB GP block does not match grad-step program shape",
    )


def check_snr():
    for c_path, label in SNR_C_FILES:
        check_snr_file(c_path, label)


def check_sweep_file(c_path: Path, label: str):
    tb = read(SWEEP_TB)
    c = read(c_path)
    h = read(SWEEP_H)
    vh = read(SWEEP_VH)
    require(bool(vh), "sweep VH missing or empty")
    require("CSCGRA_opt_architecture_opt2/tests/run1/k_sweep_golden_mu3.vh" in h, "sweep C header source tag is not opt2/run1")
    require(
        "KSWEEP_CASES = {m64n256k16, m64n256k8, m64n256k4, m32n128k8, m32n128k4, m32n128k2, m16n64k4, m16n64k2}" in c,
        f"{label} case label does not match expected case list",
    )
    for idx, (m_val, n_val, k_val) in enumerate(SWEEP_CASES):
        require(f"{idx}=({m_val},{n_val},{k_val})" in tb, f"sweep TB missing case {idx}=({m_val},{n_val},{k_val})")
    require(find_alg_map_c(c) == (0, 1, 2, 3, 4, 5, 6, 7), f"{label} alg map unexpected")
    require(
        "(iter_count == 16U) && ((alg == ALG_COSAMP) || (alg == ALG_SP))" in c,
        f"{label} missing K=16 CoSaMP/SP skip",
    )
    require(
        "requires_2K_candidate_support" in c and "requires_2K_candidate_support" in tb,
        f"{label} skip reason not mirrored in C/TB",
    )
    require("run_rc == 2" in c, f"{label} skip return is counted as pass/fail instead of ignored")
    require("KSGOLD_ALG_COUNT 8U" in h, "sweep header alg count is not 8")
    require("KSGOLD_CASE_COUNT 8U" in h, "sweep header case count is not 8")
    warn("Auto-generated" in vh or "Auto-generated" in h, "sweep golden/header does not include auto-generated marker")

    gp_c = find_first(r"case\s+ALG_GP:\s*(.*?)\s*break;", c)
    require(gp_c is not None, f"{label} missing GP case block")
    if gp_c is not None:
        gp_c_block = gp_c.group(1)
        for token in [
            "emit_select_append(&pc);",
            "sparse_op_ctx(SOP_GRAD_STEP, 0)",
            "candidate_meta_depth_ctx(0U, 0U, 0)",
            "emit_reduce_append_loop(&pc, reduce_x_ctx(0), candidate_append_path_ctx(0U, 0), (uint8_t)iter_count, 1U);",
            "sparse_op_ctx(SOP_PRUNE_X, 0)",
            "sparse_op_ctx(SOP_RESID, 0)",
        ]:
            require(token in gp_c_block, f"{label} GP block missing {token}")

    require(
        "ALG_5: begin emit_select_append(pc); write_ctx(pc,sparse_op_ctx(SOP_GRAD_STEP,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(0,0,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_x_ctx(0),candidate_append_path_ctx(0,0),k_param,1); write_ctx(pc,sparse_op_ctx(SOP_PRUNE_X,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_RESID,0)); pc=pc+1; end" in tb,
        "sweep TB GP block does not match grad-step program shape",
    )


def check_noisy_mu():
    tb = read(NOISY_MU_TB)
    vh = read(NOISY_MU_VH)
    gp_json = read(NOISY_MU_GP_JSON)
    require("ALG_IHT: noisy_alg_iter_max = 64;" in tb, "noisy_mu IHT does not run 64 iterations to match golden")
    require("ALG_HTP: noisy_alg_iter_max = 64;" in tb, "noisy_mu HTP does not run 64 iterations to match golden")
    require("ALG_5: noisy_alg_iter_max = 32;" in tb, "noisy_mu GP does not run 32 gradient-step iterations to match golden")
    require("ALG_6: noisy_alg_iter_max = 8;" in tb, "noisy_mu GOMP must run 8 iterations for K=16 with group size 2")
    require("ALG_MP: noisy_alg_iter_max = 64;" in tb, "noisy_mu MP does not run 64 iterations to match golden")
    require("SKIP_CASE alg=%0d reason=requires_2K_candidate_support_at_K16" in tb, "noisy_mu missing CoSaMP/SP K16 skip reason")
    require("SOP_GRAD_STEP" in tb and "SOP_GP_NO_LS_UPDATE" not in tb, "noisy_mu GP is not using SOP_GRAD_STEP cleanly")
    require("axi_write(REG_MU_SHIFT,32'd3)" in tb, "noisy_mu must use the same MU_SHIFT=3 as k_sweep/reference TBs")
    require("ALG_5: begin emit_select_append(pc); write_ctx(pc,sparse_op_ctx(SOP_GRAD_STEP,0)); pc=pc+1; write_ctx(pc,candidate_meta_depth_ctx(0,0,0)); pc=pc+1; emit_reduce_append_loop(pc,reduce_x_ctx(0),candidate_append_path_ctx(0,0),8'd16,1); write_ctx(pc,sparse_op_ctx(SOP_PRUNE_X,0)); pc=pc+1; write_ctx(pc,sparse_op_ctx(SOP_RESID,0)); pc=pc+1; end" in tb, "noisy_mu GP block does not match grad-step program shape")
    require("NOISY_GP_SEED = 434" in vh, "noisy_mu GP seed is not locked to seed 434")
    require("GP golden override: Python fixed-point grad-step reference seed434" in vh, "noisy_mu GP golden source marker is missing seed434 Python fixed-point grad-step reference")
    require("noisy_lfsr_24bit_gp_grad_step_fixed_k16_seed434.json" in vh, "noisy_mu GP golden marker does not point to seed434 JSON")
    require('"algorithm": "GP_grad_step_scaled_fixed_rtl_phi"' in gp_json, "noisy_mu GP JSON is not tagged as GP_grad_step_scaled_fixed_rtl_phi")
    require('"x_seed": 434' in gp_json, "noisy_mu GP JSON seed is not 434")
    require('"mu_shift": 3' in gp_json, "noisy_mu GP JSON mu_shift is not 3")
    require('"iters": 32' in gp_json, "noisy_mu GP JSON iteration count is not 32")
    require('"support_overlap": "16/16"' in gp_json, "noisy_mu GP JSON support overlap is not 16/16")

def check_sweep():
    for c_path, label in SWEEP_C_FILES:
        check_sweep_file(c_path, label)


def main():
    check_snr()
    check_noisy_mu()
    check_sweep()
    print("SDK/TB sync check")
    print(f"ROOT={ROOT}")
    if warnings:
        print("WARNINGS:")
        for item in warnings:
            print(f"  - {item}")
    if errors:
        print("FAIL:")
        for item in errors:
            print(f"  - {item}")
        return 1
    print("PASS: SNR K8, noisy_mu TB, and k-sweep SDK C mirror the checked TB/golden invariants, including ls_serial_write copies.")
    return 0


if __name__ == "__main__":
    sys.exit(main())








