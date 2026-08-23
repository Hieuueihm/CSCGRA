module pe_tile #(
    parameter integer DATA_W = 24,
    parameter integer ACC_W  = 64,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter integer IDX_W  = 10,
    parameter integer ROW_ID = 0,
    parameter integer GLOBAL_COL = 0,
    parameter integer PIPE_MESH = 1,  // 1: register inter-PE mesh hops (systolic)
    parameter integer PIPE_CORE_IN = 1,
    parameter integer FULL_OUT_MUX = 1,
    parameter integer ENABLE_MESH_CTX = 1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     tile_en,
    input  wire                     sparse_wavefront_active,
    input  wire                     corr_wavefront_active,
    input  wire                     corr_pipeline_active,

    input  wire [DATA_W-1:0]        inN,
    input  wire [DATA_W-1:0]        inS,
    input  wire [DATA_W-1:0]        inE,
    input  wire [DATA_W-1:0]        inW,

    input  wire [IDX_W-1:0]         idxE_in,
    input  wire [IDX_W-1:0]         idxW_in,
    input  wire [IDX_W-1:0]         idx_self,

    input  wire [DATA_W-1:0]        spm_a_data,
    input  wire [DATA_W-1:0]        spm_b_data,
    input  wire [DATA_W-1:0]        phi_data,
    input  wire [DATA_W-1:0]        colbus_data,
    input  wire [DATA_W-1:0]        scalar_data,
    input  wire [15:0]              imm16,
    input  wire [1:0]               mesh_ctx_mode,
    input  wire [IDX_W-1:0]         mesh_ctx_base_idx,
    input  wire [IDX_W-1:0]         mesh_ctx_limit,
    input  wire [DATA_W-1:0]        mesh_ctx_threshold,
    input  wire [3:0]               mesh_ctx_shift,
    input  wire [DATA_W-1:0]        mesh_ctx_x,
    input  wire [DATA_W-1:0]        mesh_ctx_delta,
    input  wire                     mesh_ctx_keep,

    input  wire [3:0]               pe_op,
    input  wire [2:0]               src_a_sel,
    input  wire [2:0]               src_b_sel,
    input  wire [1:0]               rf_rd_addr,
    input  wire [1:0]               rf_wr_addr,
    input  wire                     rf_wr_en,
    input  wire                     acc_clear,
    input  wire                     acc_en,
    input  wire [2:0]               sb_sel,
    input  wire                     sb_sel_en,
    input  wire [3:0]               out_sel,
    input  wire                     ext_b_is_scalar,

    output wire [DATA_W-1:0]        outN,
    output wire [DATA_W-1:0]        outS,
    output wire [DATA_W-1:0]        outE,
    output wire [DATA_W-1:0]        outW,
    output wire [IDX_W-1:0]         idxE_out,
    output wire [IDX_W-1:0]         idxW_out,
    output wire [DATA_W-1:0]        pe_data_out,
    output wire [DATA_W-1:0]        mesh_ctx_data_out,
    output wire [IDX_W-1:0]         idx_out,
    output wire [ACC_W-1:0]         acc_out,
    output wire [ACC_W-1:0]         mul_product_out
);

    wire [DATA_W-1:0] rf_rd_data;
    reg  [DATA_W-1:0] src_a_mux;
    reg  [DATA_W-1:0] src_b_mux;
    wire [DATA_W-1:0] core_out;
    wire [DATA_W-1:0] core_mesh_ctx_result;

    reg [DATA_W-1:0] core_src_a;
    reg [DATA_W-1:0] core_src_b;
    reg [3:0] core_pe_op;
    reg [15:0] core_imm16;
    reg [1:0] core_mesh_ctx_mode;
    reg [IDX_W-1:0] core_mesh_ctx_base_idx;
    reg [IDX_W-1:0] core_mesh_ctx_limit;
    reg [DATA_W-1:0] core_mesh_ctx_threshold;
    reg [3:0] core_mesh_ctx_shift;
    reg [DATA_W-1:0] core_mesh_ctx_x;
    reg [DATA_W-1:0] core_mesh_ctx_delta;
    reg core_mesh_ctx_keep;
    reg [1:0] core_rf_rd_addr;
    reg [1:0] core_rf_wr_addr;
    reg core_rf_wr_en;
    // Latency-elastic execution token for the registered core payload.  The
    // operands and controls below already crossed a tile-local register, but
    // driving pe_core.ce directly from tile_en allowed the controller/state
    // decode to remain on the MAC capture edge.  Carrying validity through
    // the same boundary makes the transaction atomic: payload stays local to
    // the PE while only this one-bit phase token advances.
    reg core_phase_valid_q;
    // These are intentional per-tile timing cut points. Preserve them so
    // synthesis cannot merge the local enables back into the sparse
    // controller state decode and recreate a controller-to-32-PE fanout path.
    (* dont_touch = "true" *) reg core_acc_clear;
    (* dont_touch = "true" *) reg core_acc_en;
    reg [IDX_W-1:0] core_idx_a;
    reg [IDX_W-1:0] core_idx_b;

    // Correlation and mesh-context transactions intentionally use the
    // PE0->PE3 single-hop wavefront.  They bypass the generic input payload
    // stage and therefore also bypass its phase-valid token.  Suppressing
    // capture while bypass is active prevents the final wavefront token from
    // being replayed through the registered path during drain.
    wire mesh_ctx_ingress_active = ENABLE_MESH_CTX &&
                                   (mesh_ctx_mode != 2'd0);
    wire vertical_ingress_active = mesh_ctx_ingress_active ||
                                   corr_wavefront_active;

    function signed [DATA_W-1:0] imm16_to_q;
        input [15:0] value;
        reg [DATA_W-1:0] ext;
        begin
            ext = {{(DATA_W-16){1'b0}}, value};
            if (Q_FRAC_W >= 16)
                imm16_to_q = $signed(ext <<< (Q_FRAC_W - 16));
            else
                imm16_to_q = $signed(ext >> (16 - Q_FRAC_W));
        end
    endfunction

    wire [DATA_W-1:0] imm_data = imm16_to_q(imm16);

    always @(*) begin
        case (src_a_sel)
            3'd0:    src_a_mux = inN;
            3'd1:    src_a_mux = inS;
            3'd2:    src_a_mux = inE;
            3'd3:    src_a_mux = inW;
            3'd4:    src_a_mux = rf_rd_data;
            3'd5:    src_a_mux = imm_data;
            3'd6:    src_a_mux = spm_a_data;
            3'd7:    src_a_mux = phi_data;
            default: src_a_mux = {DATA_W{1'b0}};
        endcase
    end

    always @(*) begin
        case (src_b_sel)
            3'd0:    src_b_mux = inN;
            3'd1:    src_b_mux = inS;
            3'd2:    src_b_mux = inE;
            3'd3:    src_b_mux = inW;
            3'd4:    src_b_mux = rf_rd_data;
            3'd5:    src_b_mux = imm_data;
            3'd6:    src_b_mux = spm_b_data;
            3'd7:    src_b_mux = ext_b_is_scalar ? scalar_data : colbus_data;
            default: src_b_mux = {DATA_W{1'b0}};
        endcase
    end


    generate
        if (PIPE_CORE_IN) begin : gen_core_input_pipe
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    core_src_a <= {DATA_W{1'b0}};
                    core_src_b <= {DATA_W{1'b0}};
                    core_pe_op <= 4'd7;
                    core_imm16 <= 16'd0;
                    core_mesh_ctx_mode <= 2'd0;
                    core_mesh_ctx_base_idx <= {IDX_W{1'b0}};
                    core_mesh_ctx_limit <= {IDX_W{1'b0}};
                    core_mesh_ctx_threshold <= {DATA_W{1'b0}};
                    core_mesh_ctx_shift <= 4'd0;
                    core_mesh_ctx_x <= {DATA_W{1'b0}};
                    core_mesh_ctx_delta <= {DATA_W{1'b0}};
                    core_mesh_ctx_keep <= 1'b0;
                core_rf_rd_addr <= 2'd0;
                core_rf_wr_addr <= 2'd0;
                core_rf_wr_en <= 1'b0;
                core_phase_valid_q <= 1'b0;
                core_acc_clear <= 1'b0;
                core_acc_en <= 1'b0;
                core_idx_a <= {IDX_W{1'b0}};
                core_idx_b <= {IDX_W{1'b0}};
            end else begin
                core_phase_valid_q <= tile_en && !vertical_ingress_active;
                if (tile_en && !vertical_ingress_active) begin
                    core_src_a <= src_a_mux;
                    core_src_b <= src_b_mux;
                    core_pe_op <= pe_op;
                    core_imm16 <= imm16;
                    core_mesh_ctx_mode <= ENABLE_MESH_CTX ? mesh_ctx_mode : 2'd0;
                    core_mesh_ctx_base_idx <= mesh_ctx_base_idx;
                    core_mesh_ctx_limit <= mesh_ctx_limit;
                    core_mesh_ctx_threshold <= mesh_ctx_threshold;
                    core_mesh_ctx_shift <= mesh_ctx_shift;
                    core_mesh_ctx_x <= mesh_ctx_x;
                    core_mesh_ctx_delta <= mesh_ctx_delta;
                    core_mesh_ctx_keep <= mesh_ctx_keep;
                    core_rf_rd_addr <= rf_rd_addr;
                    core_rf_wr_addr <= rf_wr_addr;
                    core_rf_wr_en <= rf_wr_en;
                    core_acc_clear <= acc_clear;
                    core_acc_en <= acc_en;
                    core_idx_a <= idxW_in;
                    core_idx_b <= idxE_in;
                end
            end
            end
        end else begin : gen_core_input_comb
            always @(*) begin
                core_src_a = src_a_mux;
                core_src_b = src_b_mux;
                core_pe_op = pe_op;
                core_imm16 = imm16;
                core_mesh_ctx_mode = ENABLE_MESH_CTX ? mesh_ctx_mode : 2'd0;
                core_mesh_ctx_base_idx = mesh_ctx_base_idx;
                core_mesh_ctx_limit = mesh_ctx_limit;
                core_mesh_ctx_threshold = mesh_ctx_threshold;
                core_mesh_ctx_shift = mesh_ctx_shift;
                core_mesh_ctx_x = mesh_ctx_x;
                core_mesh_ctx_delta = mesh_ctx_delta;
                core_mesh_ctx_keep = mesh_ctx_keep;
                core_rf_rd_addr = rf_rd_addr;
                core_rf_wr_addr = rf_wr_addr;
                core_rf_wr_en = rf_wr_en;
                core_acc_clear = acc_clear;
                core_acc_en = acc_en;
                core_idx_a = idxW_in;
                core_idx_b = idxE_in;
            end
        end
    endgenerate
    // Mesh-context tokens bypass the generic core-input register.  The
    // inter-PE outS register remains enabled, so a token advances exactly one
    // physical row per clock.  Non-mesh contexts keep the timing-isolating
    // core-input register unchanged.
    // Residual products use the normal core input register. The controller
    // carries a matching extra valid stage, so the PE0 -> PE3 wavefront keeps
    // its ordering while the wide multiplier no longer starts at the sparse
    // controller/state mux. Correlation and mesh contexts retain their signed-
    // off single-hop bypass schedules.
    wire [DATA_W-1:0] core_src_a_i = vertical_ingress_active ? src_a_mux : core_src_a;
    wire [DATA_W-1:0] core_src_b_i = vertical_ingress_active ? src_b_mux : core_src_b;
    wire [3:0] core_pe_op_i = vertical_ingress_active ? pe_op : core_pe_op;
    wire [15:0] core_imm16_i = vertical_ingress_active ? imm16 : core_imm16;
    wire [1:0] core_mesh_ctx_mode_i = mesh_ctx_ingress_active ? mesh_ctx_mode : core_mesh_ctx_mode;
    wire [IDX_W-1:0] core_mesh_ctx_base_idx_i = mesh_ctx_ingress_active ? mesh_ctx_base_idx : core_mesh_ctx_base_idx;
    wire [IDX_W-1:0] core_mesh_ctx_limit_i = mesh_ctx_ingress_active ? mesh_ctx_limit : core_mesh_ctx_limit;
    wire [DATA_W-1:0] core_mesh_ctx_threshold_i = mesh_ctx_ingress_active ? mesh_ctx_threshold : core_mesh_ctx_threshold;
    wire [3:0] core_mesh_ctx_shift_i = mesh_ctx_ingress_active ? mesh_ctx_shift : core_mesh_ctx_shift;
    wire [DATA_W-1:0] core_mesh_ctx_x_i = mesh_ctx_ingress_active ? mesh_ctx_x : core_mesh_ctx_x;
    wire [DATA_W-1:0] core_mesh_ctx_delta_i = mesh_ctx_ingress_active ? mesh_ctx_delta : core_mesh_ctx_delta;
    wire core_mesh_ctx_keep_i = mesh_ctx_ingress_active ? mesh_ctx_keep : core_mesh_ctx_keep;
    // The RF write token follows the same rule as the accumulator token
    // above: during the single-hop vertical bypass the registered copy
    // belongs to the instruction frozen before the bypass, and ce is high
    // every bypass clock, so the stale token would replay an RF write of the
    // mesh/corr result on every beat.  Take the live decode instead.
    wire [1:0] core_rf_wr_addr_i = vertical_ingress_active ? rf_wr_addr : core_rf_wr_addr;
    wire core_rf_wr_en_i = vertical_ingress_active ? rf_wr_en : core_rf_wr_en;
    // Once correlation uses the combinational wavefront bypass, its registered
    // acc_en copy must not replay the last owner token during pipeline drain.
    wire core_acc_clear_i = vertical_ingress_active ? acc_clear : core_acc_clear;
    wire core_acc_en_i = vertical_ingress_active ? acc_en :
                         (corr_pipeline_active ? 1'b0 : core_acc_en);
    wire core_ce_i = vertical_ingress_active ? tile_en : core_phase_valid_q;

    pe_core #(
        .DATA_W(DATA_W), .ACC_W(ACC_W), .RF_DEPTH(4),
        .Q_FRAC_W(Q_FRAC_W), .IDX_W(IDX_W), .ROW_ID(ROW_ID), .GLOBAL_COL(GLOBAL_COL), .ENABLE_MESH_CTX(ENABLE_MESH_CTX)
    ) u_core (
        .clk(clk), .rst_n(rst_n), .ce(core_ce_i),
        .src_a(core_src_a_i), .src_b(core_src_b_i), .pe_op(core_pe_op_i), .imm16(core_imm16_i),
        .mesh_ctx_mode(core_mesh_ctx_mode_i),
        .mesh_ctx_base_idx(core_mesh_ctx_base_idx_i), .mesh_ctx_limit(core_mesh_ctx_limit_i), .mesh_ctx_threshold(core_mesh_ctx_threshold_i), .mesh_ctx_shift(core_mesh_ctx_shift_i), .mesh_ctx_x(core_mesh_ctx_x_i), .mesh_ctx_delta(core_mesh_ctx_delta_i), .mesh_ctx_keep(core_mesh_ctx_keep_i),
        .rf_rd_addr(core_rf_rd_addr), .rf_wr_addr(core_rf_wr_addr_i), .rf_wr_en(core_rf_wr_en_i),
        .acc_clear(core_acc_clear_i), .acc_en(core_acc_en_i),
        .idx_a(core_idx_a), .idx_b(core_idx_b), .idx_out(idx_out),
        .pe_out(core_out), .mesh_ctx_result_out(core_mesh_ctx_result), .acc_out(acc_out), .mul_product_out(mul_product_out), .rf_rd_data(rf_rd_data)
    );

    function [DATA_W-1:0] sat_acc_q;
        input signed [ACC_W-1:0] value;
        reg signed [ACC_W:0] rounded;
        reg signed [ACC_W:0] shifted;
        begin
            if (Q_FRAC_W > 0)
                rounded = {value[ACC_W-1], value} + (value[ACC_W-1] ? -($signed(1) <<< (Q_FRAC_W-1)) : ($signed(1) <<< (Q_FRAC_W-1)));
            else
                rounded = {value[ACC_W-1], value};
            shifted = rounded >>> Q_FRAC_W;
            if (!shifted[ACC_W] && |shifted[ACC_W-1:DATA_W-1])
                sat_acc_q = {1'b0, {(DATA_W-1){1'b1}}};
            else if (shifted[ACC_W] && ~&shifted[ACC_W-1:DATA_W-1])
                sat_acc_q = {1'b1, {(DATA_W-1){1'b0}}};
            else
                sat_acc_q = shifted[DATA_W-1:0];
        end
    endfunction

    reg [DATA_W-1:0] selected_out;
    always @(*) begin
        if (!FULL_OUT_MUX) begin
            selected_out = core_out;
        end else begin
            case (out_sel)
                4'd0:    selected_out = core_out;
                4'd1:    selected_out = sat_acc_q(acc_out);
                4'd2:    selected_out = acc_out[DATA_W-1:0];
                4'd3:    selected_out = core_out[DATA_W-1] ? (~core_out + 1'b1) : core_out;
                default: selected_out = core_out;
            endcase
        end
    end

    wire mesh_ctx_active_w = ENABLE_MESH_CTX && (core_mesh_ctx_mode_i != 2'd0);
    wire [DATA_W-1:0] mesh_out_data_w = mesh_ctx_active_w ? core_mesh_ctx_result : selected_out;
    assign pe_data_out = mesh_out_data_w;
    assign mesh_ctx_data_out = ENABLE_MESH_CTX ? core_mesh_ctx_result : {DATA_W{1'b0}};

    // combinational switchbox outputs
    wire [DATA_W-1:0] sbN, sbS, sbE, sbW;
    wire [IDX_W-1:0]  sbE_idx, sbW_idx;
    switchbox #(.DATA_W(DATA_W), .IDX_W(IDX_W)) u_switchbox (
        .inN(inN), .inS(inS), .inE(inE), .inW(inW), .inPE(mesh_out_data_w),
        .inN_idx({IDX_W{1'b0}}), .inS_idx({IDX_W{1'b0}}),
        .inE_idx(idxE_in), .inW_idx(idxW_in), .inPE_idx(idx_self),
        .sel(sb_sel_en ? sb_sel : 3'd4),
        .outN(sbN), .outS(sbS), .outE(sbE), .outW(sbW), .outPE(),
        .outN_idx(), .outS_idx(), .outE_idx(sbE_idx), .outW_idx(sbW_idx), .outPE_idx()
    );

    // v3: pipeline the inter-PE mesh hops (cuts long horizontal comb chain)
    generate
        if (PIPE_MESH) begin : gen_pipe
            reg [DATA_W-1:0] rN, rS, rE, rW;
            reg [IDX_W-1:0]  rEi, rWi;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    rN<=0; rS<=0; rE<=0; rW<=0; rEi<=0; rWi<=0;
                end else if (tile_en) begin
                    rN<=sbN; rS<=sbS; rE<=sbE; rW<=sbW; rEi<=sbE_idx; rWi<=sbW_idx;
                end
            end
            assign outN=rN; assign outS=rS; assign outE=rE; assign outW=rW;
            assign idxE_out=rEi; assign idxW_out=rWi;
        end else begin : gen_comb
            assign outN=sbN; assign outS=sbS; assign outE=sbE; assign outW=sbW;
            assign idxE_out=sbE_idx; assign idxW_out=sbW_idx;
        end
    endgenerate

endmodule













