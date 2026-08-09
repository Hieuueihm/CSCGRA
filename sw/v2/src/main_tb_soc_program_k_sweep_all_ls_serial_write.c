#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtime_l.h"
#include <stdint.h>
#include "cscgra_k_sweep_golden.h"

#ifndef XPAR_CGRA_0_S_AXI_CONTROL_BASEADDR
#ifdef XPAR_CGRA_SOC_TOP_0_S_AXI_CONTROL_BASEADDR
#define XPAR_CGRA_0_S_AXI_CONTROL_BASEADDR XPAR_CGRA_SOC_TOP_0_S_AXI_CONTROL_BASEADDR
#elif defined(XPAR_CSCGRA_SOC_BD_CGRA_0_S_AXI_CONTROL_BASEADDR)
#define XPAR_CGRA_0_S_AXI_CONTROL_BASEADDR XPAR_CSCGRA_SOC_BD_CGRA_0_S_AXI_CONTROL_BASEADDR
#else
#define XPAR_CGRA_0_S_AXI_CONTROL_BASEADDR 0xA0000000U
#endif
#endif

#define CGRA_BASE       XPAR_CGRA_0_S_AXI_CONTROL_BASEADDR

#define REG_CTRL        0x000U
#define REG_STATUS      0x004U
#define REG_M_SIZE      0x00CU
#define REG_N_SIZE      0x010U
#define REG_K_PARAM     0x014U
#define REG_Y_DDR       0x018U
#define REG_X_DDR       0x01CU
#define REG_SEED        0x020U
#define REG_PHI_SCALE   0x024U
#define REG_FLAGS       0x030U
#define REG_PROG_BASE   0x040U
#define REG_PROG_LEN    0x044U
#define REG_RESULT0     0x050U
#define REG_CYCLE_CNT   0x054U
#define REG_PC_DBG      0x058U
#define REG_MU_SHIFT    0x070U
#define REG_CTX_BASE    0x100U

#define STATUS_DONE     (1U << 0)
#define STATUS_BUSY     (1U << 1)
#define STATUS_ERROR    (1U << 3)
#define STATUS_ERRCODE_SHIFT 4U

#define VEC_X           0U
#define VEC_R           1U
#define VEC_Y           2U

#define SOP_REFINE          0x80U
#define SOP_CORR            0x81U
#define SOP_IHT_UPDATE      0x82U
#define SOP_RESID           0x83U
#define SOP_PRUNE_X         0x84U
#define SOP_MP_UPDATE       0x85U
#define SOP_REFINE_SPARSE   0x86U
#define SOP_GRAD_STEP       0x87U
#define SOP_CORR_UPDATE     0x88U

#define ALG_OMP     0U
#define ALG_COSAMP  1U
#define ALG_IHT     2U
#define ALG_HTP     3U
#define ALG_SP      4U
#define ALG_GP      5U
#define ALG_GOMP    6U
#define ALG_MP      7U

#define CTX_AXI_WORD_LIMIT 2048U

static const char * const tb_alg_names[8] = {
    "OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"
};

static uint32_t y_buf[KSGOLD_MAX_M] __attribute__((aligned(64)));
static uint32_t x_buf[KSGOLD_MAX_N] __attribute__((aligned(64)));
static volatile uint32_t ctx_write_overflow;
static uint32_t ctx_loop_count;
static uint32_t pass_cnt;
static uint32_t fail_cnt;
static uint32_t run_pass_cnt;
static uint32_t run_fail_cnt;

static inline void cgra_write(uint32_t off, uint32_t value)
{
    Xil_Out32(CGRA_BASE + off, value);
}

static inline uint32_t cgra_read(uint32_t off)
{
    return Xil_In32(CGRA_BASE + off);
}

static void cgra_write_ctx(uint32_t idx, uint64_t word)
{
    if (idx >= CTX_AXI_WORD_LIMIT) {
        ctx_write_overflow = 1U;
        return;
    }
    if (((word >> 56) & 0x0fULL) == 9ULL && ((word >> 40) & 0x0fULL) == 3ULL) {
        ++ctx_loop_count;
    }
    cgra_write(REG_CTX_BASE + (idx << 3), (uint32_t)(word & 0xffffffffULL));
    cgra_write(REG_CTX_BASE + (idx << 3) + 4U, (uint32_t)(word >> 32));
}

