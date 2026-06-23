#include <stdint.h>
#include <stddef.h>

#include "platform.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"

#if defined(__INCLUDE_LEVEL__) && (__INCLUDE_LEVEL__ == 0)
int cscgra_soc_main_8alg_compile_via_main_c;
#else

#ifndef CGRA_BASEADDR
#define CGRA_BASEADDR 0xA0000000UL
#endif

#ifndef CGRA_RUN_ALG_MASK
#define CGRA_RUN_ALG_MASK 0x01ffU
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
#define REG_CYCLE_CNT    0x054U
#define REG_PC_DBG       0x058U
#define REG_CTX_BASE     0x100U

#define CTRL_START       0x00000001U
#define CTRL_SOFT_RESET  0x00000002U
#define CTRL_CLEAR_ERROR 0x00000004U

#define ST_DONE          0x00000001U
#define ST_ERROR         0x00000008U
#define ST_ERROR_CODE(s) (((s) >> 4) & 0x0FU)

#define M_SIZE 64U
#define N_SIZE 256U
#define K_PARAM 16U
#define ALG_ITERS 16U
#define PHI_SCALE_Q8_16 0x004000U
#define SEED 17U
#define FLAGS_TESTBENCH 0x00000001U

#define VEC_X     0U
#define VEC_R     1U
#define VEC_Y     2U
#define VEC_SCORE 3U
#define NEXT_END_PROG 6U
#define POLL_LIMIT 100000000U
#define GOLD_TOL 512
#define ARRAY_COUNT(a) ((uint32_t)(sizeof(a) / sizeof((a)[0])))

typedef struct { uint16_t index; uint32_t value; } gold_pair_t;
typedef enum { ALG_OMP, ALG_OMP_DIRECTPHI, ALG_GOMP, ALG_COSAMP, ALG_SP,
               ALG_IHT, ALG_HTP, ALG_GP, ALG_MP } alg_kind_t;
typedef struct {
    const char *name;
    alg_kind_t kind;
    uint32_t gold_alg_idx;
    uint32_t direct_phi_ctx;
    const gold_pair_t *gold_x;
    uint32_t gold_x_count;
} alg_desc_t;

static uint32_t y_ddr[M_SIZE] __attribute__((aligned(64))) = {
    0x00fec000U,0x00ffa000U,0x00018000U,0x00ffa000U,0x00ff8000U,0x00ffa000U,0x00012000U,0x00fda000U,
    0x00fec000U,0x00fde000U,0x00ffa000U,0x00ff8000U,0x00004000U,0x00fde000U,0x00024000U,0x00fd8000U,
    0x00ff0000U,0x00020000U,0x00ff2000U,0x0001e000U,0x00ff0000U,0x00016000U,0x00ffc000U,0x0000c000U,
    0x00fe2000U,0x00012000U,0x00ff6000U,0x00014000U,0x00020000U,0x00012000U,0x00ffe000U,0x00ffc000U,
    0x00000000U,0x00fea000U,0x00ffe000U,0x00004000U,0x00012000U,0x00ff4000U,0x00000000U,0x00fda000U,
    0x00fd4000U,0x00ffe000U,0x00ff0000U,0x0000c000U,0x00010000U,0x00ffe000U,0x00010000U,0x00018000U,
    0x00ffa000U,0x00fe6000U,0x00006000U,0x00ff8000U,0x00ff8000U,0x00ffa000U,0x00ff6000U,0x00fe6000U,
    0x00010000U,0x00fe0000U,0x00010000U,0x00018000U,0x00010000U,0x00008000U,0x00fea000U,0x00014000U,
};
static uint32_t zero_ddr[N_SIZE] __attribute__((aligned(64)));
static uint32_t x_ddr[N_SIZE] __attribute__((aligned(64)));

