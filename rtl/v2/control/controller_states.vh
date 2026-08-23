// State encodings of sparse_loop_controller's main FSM.
//
// The numeric values are a frozen contract: verification benches match
// `state` (and wide_mul_state_q) against these encodings through
// hierarchical references, and scripts/maintenance/check_controller_state_encodings.py
// fails when a bench literal disagrees with this table.  Do not renumber;
// only append new states in unused encodings.
//
// Encodings 17, 40, 56, 71, 78, 88-91, 93, 95, 98, 104 and 105 belonged
// to unreachable pre-LDLT Gauss-elimination/cache arms removed by the R3-lite
// dead-code cleanup; they stay reserved so no other state takes them.
// S_CORR_WRITE_H1 reuses freed encoding 55 for the pair-mode second-half
// correlation drain.
localparam [6:0] S_IDLE=0, S_PRIME=1, S_ACC=3, S_WX=5, S_WR=7, S_DONE=8, S_SOLVE_INIT=11, S_ELIM_START=12, S_ELIM_ROW=13, S_ELIM_UPDATE=14, S_BACK_INIT=15, S_BACK_ACC=16, S_SOLVE_DONE=18, S_ACC_RHS=19, S_ACC_GRAM=20, S_WR_ACC_INIT=21, S_ACC_PE_WAIT3=22, S_BACK_PREP=23, S_ELIM_PREP=24, S_ELIM_MUL=25, S_BACK_MUL=26, S_BACK_UPDATE=27, S_DIV_INIT=28, S_DIV_STEP=29, S_ELIM_DIV_DONE=30, S_BACK_DIV_DONE=31, S_CORR_INIT=34, S_CORR_SCAN=35, S_CORR_ACC=36, S_CORR_WRITE=37, S_IHT_X_WAIT=38, S_IHT_SCORE_WAIT=39, S_PRUNE_X_WAIT=41, S_IHT_SCORE_READ=42, S_IHT_X_READ=43, S_PRUNE_X_READ=44, S_LOAD_COEFF_READ=45, S_LOAD_COEFF_CAP=46, S_ACC_PE_WAIT=47, S_GRAM_PE_WAIT=48, S_GRAM_PE_WAIT2=49, S_RESID_PE_WAIT=50, S_ACC_PE_WAIT2=53, S_CORR_PE_WAIT=54, S_CORR_LATCH=57,
S_MP_X_READ=70, S_MP_DIV_PREP=72, S_MP_X_WRITE=73, S_MP_DIV_DONE=74, S_MP_SCORE_CAP=75, S_MP_X_CAP=76, S_SCAN_DIRECT_STEP=77, S_CORR_WRITE_H1=55,
S_LS_CLEAR_START=86, S_LS_CLEAR_WAIT=87,
S_ELIM_ROW_READ=92, S_BACK_ACC_READ=96, S_GRAM_ACC_WAIT=100, S_RHS_INIT_WAIT=103, S_BACK_RHS_READ=106, S_BACK_RHS_READ_WAIT=107;
localparam [6:0] S_IHT_MESH_WAIT=108, S_IHT_MESH_WRITE=110, S_PRUNE_MESH_WAIT=111, S_PRUNE_MESH_WRITE=113, S_WR_MESH_WAIT=114, S_WR_MESH_COMMIT=116, S_WX_COMMIT=117, S_WX_CLEAR=4, S_DELTA_CLEAR_START=6, S_DELTA_CLEAR_WAIT=9;
localparam [6:0] S_LDL_INIT=58, S_LDL_DIAG_READ=59, S_LDL_DIAG_WAIT=60,
S_LDL_DIAG_GATHER=61, S_LDL_DIAG_GATHER_WAIT=62, S_LDL_DIAG_MUL1=63,
S_LDL_DIAG_MUL1_WAIT=64, S_LDL_DIAG_MUL2=65, S_LDL_DIAG_MUL2_WAIT=66,
S_LDL_DIAG_WRITE=67, S_LDL_DIAG_WRITE_WAIT=68, S_LDL_INV_DIV=69,
S_LDL_INV_DONE=79, S_LDL_ROW_INIT=80,
S_LDL_ROW_A_WAIT=82, S_LDL_ROW_P_WAIT=84,
S_LDL_ROW_MUL1=85, S_LDL_ROW_MUL2=119, S_LDL_ROW_FINAL_MUL=121,
S_LDL_ROW_FINAL_WAIT=122,
S_LDL_ROW_WRITE_WAIT=124;
localparam [6:0] S_FACTOR_CHECK_INIT=125, S_FACTOR_CHECK_SCAN=126,
                 S_FACTOR_CHECK_DONE=127;
localparam [6:0] S_FUSED_UPDATE_CAPTURE=7'd2;
localparam [6:0] S_GP_DIV_DONE=7'd118;
// Registered commit boundary for the GP x update.  GP is the only score
// update which multiplies an SPM value by the line-search alpha; committing
// it directly in S_IHT_SCORE_READ formed an SPM -> DSP -> saturation -> SPM
// path in one clock.
localparam [6:0] S_GP_UPDATE_COMMIT=7'd51,
                 S_GP_UPDATE_OPERANDS=7'd52,
                 S_GP_UPDATE_MUL=7'd81,
                 S_GP_UPDATE_SAT=7'd83;