static uint64_t sparse_op_ctx(uint8_t sparse_op, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 8ULL << 56;
    w |= ((uint64_t)sparse_op) << 20;
    if (is_last) w |= 6ULL << 44;
    return w;
}

static uint64_t reduce_argmax_ctx(int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 4ULL << 56;
    w |= 1ULL << 52;
    w |= 2ULL << 48;
    if (is_last) w |= 6ULL << 44;
    w |= 3ULL << 41;
    w |= 3ULL << 32;
    w |= 4ULL << 24;
    return w;
}

static uint64_t reduce_argmax_mp_ctx(int is_last)
{
    uint64_t w = reduce_argmax_ctx(is_last);
    w &= ~(7ULL << 32);
    return w;
}

static uint64_t reduce_x_ctx(int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 4ULL << 56;
    w |= 1ULL << 52;
    w |= 2ULL << 48;
    if (is_last) w |= 6ULL << 44;
    w |= 0ULL << 41;
    w |= 3ULL << 32;
    w |= 4ULL << 24;
    return w;
}

static uint64_t reduce_x_support_ctx(int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 4ULL << 56;
    w |= 1ULL << 52;
    w |= 2ULL << 48;
    if (is_last) w |= 6ULL << 44;
    w |= 0ULL << 41;
    w |= 4ULL << 32;
    w |= 4ULL << 24;
    return w;
}

static uint64_t stream_topk_ctx(uint8_t path, uint8_t count, int exclude_support, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 5ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= 1ULL << 31;
    w |= ((uint64_t)(exclude_support ? 2U : 1U)) << 24;
    w |= ((uint64_t)(path & 7U)) << 20;
    w |= ((uint64_t)(count & 0x1fU)) << 11;
    return w;
}

static uint64_t post_update_x_topk_ctx(uint8_t path, uint8_t count, int is_last)
{
    uint64_t w = stream_topk_ctx(path, count, 0, is_last);
    w |= 1ULL << 30; /* retain the reduce-x behavior for quantized tiny values */
    w |= 1ULL << 29; /* select the post-update x producer */
    return w;
}

static uint64_t candidate_append_result_ctx(int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 6ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= 1ULL << 16;
    return w;
}

static uint64_t candidate_append_path_ctx(uint8_t path, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 6ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= ((uint64_t)(path & 7U)) << 20;
    w |= 9ULL << 16;
    return w;
}

static uint64_t candidate_meta_depth_ctx(uint8_t path, uint8_t depth, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 6ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= ((uint64_t)(path & 7U)) << 20;
    w |= 4ULL << 16;
    w |= ((uint64_t)(depth & 0x1fU)) << 11;
    return w;
}

static uint64_t candidate_select_path_ctx(uint8_t path, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 6ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= ((uint64_t)(path & 7U)) << 20;
    w |= 6ULL << 16;
    return w;
}

static uint64_t candidate_merge_path_ctx(uint8_t path, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 6ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= ((uint64_t)(path & 7U)) << 20;
    w |= 2ULL << 16;
    return w;
}

static uint64_t candidate_copy_to_p0_ctx(uint8_t path, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 6ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= ((uint64_t)(path & 7U)) << 20;
    w |= 14ULL << 16;
    return w;
}

static uint64_t dma_ctx(uint8_t vec_id, uint8_t addr_dim, int ddr_write, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 7ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= ((uint64_t)(vec_id & 7U)) << 41;
    w |= ((uint64_t)(addr_dim & 0xfU)) << 28;
    if (ddr_write) w |= 1ULL;
    return w;
}

static uint64_t ctrl_loop_rel_ctx(int8_t rel_off, uint8_t count, uint8_t loop_id, int is_last)
{
    uint64_t w = 0;
    w |= 1ULL << 60;
    w |= 9ULL << 56;
    if (is_last) w |= 6ULL << 44;
    w |= 3ULL << 40;
    w |= ((uint64_t)((uint8_t)rel_off & 0x3fU)) << 28;
    w |= ((uint64_t)count) << 20;
    w |= ((uint64_t)(loop_id & 3U)) << 18;
    return w;
}

static void emit_select_append(uint32_t *pc)
{
    cgra_write_ctx((*pc)++, stream_topk_ctx(0U, 1U, 1, 0));
    cgra_write_ctx((*pc)++, sparse_op_ctx(SOP_CORR, 0));
}

static void emit_mp_select_append(uint32_t *pc)
{
    cgra_write_ctx((*pc)++, sparse_op_ctx(SOP_CORR, 0));
    cgra_write_ctx((*pc)++, reduce_argmax_mp_ctx(0));
    cgra_write_ctx((*pc)++, candidate_append_result_ctx(0));
}