static const gold_pair_t gold_omp_x[]={{38U,0x00fee6eaU},{42U,0x00ff73f2U},{74U,0x00feabe3U},{84U,0x000090f5U},{87U,0x00010a5aU},{91U,0x00018f38U},{96U,0x00001566U},{107U,0x000139a8U},{147U,0x0000f1c0U},{149U,0x00016da4U},{168U,0x00fe6fd3U},{174U,0x00fef751U},{182U,0x00ff5a3eU},{201U,0x00ff6842U},{209U,0x00ff8308U},{231U,0x000190cdU}};
static const gold_pair_t gold_gomp_x[]={{30U,0x00ff6149U},{37U,0x00ff832aU},{38U,0x00fe7aa5U},{42U,0x00febcd4U},{48U,0x00005104U},{74U,0x00fe460fU},{84U,0x0000b854U},{87U,0x00019c60U},{91U,0x0001b78fU},{92U,0x00fef98bU},{96U,0x00ff41acU},{99U,0x00ff7666U},{107U,0x0001c77aU},{119U,0x00ff3cc5U},{135U,0x0000e148U},{137U,0x00ff1607U}};
static const gold_pair_t gold_cosamp_x[]={{1U,0x00ff9d8eU},{8U,0x0000bef3U},{10U,0x00013331U},{13U,0x00fed102U},{14U,0x00ff0ac6U},{16U,0x00ff557dU},{30U,0x0000bafbU},{33U,0x0000e9d4U},{36U,0x0001ff80U},{37U,0x00fef8c5U},{38U,0x00fee425U},{48U,0x00012ae1U},{52U,0x00006a82U},{55U,0x00011b38U},{59U,0x00ff0ab3U},{60U,0x00fffa6aU}};
static const gold_pair_t gold_sp_x[]={{5U,0x00ffe363U},{8U,0x0000f8b2U},{14U,0x00ff15f4U},{30U,0x0000fafbU},{32U,0x00010390U},{38U,0x00ff60bcU},{41U,0x00004aa8U},{47U,0x0000179fU},{59U,0x00ff3202U},{66U,0x0000e9ccU},{67U,0x00fed6eaU},{73U,0x00ffae70U},{74U,0x00fdd33eU},{77U,0x0000eb01U},{84U,0x0001596cU},{87U,0x0001143bU}};
static const gold_pair_t gold_iht_x[]={{0U,0x00e00000U},{8U,0x00e00000U},{10U,0x00e00000U},{17U,0x00e00000U},{20U,0x00e00000U},{25U,0x00e00000U},{27U,0x00e00000U},{30U,0x00e00000U},{41U,0x00e00000U},{48U,0x00e00000U},{49U,0x00e00000U},{61U,0x00e00000U},{69U,0x00e00000U},{70U,0x00e00000U},{72U,0x00e00000U},{99U,0x00e00000U}};
static const gold_pair_t gold_htp_x[]={{38U,0x00ff0000U},{42U,0x00ff8000U},{74U,0x00fe7fffU},{84U,0x00008001U},{87U,0x0000fffeU},{91U,0x00018002U},{107U,0x00014001U},{147U,0x00010002U},{149U,0x00014000U},{165U,0x00008003U},{168U,0x00fe8000U},{174U,0x00ff0002U},{182U,0x00ff3fffU},{201U,0x00ff3ffbU},{209U,0x00ff8001U},{231U,0x00017fffU}};
static const gold_pair_t gold_gp_x[]={{32U,0x0000012dU},{37U,0x000030c7U},{38U,0x00fe8415U},{73U,0x00fff54cU},{82U,0x00ff55dbU},{84U,0x0000c0c6U},{120U,0x00ffb57aU},{149U,0x000043d2U},{165U,0x000056e4U},{169U,0x000039eeU},{171U,0x000090e4U},{182U,0x00ff9c3bU},{209U,0x00ffdd32U},{231U,0x0001f3c7U},{239U,0x00ff78aeU},{243U,0x00ffe6a0U}};
static const gold_pair_t gold_mp_x[]={{65U,0x00ff62b9U},{74U,0x00fda861U},{84U,0x0000b43eU},{91U,0x000107b8U},{107U,0x0000aeb7U},{147U,0x0001a0d0U},{148U,0x00ff5611U},{149U,0x00008b79U},{165U,0x00013ac0U},{168U,0x00fed9ceU},{174U,0x00ff2b4fU},{182U,0x00ff603eU},{201U,0x00feee3eU},{231U,0x000204d0U},{235U,0x00ffa1d0U}};

