#include "main_8alg.c"

#if 0
#include <stdint.h>
#include <stddef.h>

#include "platform.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"

#ifndef CGRA_BASEADDR
#define CGRA_BASEADDR 0xA0000000UL
#endif

#define CGRA_DDR_LOW_LIMIT 0x80000000UL

#define REG_CTRL         0x000U
#define REG_STATUS       0x004U
#define REG_M_SIZE       0x00CU
#define REG_N_SIZE       0x010U
#define REG_K_PARAM      0x014U
#define REG_Y_DDR        0x018U
#define REG_X_DDR        0x01CU
#define REG_SEED         0x020U
#define REG_PHI_SCALE    0x024U
#define REG_FLAGS        0x030U
#define REG_PROG_BASE    0x040U
#define REG_PROG_LEN     0x044U
#define REG_RESULT0      0x050U
#define REG_CYCLE_CNT    0x054U
#define REG_PC_DBG       0x058U
#define REG_CTX_BASE     0x100U

#define CTRL_START       0x00000001U
#define CTRL_SOFT_RESET  0x00000002U
#define CTRL_CLEAR_ERROR 0x00000004U

#define ST_DONE          0x00000001U
#define ST_BUSY          0x00000002U
#define ST_CONVERGED     0x00000004U
#define ST_ERROR         0x00000008U
#define ST_ERROR_CODE(s) (((s) >> 4) & 0x0FU)

#define M_SIZE 64U
#define N_SIZE 256U
#define K_PARAM 16U
#define PHI_SCALE_Q8_16 0x004000U
#define SEED 17U
#define FLAGS_MP 0x00000001U

#define VEC_X 0U
#define VEC_R 1U
#define VEC_Y 2U
#define NEXT_END_PROG 6U
#define POLL_LIMIT 100000000U
#define GOLD_TOL 512

static uint32_t y_ddr[M_SIZE] __attribute__((aligned(64))) = {
    0x00fec000U, 0x00ffa000U, 0x00018000U, 0x00ffa000U,
    0x00ff8000U, 0x00ffa000U, 0x00012000U, 0x00fda000U,
    0x00fec000U, 0x00fde000U, 0x00ffa000U, 0x00ff8000U,
    0x00004000U, 0x00fde000U, 0x00024000U, 0x00fd8000U,
    0x00ff0000U, 0x00020000U, 0x00ff2000U, 0x0001e000U,
    0x00ff0000U, 0x00016000U, 0x00ffc000U, 0x0000c000U,
    0x00fe2000U, 0x00012000U, 0x00ff6000U, 0x00014000U,
    0x00020000U, 0x00012000U, 0x00ffe000U, 0x00ffc000U,
    0x00000000U, 0x00fea000U, 0x00ffe000U, 0x00004000U,
    0x00012000U, 0x00ff4000U, 0x00000000U, 0x00fda000U,
    0x00fd4000U, 0x00ffe000U, 0x00ff0000U, 0x0000c000U,
    0x00010000U, 0x00ffe000U, 0x00010000U, 0x00018000U,
    0x00ffa000U, 0x00fe6000U, 0x00006000U, 0x00ff8000U,
    0x00ff8000U, 0x00ffa000U, 0x00ff6000U, 0x00fe6000U,
    0x00010000U, 0x00fe0000U, 0x00010000U, 0x00018000U,
    0x00010000U, 0x00008000U, 0x00fea000U, 0x00014000U,
};

static uint32_t x_ddr[N_SIZE] __attribute__((aligned(64)));

static uint32_t gold_x_at(uint32_t index)
{
    switch (index) {
    case 65U:  return 0x00ff62b9U;
    case 74U:  return 0x00fda861U;
    case 84U:  return 0x0000b43eU;
    case 91U:  return 0x000107b8U;
    case 107U: return 0x0000aeb7U;
    case 147U: return 0x0001a0d0U;
    case 148U: return 0x00ff5611U;
    case 149U: return 0x00008b79U;
    case 165U: return 0x00013ac0U;
    case 168U: return 0x00fed9ceU;
    case 174U: return 0x00ff2b4fU;
    case 182U: return 0x00ff603eU;
    case 201U: return 0x00feee3eU;
    case 231U: return 0x000204d0U;
    case 235U: return 0x00ffa1d0U;
    default:   return 0U;
    }
}

static int32_t sign_extend24(uint32_t value)
{
    value &= 0x00ffffffU;
    if ((value & 0x00800000U) != 0U) {
        value |= 0xff000000U;
    }
    return (int32_t)value;
}

static int absdiff_le24(uint32_t actual, uint32_t expected, int32_t tol)
{
    int32_t diff = sign_extend24(actual) - sign_extend24(expected);
    if (diff < 0) {
        diff = -diff;
    }
    return diff <= tol;
}