static void emit_reduce_append_loop(uint32_t *pc, uint64_t reduce_word, uint64_t append_word, uint8_t count, uint8_t loop_id)
{
    cgra_write_ctx((*pc)++, reduce_word);
    cgra_write_ctx((*pc)++, append_word);
    cgra_write_ctx((*pc)++, ctrl_loop_rel_ctx(-2, count, loop_id, 0));
}

static void emit_loop_tail(uint32_t *pc, uint32_t body_start, uint8_t count, uint8_t loop_id)
{
    if (count > 1U) {
        int32_t rel = (int32_t)body_start - (int32_t)(*pc);
        cgra_write_ctx((*pc)++, ctrl_loop_rel_ctx((int8_t)rel, count, loop_id, 0));
    }
}

static uint32_t golden_alg_idx(uint32_t tb_alg)
{
    return tb_alg;
}

static uint32_t build_program(uint32_t alg, uint32_t iter_count)
{
    uint32_t pc = 0;
    uint32_t body_start = 0;

    cgra_write_ctx(pc++, dma_ctx(VEC_X, 0U, 0, 0));
    cgra_write_ctx(pc++, dma_ctx(VEC_R, 1U, 0, 0));
    cgra_write_ctx(pc++, dma_ctx(VEC_Y, 1U, 0, 0));

    body_start = pc;
    switch (alg) {
    case ALG_OMP:
        emit_select_append(&pc);
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE_SPARSE, 0));
        break;
    case ALG_COSAMP:
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_CORR, 0));
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(1U, 0U, 0));
        cgra_write_ctx(pc++, candidate_select_path_ctx(1U, 0));
        emit_reduce_append_loop(&pc, reduce_argmax_ctx(0), candidate_append_path_ctx(1U, 0), (uint8_t)(iter_count << 1), 1U);
        cgra_write_ctx(pc++, candidate_select_path_ctx(1U, 0));
        cgra_write_ctx(pc++, candidate_merge_path_ctx(0U, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE, 0));
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(1U, 0U, 0));
        cgra_write_ctx(pc++, candidate_select_path_ctx(1U, 0));
        emit_reduce_append_loop(&pc, reduce_x_support_ctx(0), candidate_append_path_ctx(1U, 0), (uint8_t)iter_count, 1U);
        cgra_write_ctx(pc++, candidate_copy_to_p0_ctx(1U, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE, 0));
        break;
    case ALG_IHT:
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_CORR_UPDATE, 0));
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(0U, 0U, 0));
        emit_reduce_append_loop(&pc, reduce_x_ctx(0), candidate_append_path_ctx(0U, 0), (uint8_t)iter_count, 1U);
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_PRUNE_X, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_RESID, 0));
        break;
    case ALG_HTP:
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(1U, 0U, 0));
        cgra_write_ctx(pc++, post_update_x_topk_ctx(1U, (uint8_t)iter_count, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_CORR_UPDATE, 0));
        cgra_write_ctx(pc++, candidate_copy_to_p0_ctx(1U, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_PRUNE_X, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE, 0));
        break;
    case ALG_SP:
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_CORR, 0));
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(1U, 0U, 0));
        cgra_write_ctx(pc++, candidate_select_path_ctx(1U, 0));
        emit_reduce_append_loop(&pc, reduce_argmax_ctx(0), candidate_append_path_ctx(1U, 0), (uint8_t)iter_count, 1U);
        cgra_write_ctx(pc++, candidate_select_path_ctx(1U, 0));
        cgra_write_ctx(pc++, candidate_merge_path_ctx(0U, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE, 0));
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(1U, 0U, 0));
        cgra_write_ctx(pc++, candidate_select_path_ctx(1U, 0));
        emit_reduce_append_loop(&pc, reduce_x_support_ctx(0), candidate_append_path_ctx(1U, 0), (uint8_t)iter_count, 1U);
        cgra_write_ctx(pc++, candidate_copy_to_p0_ctx(1U, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE, 0));
        break;
    case ALG_GP:
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_CORR_UPDATE, 0));
        cgra_write_ctx(pc++, reduce_argmax_ctx(0));
        cgra_write_ctx(pc++, candidate_append_result_ctx(0));
        cgra_write_ctx(pc++, candidate_meta_depth_ctx(0U, 0U, 0));
        emit_reduce_append_loop(&pc, reduce_x_ctx(0), candidate_append_path_ctx(0U, 0), (uint8_t)iter_count, 1U);
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_PRUNE_X, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_RESID, 0));
        break;
    case ALG_GOMP:
        cgra_write_ctx(pc++, stream_topk_ctx(0U, 2U, 1, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_CORR, 0));
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_REFINE, 0));
        break;
    case ALG_MP:
        emit_mp_select_append(&pc);
        cgra_write_ctx(pc++, sparse_op_ctx(SOP_MP_UPDATE, 0));
        break;
    default:
        break;
    }

    emit_loop_tail(&pc, body_start, (uint8_t)iter_count, 0U);
    cgra_write_ctx(pc++, dma_ctx(VEC_X, 0U, 1, 1));
    return pc;
}