static const alg_desc_t algorithms[] = {
    {"OMP",ALG_OMP,0U,0U,gold_omp_x,ARRAY_COUNT(gold_omp_x)},
    {"OMP_DIRECTPHI",ALG_OMP_DIRECTPHI,0U,1U,gold_omp_x,ARRAY_COUNT(gold_omp_x)},
    {"gOMP",ALG_GOMP,1U,0U,gold_gomp_x,ARRAY_COUNT(gold_gomp_x)},
    {"CoSaMP",ALG_COSAMP,2U,0U,gold_cosamp_x,ARRAY_COUNT(gold_cosamp_x)},
    {"SP",ALG_SP,3U,0U,gold_sp_x,ARRAY_COUNT(gold_sp_x)},
    {"IHT",ALG_IHT,4U,0U,gold_iht_x,ARRAY_COUNT(gold_iht_x)},
    {"HTP",ALG_HTP,5U,0U,gold_htp_x,ARRAY_COUNT(gold_htp_x)},
    {"GP",ALG_GP,6U,0U,gold_gp_x,ARRAY_COUNT(gold_gp_x)},
    {"MP",ALG_MP,7U,0U,gold_mp_x,ARRAY_COUNT(gold_mp_x)},
};

static inline void cgra_wr(uint32_t off,uint32_t v){Xil_Out32((UINTPTR)(CGRA_BASEADDR+off),v);} 
static inline uint32_t cgra_rd(uint32_t off){return Xil_In32((UINTPTR)(CGRA_BASEADDR+off));}
static int32_t sx24(uint32_t v){v&=0x00ffffffU; if(v&0x00800000U) v|=0xff000000U; return (int32_t)v;}
static int absdiff_le24(uint32_t a,uint32_t b,int32_t tol){int32_t d=sx24(a)-sx24(b); if(d<0)d=-d; return d<=tol;}

/* Context/uop encoders. Each build_* function below emits 64-bit context
 * words into the RTL context RAM at REG_CTX_BASE, matching the regression
 * testbench tasks under analysis/m64n256k16.
 */
static void ctx_write(uint32_t i,uint64_t w){uint32_t o=REG_CTX_BASE+i*8U; cgra_wr(o,(uint32_t)w); cgra_wr(o+4U,(uint32_t)(w>>32));}
static void emit(uint32_t *pc,uint64_t w){ctx_write(*pc,w); *pc=*pc+1U;}
static uint64_t hdr(uint32_t cls,uint32_t rep,uint32_t dim,uint32_t next){return (1ULL<<60)|((uint64_t)(cls&15U)<<56)|((uint64_t)(rep&15U)<<52)|((uint64_t)(dim&15U)<<48)|((uint64_t)(next&15U)<<44);} 
static uint64_t dma_ctx(uint32_t vec,uint32_t use_m,uint32_t wr){uint64_t w=hdr(7U,0U,use_m?1U:2U,NEXT_END_PROG); w|=((uint64_t)(vec&7U)<<41); w|=(uint64_t)(wr&1U); return w;}
static uint64_t sparse(uint32_t sop,uint32_t last,uint32_t direct){uint64_t w=hdr(8U,0U,0U,last?NEXT_END_PROG:0U); w|=((uint64_t)(sop&255U)<<20); if(direct&&((sop==0x86U)||(sop==0x80U))) w|=(1ULL<<30); return w;}
static uint64_t red(uint32_t vec,uint32_t mode){uint64_t w=hdr(4U,1U,2U,0U); w|=((uint64_t)(vec&7U)<<41)|((uint64_t)(mode&7U)<<32)|(4ULL<<24); return w;}
static uint64_t cand(uint32_t path,uint32_t op){uint64_t w=hdr(6U,0U,0U,0U); w|=((uint64_t)(path&7U)<<20)|((uint64_t)(op&15U)<<16); return w;}
static uint64_t cand_depth(uint32_t path,uint32_t depth){return cand(path,4U)|((uint64_t)(depth&31U)<<11);} 

static uint32_t low_ddr_addr(const void *p,const char *n,int *ok){UINTPTR a=(UINTPTR)p; if(a>=(UINTPTR)CGRA_DDR_LOW_LIMIT){xil_printf("ERROR: %s buffer low address 0x%x is outside low DDR\r\n",n,(uint32_t)a); *ok=0;} return (uint32_t)a;}
static void cgra_soft_reset(void){cgra_wr(REG_CTRL,CTRL_SOFT_RESET|CTRL_CLEAR_ERROR); for(volatile uint32_t i=0;i<10000U;++i){} cgra_wr(REG_CTRL,CTRL_CLEAR_ERROR);} 