static inline void cgra_wr(uint32_t off, uint32_t value)
{
    Xil_Out32((UINTPTR)(CGRA_BASEADDR + off), value);
}

static inline uint32_t cgra_rd(uint32_t off)
{
    return Xil_In32((UINTPTR)(CGRA_BASEADDR + off));
}

static void ctx_write(uint32_t index, uint64_t word)
{
    const uint32_t off = REG_CTX_BASE + (index * 8U);
    cgra_wr(off + 0U, (uint32_t)(word & 0xffffffffULL));
    cgra_wr(off + 4U, (uint32_t)(word >> 32));
}

static uint64_t ctx_header(uint32_t uop_class, uint32_t repeat_sel,
                           uint32_t addr_dim, uint32_t next_ctrl)
{
    return (1ULL << 60) |
           ((uint64_t)(uop_class & 0x0FU) << 56) |
           ((uint64_t)(repeat_sel & 0x0FU) << 52) |
           ((uint64_t)(addr_dim & 0x0FU) << 48) |
           ((uint64_t)(next_ctrl & 0x0FU) << 44);
}

static uint64_t dma_ctx(uint32_t vec_id, uint32_t use_m_size, uint32_t ddr_write,
                        uint32_t end_prog)
{
    const uint32_t addr_dim = use_m_size ? 1U : 2U;
    uint64_t w = ctx_header(7U, 0U, addr_dim, end_prog ? NEXT_END_PROG : 0U);
    w |= ((uint64_t)(vec_id & 0x7U) << 41);
    w |= (uint64_t)(ddr_write & 0x1U);
    return w;
}

static uint64_t sparse_op_ctx(uint32_t sop, uint32_t end_prog)
{
    uint64_t w = ctx_header(8U, 0U, 0U, end_prog ? NEXT_END_PROG : 0U);
    w |= ((uint64_t)(sop & 0xffU) << 20);
    return w;
}

static uint64_t reduce_argmax_ctx(uint32_t end_prog)
{
    uint64_t w = ctx_header(4U, 1U, 2U, end_prog ? NEXT_END_PROG : 0U);
    w |= (3ULL << 41); /* spm_a_vec */
    w |= (0ULL << 32); /* lane_mask_mode from MP cycle test */
    w |= (4ULL << 24); /* reduce_op argmax */
    return w;
}

static uint64_t candidate_append_result_ctx(uint32_t end_prog)
{
    uint64_t w = ctx_header(6U, 0U, 0U, end_prog ? NEXT_END_PROG : 0U);
    w |= (0ULL << 20);
    w |= (1ULL << 16);
    return w;
}

static uint32_t low_ddr_addr(const void *ptr, const char *name, int *ok)
{
    const UINTPTR a = (UINTPTR)ptr;
    if (a >= (UINTPTR)CGRA_DDR_LOW_LIMIT) {
        xil_printf("ERROR: %s buffer low address 0x%x is outside low DDR\r\n",
                   name, (uint32_t)a);
        *ok = 0;
    }
    return (uint32_t)a;
}

static void cgra_soft_reset(void)
{
    cgra_wr(REG_CTRL, CTRL_SOFT_RESET | CTRL_CLEAR_ERROR);
    for (volatile uint32_t i = 0; i < 10000U; ++i) {
    }
    cgra_wr(REG_CTRL, CTRL_CLEAR_ERROR);
}

static int wait_for_done(const char *tag)
{
    uint32_t status = 0U;
    for (uint32_t i = 0U; i < POLL_LIMIT; ++i) {
        status = cgra_rd(REG_STATUS);
        if ((status & (ST_DONE | ST_ERROR)) != 0U) {
            const uint32_t cycles = cgra_rd(REG_CYCLE_CNT);
            const uint32_t pc = cgra_rd(REG_PC_DBG);
            xil_printf("%s status=0x%x cycles=%d pc=%d\r\n",
                       tag, status, cycles, pc);
            if ((status & ST_ERROR) != 0U) {
                xil_printf("  ERROR: CGRA error_code=%d\r\n",
                           ST_ERROR_CODE(status));
                return -1;
            }
            return 0;
        }
    }

    status = cgra_rd(REG_STATUS);
    xil_printf("%s TIMEOUT status=0x%x pc=%d\r\n", tag, status,
               cgra_rd(REG_PC_DBG));
    return -1;
}

static int launch_program(const char *tag, uint32_t prog_len)
{
    cgra_wr(REG_PROG_BASE, 0U);
    cgra_wr(REG_PROG_LEN, prog_len);
    cgra_wr(REG_CTRL, CTRL_START);
    return wait_for_done(tag);
}

static int run_dma(const char *tag, uint32_t vec_id, uint32_t use_m_size,
                   uint32_t ddr_write)
{
    ctx_write(0U, dma_ctx(vec_id, use_m_size, ddr_write, 1U));
    return launch_program(tag, 1U);
}