static int32_t sign_extend24(uint32_t value)
{
    value &= 0x00ffffffU;
    return (value & 0x00800000U) ? (int32_t)(value | 0xff000000U) : (int32_t)value;
}

static uint32_t abs_diff24(uint32_t actual, uint32_t expected)
{
    int32_t diff = sign_extend24(actual) - sign_extend24(expected);
    return (diff < 0) ? (uint32_t)(-diff) : (uint32_t)diff;
}

static uint64_t elapsed_us(XTime start, XTime end)
{
    return ((uint64_t)(end - start) * 1000000ULL) / (uint64_t)COUNTS_PER_SECOND;
}

static void check(const char *name, int cond)
{
    if (cond) {
        ++pass_cnt;
    } else {
        xil_printf("FAIL %s\r\n", name);
        ++fail_cnt;
    }
}

static void init_buffers(uint32_t case_idx)
{
    for (uint32_t i = 0; i < KSGOLD_MAX_M; ++i) {
        y_buf[i] = (i < ksgold_case_m[case_idx]) ? ksgold_y[i] : 0U;
    }
    for (uint32_t i = 0; i < KSGOLD_MAX_N; ++i) {
        x_buf[i] = 0U;
    }
    Xil_DCacheFlushRange((UINTPTR)y_buf, sizeof(y_buf));
    Xil_DCacheFlushRange((UINTPTR)x_buf, sizeof(x_buf));
}

static void clear_cgra_state(void)
{
    /* Independent run boundary: reset SPM scratch and configmem as well as
     * status.  Buffers and the next program are loaded after this call. */
    cgra_write(REG_CTRL, 2U);
    for (volatile uint32_t i = 0; i < 1024U; ++i) {
    }
}