static int wait_done(const char *tag){uint32_t st=0U; for(uint32_t i=0;i<POLL_LIMIT;++i){st=cgra_rd(REG_STATUS); if(st&(ST_DONE|ST_ERROR)){xil_printf("%s status=0x%x cycles=%d pc=%d\r\n",tag,st,cgra_rd(REG_CYCLE_CNT),cgra_rd(REG_PC_DBG)); if(st&ST_ERROR){xil_printf("  ERROR: CGRA error_code=%d\r\n",ST_ERROR_CODE(st)); return -1;} return 0;}} xil_printf("%s TIMEOUT status=0x%x pc=%d\r\n",tag,st,cgra_rd(REG_PC_DBG)); return -1;}
static int launch(const char *tag,uint32_t len){cgra_wr(REG_PROG_BASE,0U); cgra_wr(REG_PROG_LEN,len); cgra_wr(REG_CTRL,CTRL_START); return wait_done(tag);} 
static int dma_read(const char *tag,uint32_t addr,uint32_t vec,uint32_t use_m){cgra_wr(REG_Y_DDR,addr); ctx_write(0U,dma_ctx(vec,use_m,0U)); return launch(tag,1U);} 
static int dma_write(const char *tag,uint32_t addr,uint32_t vec,uint32_t use_m){cgra_wr(REG_X_DDR,addr); ctx_write(0U,dma_ctx(vec,use_m,1U)); return launch(tag,1U);} 

static uint32_t build_omp(uint32_t direct){uint32_t pc=0U; for(uint32_t it=0;it<K_PARAM;++it){uint32_t last=it==(K_PARAM-1U); emit(&pc,sparse(0x81U,0U,direct)); emit(&pc,red(3U,3U)); emit(&pc,cand(0U,1U)); emit(&pc,sparse(0x86U,last,direct));} return pc;}
static uint32_t build_mp(void){uint32_t pc=0U; for(uint32_t it=0;it<K_PARAM;++it){uint32_t last=it==(K_PARAM-1U); emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,red(3U,0U)); emit(&pc,cand(0U,1U)); emit(&pc,sparse(0x85U,last,0U));} return pc;}
static uint32_t build_gomp(void){uint32_t pc=0U; for(uint32_t it=0;it<ALG_ITERS;++it){uint32_t last=it==(ALG_ITERS-1U); emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,red(3U,3U)); emit(&pc,cand(0U,9U)); emit(&pc,red(3U,3U)); emit(&pc,cand(0U,9U)); emit(&pc,sparse(0x80U,last,0U));} return pc;}
static uint32_t build_iht_iter(uint32_t it){uint32_t pc=0U; emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,sparse(0x82U,0U,0U)); emit(&pc,cand_depth(0U,0U)); for(uint32_t i=0;i<K_PARAM;++i){emit(&pc,red(0U,3U)); emit(&pc,cand(0U,9U));} emit(&pc,sparse(0x84U,0U,0U)); emit(&pc,sparse(0x83U,it==(ALG_ITERS-1U),0U)); return pc;}
static uint32_t build_htp_iter(uint32_t it){uint32_t pc=0U; emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,sparse(0x82U,0U,0U)); emit(&pc,cand_depth(0U,0U)); for(uint32_t i=0;i<K_PARAM;++i){emit(&pc,red(0U,3U)); emit(&pc,cand(0U,9U));} emit(&pc,sparse(0x80U,it==(ALG_ITERS-1U),0U)); return pc;}
static uint32_t build_gp_iter(uint32_t it){uint32_t pc=0U; emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,sparse(0x87U,0U,0U)); emit(&pc,cand_depth(0U,0U)); for(uint32_t i=0;i<K_PARAM;++i){emit(&pc,red(0U,3U)); emit(&pc,cand(0U,9U));} emit(&pc,sparse(0x80U,it==(ALG_ITERS-1U),0U)); return pc;}
static uint32_t build_sp_iter(uint32_t it){uint32_t pc=0U; emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,cand_depth(1U,0U)); emit(&pc,cand(1U,6U)); for(uint32_t i=0;i<K_PARAM;++i){emit(&pc,red(3U,3U)); emit(&pc,cand(1U,9U));} emit(&pc,cand(1U,6U)); emit(&pc,cand(0U,2U)); emit(&pc,sparse(0x80U,0U,0U)); emit(&pc,cand_depth(1U,0U)); emit(&pc,cand(1U,6U)); for(uint32_t i=0;i<K_PARAM;++i){emit(&pc,red(0U,3U)); emit(&pc,cand(1U,9U));} emit(&pc,cand(1U,14U)); emit(&pc,sparse(0x80U,it==(ALG_ITERS-1U),0U)); return pc;}
static uint32_t build_cosamp_iter(uint32_t it){uint32_t pc=0U; emit(&pc,sparse(0x81U,0U,0U)); emit(&pc,cand_depth(1U,0U)); emit(&pc,cand(1U,6U)); for(uint32_t i=0;i<(K_PARAM<<1);++i){emit(&pc,red(3U,3U)); emit(&pc,cand(1U,9U));} emit(&pc,cand(1U,6U)); emit(&pc,cand(0U,2U)); emit(&pc,sparse(0x80U,0U,0U)); emit(&pc,cand_depth(1U,0U)); emit(&pc,cand(1U,6U)); for(uint32_t i=0;i<K_PARAM;++i){emit(&pc,red(0U,4U)); emit(&pc,cand(1U,9U));} emit(&pc,cand(1U,14U)); emit(&pc,sparse(0x80U,it==(ALG_ITERS-1U),0U)); return pc;}