static int run_mp_kernel(void)
{
    uint32_t pc = 0U;
    for (uint32_t iter = 0U; iter < K_PARAM; ++iter) {
        ctx_write(pc++, sparse_op_ctx(0x81U, 0U));
        ctx_write(pc++, reduce_argmax_ctx(0U));
        ctx_write(pc++, candidate_append_result_ctx(0U));
        ctx_write(pc++, sparse_op_ctx(0x85U, iter == (K_PARAM - 1U)));
    }
    return launch_program("mp compute", pc);
}

static void print_x_samples(void)
{
    uint32_t printed = 0U;
    xil_printf("x non-zero samples:\r\n");
    for (uint32_t i = 0U; i < N_SIZE; ++i) {
        const uint32_t v = x_ddr[i] & 0x00ffffffU;
        if (v != 0U) {
            xil_printf("  x[%d] = 0x%x\r\n", i, v);
            printed++;
            if (printed >= 24U) {
                break;
            }
        }
    }
    if (printed == 0U) {
        xil_printf("  all first %d entries are zero\r\n", N_SIZE);
    }
}

static int verify_x_against_golden(void)
{
    uint32_t fail = 0U;
    uint32_t shown = 0U;

    for (uint32_t i = 0U; i < N_SIZE; ++i) {
        const uint32_t actual = x_ddr[i] & 0x00ffffffU;
        const uint32_t expected = gold_x_at(i);
        if (!absdiff_le24(actual, expected, GOLD_TOL)) {
            fail++;
            if (shown < 16U) {
                xil_printf("  MISMATCH x[%d] got=0x%x exp=0x%x\r\n",
                           i, actual, expected);
                shown++;
            }
        }
    }

    if (fail == 0U) {
        xil_printf("VERIFY x_final PASS tol=%d\r\n", GOLD_TOL);
        return 0;
    }

    xil_printf("VERIFY x_final FAIL mismatches=%d tol=%d\r\n", fail, GOLD_TOL);
    return -1;
}

int main(void)
{
    int addr_ok = 1;

    init_platform();

    const uint32_t y_addr = low_ddr_addr(y_ddr, "y_ddr", &addr_ok);
    const uint32_t x_addr = low_ddr_addr(x_ddr, "x_ddr", &addr_ok);

    xil_printf("\r\nCSCGRA ZCU106 SoC bare-metal run\r\n");
    xil_printf("CGRA AXI-Lite base: 0x%x\r\n", (uint32_t)CGRA_BASEADDR);
    xil_printf("y_ddr: 0x%x, x_ddr: 0x%x\r\n", y_addr, x_addr);

    if (!addr_ok) {
        xil_printf("Move buffers/linker sections to low DDR and rerun.\r\n");
        cleanup_platform();
        return -1;
    }

    for (uint32_t i = 0U; i < N_SIZE; ++i) {
        x_ddr[i] = 0U;
    }

    Xil_DCacheFlushRange((UINTPTR)y_ddr, sizeof(y_ddr));
    Xil_DCacheFlushRange((UINTPTR)x_ddr, sizeof(x_ddr));

    cgra_soft_reset();
    cgra_wr(REG_M_SIZE, M_SIZE);
    cgra_wr(REG_N_SIZE, N_SIZE);
    cgra_wr(REG_K_PARAM, K_PARAM);
    cgra_wr(REG_Y_DDR, y_addr);
    cgra_wr(REG_X_DDR, x_addr);
    cgra_wr(REG_SEED, SEED);
    cgra_wr(REG_PHI_SCALE, PHI_SCALE_Q8_16);
    cgra_wr(REG_FLAGS, FLAGS_MP);

    xil_printf("Configured M=%d N=%d K=%d seed=%d scale=0x%x flags=0x%x\r\n",
               M_SIZE, N_SIZE, K_PARAM, SEED, PHI_SCALE_Q8_16, FLAGS_MP);

    if (run_dma("dma y -> vec2", VEC_Y, 1U, 0U) != 0) {
        cleanup_platform();
        return -1;
    }
    if (run_dma("dma y -> vec1", VEC_R, 1U, 0U) != 0) {
        cleanup_platform();
        return -1;
    }
    if (run_mp_kernel() != 0) {
        cleanup_platform();
        return -1;
    }
    if (run_dma("dma vec0 -> x", VEC_X, 0U, 1U) != 0) {
        cleanup_platform();
        return -1;
    }

    Xil_DCacheInvalidateRange((UINTPTR)x_ddr, sizeof(x_ddr));
    print_x_samples();
    if (verify_x_against_golden() != 0) {
        cleanup_platform();
        return -1;
    }

    xil_printf("CSCGRA SoC run complete.\r\n");
    cleanup_platform();
    return 0;
}
#endif