static int run_one(uint32_t case_idx, uint32_t alg)
{
    const uint32_t k_target = ksgold_case_k[case_idx];
    const uint32_t iter_count = (alg == ALG_GOMP) ? ((k_target + 1U) >> 1) : k_target;
    const uint32_t gold_idx = golden_alg_idx(alg);
    const uint32_t fail_before = fail_cnt;
    uint32_t program_len;
    uint32_t status_rd;
    uint32_t cycle_rd;
    uint32_t pc_rd;
    uint32_t mismatches;
    uint32_t nonzero_count;
    uint32_t pass_case;
    uint32_t i;
    int rc;
    int done_seen;
    int error_seen;
    XTime t0;
    XTime t1;

    if ((iter_count == 16U) && ((alg == ALG_COSAMP) || (alg == ALG_SP))) {
        xil_printf("SKIP_CASE case=%lu m=%lu n=%lu k=%lu alg=%lu reason=requires_2K_candidate_support\r\n",
                   (unsigned long)case_idx,
                   (unsigned long)ksgold_case_m[case_idx],
                   (unsigned long)ksgold_case_n[case_idx],
                   (unsigned long)ksgold_case_k[case_idx],
                   (unsigned long)alg);
        return 2;
    }

    clear_cgra_state();
    init_buffers(case_idx);

    ctx_write_overflow = 0U;
    ctx_loop_count = 0U;

    cgra_write(REG_M_SIZE, ksgold_case_m[case_idx]);
    cgra_write(REG_N_SIZE, ksgold_case_n[case_idx]);
    cgra_write(REG_K_PARAM, iter_count);
    cgra_write(REG_Y_DDR, (uint32_t)(UINTPTR)y_buf);
    cgra_write(REG_X_DDR, (uint32_t)(UINTPTR)x_buf);
    cgra_write(REG_SEED, KSGOLD_SEED);
    cgra_write(REG_PHI_SCALE, KSGOLD_SCALE);
    cgra_write(REG_FLAGS, (KSGOLD_PHI_KIND << 2));
    cgra_write(REG_MU_SHIFT, KSGOLD_MU_SHIFT);

    program_len = build_program(alg, iter_count);
    check("program_len_nonzero", program_len > 0U);
    check("program_len_fits_ctx", (!ctx_write_overflow) && (program_len < CTX_AXI_WORD_LIMIT));
    if ((alg == ALG_COSAMP) || (alg == ALG_SP) || (alg == ALG_IHT) || (alg == ALG_HTP) || (alg == ALG_GP)) {
        check("cf_loop_present", ctx_loop_count > 0U);
    }

    if (ctx_write_overflow || program_len > CTX_AXI_WORD_LIMIT) {
        xil_printf("CASE=m%lu_n%lu_iter%lu_kparam%lu ALG=%s rc=-10 program_len=%lu limit=%lu overflow=%lu FAIL\r\n",
                   (unsigned long)ksgold_case_m[case_idx],
                   (unsigned long)ksgold_case_n[case_idx],
                   (unsigned long)iter_count,
                   (unsigned long)iter_count,
                   tb_alg_names[alg],
                   (unsigned long)program_len,
                   (unsigned long)CTX_AXI_WORD_LIMIT,
                   (unsigned long)ctx_write_overflow);
        return -10;
    }

    cgra_write(REG_PROG_BASE, 0U);
    cgra_write(REG_PROG_LEN, program_len);

    XTime_GetTime(&t0);
    cgra_write(REG_CTRL, 1U);

    done_seen = 0;
    error_seen = 0;
    rc = 0;
    for (uint32_t timeout = 200000000U; timeout != 0U; --timeout) {
        uint32_t st = cgra_read(REG_STATUS);
        if (st & STATUS_ERROR) {
            error_seen = 1;
            rc = -1;
            break;
        }
        if (st & STATUS_DONE) {
            done_seen = 1;
            break;
        }
    }
    if (!done_seen && !error_seen) {
        rc = -2;
    }

    XTime_GetTime(&t1);
    Xil_DCacheInvalidateRange((UINTPTR)x_buf, sizeof(x_buf));

    status_rd = cgra_read(REG_STATUS);
    cycle_rd = cgra_read(REG_CYCLE_CNT);
    pc_rd = cgra_read(REG_PC_DBG);

    mismatches = 0U;
    nonzero_count = 0U;
    for (i = 0; i < ksgold_case_n[case_idx]; ++i) {
        uint32_t actual = x_buf[i] & 0x00ffffffU;
        uint32_t expected = ksgold_x_final[gold_idx][case_idx][i] & 0x00ffffffU;
        if (actual != 0U) {
            ++nonzero_count;
        }
        if (abs_diff24(actual, expected) > KSGOLD_TOL) {
            if (mismatches < 8U) {
                xil_printf("X_MISM alg=%lu i=%lu got=0x%06lx exp=0x%06lx diff=%lu\r\n",
                           (unsigned long)alg,
                           (unsigned long)i,
                           (unsigned long)actual,
                           (unsigned long)expected,
                           (unsigned long)abs_diff24(actual, expected));
            }
            ++mismatches;
        }
    }

    check("irq_done", done_seen && !error_seen && (rc == 0));
    check("pc_in_program_or_done", pc_rd < program_len);
    check("golden_vector", mismatches == 0U);

    pass_case = (fail_cnt == fail_before) && (mismatches == 0U);
    if (!pass_case) {
        xil_printf("CASE=m%lu_n%lu_iter%lu_kparam%lu ALG=%s rc=%d status=0x%08lx cycles=%lu time_us=%llu plen=%lu nz=%lu mism=%lu FAIL\r\n",
                   (unsigned long)ksgold_case_m[case_idx],
                   (unsigned long)ksgold_case_n[case_idx],
                   (unsigned long)iter_count,
                   (unsigned long)iter_count,
                   tb_alg_names[alg],
                   rc,
                   (unsigned long)status_rd,
                   (unsigned long)cycle_rd,
                   (unsigned long long)elapsed_us(t0, t1),
                   (unsigned long)program_len,
                   (unsigned long)nonzero_count,
                   (unsigned long)mismatches);
        xil_printf("X_DUMP_BEGIN case=%lu m=%lu n=%lu k=%lu alg=%lu name=%s\r\n",
                   (unsigned long)case_idx,
                   (unsigned long)ksgold_case_m[case_idx],
                   (unsigned long)ksgold_case_n[case_idx],
                   (unsigned long)iter_count,
                   (unsigned long)alg,
                   tb_alg_names[alg]);
        for (i = 0; i < ksgold_case_n[case_idx]; ++i) {
            uint32_t actual = x_buf[i] & 0x00ffffffU;
            uint32_t expected = ksgold_x_final[gold_idx][case_idx][i] & 0x00ffffffU;
            if ((actual != 0U) || (expected != 0U)) {
                xil_printf("X_DUMP case=%lu alg=%lu i=%lu got=0x%06lx exp=0x%06lx diff=%lu\r\n",
                           (unsigned long)case_idx,
                           (unsigned long)alg,
                           (unsigned long)i,
                           (unsigned long)actual,
                           (unsigned long)expected,
                           (unsigned long)abs_diff24(actual, expected));
            }
        }
        xil_printf("X_DUMP_END case=%lu alg=%lu\r\n", (unsigned long)case_idx, (unsigned long)alg);
        return -1;
    }

    xil_printf("CASE=m%lu_n%lu_iter%lu_kparam%lu ALG=%s status=0x%08lx cycles=%lu time_us=%llu plen=%lu nz=%lu pc_dbg=%lu PASS\r\n",
               (unsigned long)ksgold_case_m[case_idx],
               (unsigned long)ksgold_case_n[case_idx],
               (unsigned long)iter_count,
               (unsigned long)iter_count,
               tb_alg_names[alg],
               (unsigned long)status_rd,
               (unsigned long)cycle_rd,
               (unsigned long long)elapsed_us(t0, t1),
               (unsigned long)program_len,
               (unsigned long)nonzero_count,
               (unsigned long)pc_rd);

    return 0;
}