static int run_iter_alg(const alg_desc_t *alg){for(uint32_t it=0;it<ALG_ITERS;++it){uint32_t pc; if(alg->kind==ALG_IHT) pc=build_iht_iter(it); else if(alg->kind==ALG_HTP) pc=build_htp_iter(it); else if(alg->kind==ALG_GP) pc=build_gp_iter(it); else if(alg->kind==ALG_SP) pc=build_sp_iter(it); else pc=build_cosamp_iter(it); xil_printf("%s ITER_RUN iter=%d pc=%d\r\n",alg->name,it,pc); if(launch(alg->name,pc)!=0) return -1;} return 0;}
static int run_kernel(const alg_desc_t *alg){uint32_t pc=0U; if(alg->kind==ALG_OMP||alg->kind==ALG_OMP_DIRECTPHI) pc=build_omp(alg->direct_phi_ctx); else if(alg->kind==ALG_GOMP) pc=build_gomp(); else if(alg->kind==ALG_MP) pc=build_mp(); else return run_iter_alg(alg); xil_printf("%s program pc=%d\r\n",alg->name,pc); return launch(alg->name,pc);} 

static uint32_t gold_at(const alg_desc_t *alg,uint32_t idx){for(uint32_t i=0;i<alg->gold_x_count;++i) if(alg->gold_x[i].index==idx) return alg->gold_x[i].value; return 0U;}
static int verify_x(const alg_desc_t *alg){uint32_t fail=0U,shown=0U; for(uint32_t i=0;i<N_SIZE;++i){uint32_t got=x_ddr[i]&0x00ffffffU, exp=gold_at(alg,i); if(!absdiff_le24(got,exp,GOLD_TOL)){fail++; if(shown<16U){xil_printf("  MISMATCH %s x[%d] got=0x%x exp=0x%x\r\n",alg->name,i,got,exp); shown++;}}} if(fail==0U){xil_printf("VERIFY %s x_final PASS alg_idx=%d tol=%d\r\n",alg->name,alg->gold_alg_idx,GOLD_TOL); return 0;} xil_printf("VERIFY %s x_final FAIL mismatches=%d tol=%d\r\n",alg->name,fail,GOLD_TOL); return -1;}
static void print_samples(const char *name){uint32_t n=0U; xil_printf("%s x non-zero samples:\r\n",name); for(uint32_t i=0;i<N_SIZE&&n<24U;++i){uint32_t v=x_ddr[i]&0x00ffffffU; if(v){xil_printf("  x[%d] = 0x%x\r\n",i,v); n++;}} if(n==0U) xil_printf("  all first %d entries are zero\r\n",N_SIZE);} 
static void configure_case(uint32_t y,uint32_t x){cgra_wr(REG_M_SIZE,M_SIZE); cgra_wr(REG_N_SIZE,N_SIZE); cgra_wr(REG_K_PARAM,K_PARAM); cgra_wr(REG_Y_DDR,y); cgra_wr(REG_X_DDR,x); cgra_wr(REG_SEED,SEED); cgra_wr(REG_PHI_SCALE,PHI_SCALE_Q8_16); cgra_wr(REG_FLAGS,FLAGS_TESTBENCH);} 
static int prepare_spm(uint32_t y,uint32_t z){if(dma_read("dma zero -> vec0",z,VEC_X,0U)!=0) return -1; if(dma_read("dma zero -> vec1",z,VEC_R,0U)!=0) return -1; if(dma_read("dma zero -> vec3",z,VEC_SCORE,0U)!=0) return -1; if(dma_read("dma y -> vec2",y,VEC_Y,1U)!=0) return -1; if(dma_read("dma y -> vec1",y,VEC_R,1U)!=0) return -1; return 0;}
static int run_one(const alg_desc_t *alg,uint32_t y,uint32_t z,uint32_t x){xil_printf("\r\n=== RUN %s alg_idx=%d ===\r\n",alg->name,alg->gold_alg_idx); for(uint32_t i=0;i<N_SIZE;++i) x_ddr[i]=0U; Xil_DCacheFlushRange((UINTPTR)x_ddr,sizeof(x_ddr)); cgra_soft_reset(); configure_case(y,x); if(prepare_spm(y,z)!=0) return -1; if(run_kernel(alg)!=0) return -1; if(dma_write("dma vec0 -> x",x,VEC_X,0U)!=0) return -1; Xil_DCacheInvalidateRange((UINTPTR)x_ddr,sizeof(x_ddr)); print_samples(alg->name); return verify_x(alg);}