int main(void)
{
    xil_printf("\r\nCSCGRA tb_soc_program k-sweep SDK runner [ls_serial_write RTL]\r\n");
    xil_printf("CGRA_BASE = 0x%08lx\r\n", (unsigned long)CGRA_BASE);
    xil_printf("GOLDEN_MODE = %s [mu_shift=%lu ls_serial_write RTL]\r\n",
               KSGOLD_SOURCE_TAG,
               (unsigned long)KSGOLD_MU_SHIFT);
    xil_printf("KSWEEP_CASES = {m64n256k16, m64n256k8, m64n256k4, m32n128k8, m32n128k4, m32n128k2, m16n64k4, m16n64k2}\r\n");

    pass_cnt = 0U;
    fail_cnt = 0U;
    run_pass_cnt = 0U;
    run_fail_cnt = 0U;
#ifdef KSWEEP_ONLY_CASE
    for (uint32_t case_idx = KSWEEP_ONLY_CASE; case_idx <= KSWEEP_ONLY_CASE; ++case_idx) {
#else
    for (uint32_t case_idx = 0U; case_idx < KSGOLD_CASE_COUNT; ++case_idx) {
#endif
        xil_printf("RUN_CASE m=%lu n=%lu iter=%lu kparam=%lu\r\n",
                   (unsigned long)ksgold_case_m[case_idx],
                   (unsigned long)ksgold_case_n[case_idx],
                   (unsigned long)ksgold_case_k[case_idx],
                   (unsigned long)ksgold_case_k[case_idx]);
#ifdef KSWEEP_ONLY_ALG
        for (uint32_t alg = KSWEEP_ONLY_ALG; alg <= KSWEEP_ONLY_ALG; ++alg) {
#else
        for (uint32_t alg = 0U; alg < KSGOLD_ALG_COUNT; ++alg) {
#endif
            int run_rc = run_one(case_idx, alg);
            if (run_rc == 0) {
                ++run_pass_cnt;
            } else if (run_rc == 2) {
                /* skipped to match tb_run1_k_sweep K=16 2K-support limitation */
            } else {
                ++run_fail_cnt;
            }
        }
    }

    xil_printf("tb_soc_program_k_sweep: runs %lu PASS, %lu FAIL | checks %lu PASS, %lu FAIL\r\n",
               (unsigned long)run_pass_cnt,
               (unsigned long)run_fail_cnt,
               (unsigned long)pass_cnt,
               (unsigned long)fail_cnt);
    return (run_fail_cnt || fail_cnt) ? -1 : 0;
}