int main(void)
{
    int addr_ok=1; uint32_t pass=0U,fail=0U;
    init_platform();
    for(uint32_t i=0;i<N_SIZE;++i){zero_ddr[i]=0U; x_ddr[i]=0U;}
    uint32_t y=low_ddr_addr(y_ddr,"y_ddr",&addr_ok), z=low_ddr_addr(zero_ddr,"zero_ddr",&addr_ok), x=low_ddr_addr(x_ddr,"x_ddr",&addr_ok);
    xil_printf("\r\nCSCGRA ZCU106 SoC 8-alg bare-metal run\r\n");
    xil_printf("CGRA AXI-Lite base: 0x%x\r\n",(uint32_t)CGRA_BASEADDR);
    xil_printf("y_ddr: 0x%x, zero_ddr: 0x%x, x_ddr: 0x%x\r\n",y,z,x);
    xil_printf("Configured M=%d N=%d K=%d seed=%d scale=0x%x flags=0x%x\r\n",M_SIZE,N_SIZE,K_PARAM,SEED,PHI_SCALE_Q8_16,FLAGS_TESTBENCH);
    if(!addr_ok){xil_printf("Move buffers/linker sections to low DDR and rerun.\r\n"); cleanup_platform(); return -1;}
    Xil_DCacheFlushRange((UINTPTR)y_ddr,sizeof(y_ddr)); Xil_DCacheFlushRange((UINTPTR)zero_ddr,sizeof(zero_ddr)); Xil_DCacheFlushRange((UINTPTR)x_ddr,sizeof(x_ddr));
    for(uint32_t i=0;i<ARRAY_COUNT(algorithms);++i){if((CGRA_RUN_ALG_MASK&(1U<<i))==0U){xil_printf("SKIP %s by CGRA_RUN_ALG_MASK\r\n",algorithms[i].name); continue;} if(run_one(&algorithms[i],y,z,x)==0) pass++; else {fail++; xil_printf("ALGORITHM %s FAIL\r\n",algorithms[i].name);}}
    xil_printf("\r\nCSCGRA SoC run complete: pass=%d fail=%d\r\n",pass,fail);
    cleanup_platform();
    return fail==0U ? 0 : -1;
}
#endif
