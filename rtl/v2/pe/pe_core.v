module pe_core #(
    parameter integer DATA_W   = 24,
    parameter integer ACC_W    = 64,
    parameter integer RF_DEPTH = 4,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter integer IDX_W    = 10,
    parameter integer ROW_ID   = 0,
    parameter integer GLOBAL_COL = 0,
    parameter integer ENABLE_MESH_CTX = 1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     ce,

    input  wire [DATA_W-1:0]        src_a,
    input  wire [DATA_W-1:0]        src_b,
    input  wire [3:0]               pe_op,
    input  wire [15:0]              imm16,
    input  wire [1:0]               mesh_ctx_mode,
    input  wire [IDX_W-1:0]         mesh_ctx_base_idx,
    input  wire [IDX_W-1:0]         mesh_ctx_limit,
    input  wire [DATA_W-1:0]        mesh_ctx_threshold,
    input  wire [3:0]               mesh_ctx_shift,
    input  wire [DATA_W-1:0]        mesh_ctx_x,
    input  wire [DATA_W-1:0]        mesh_ctx_delta,
    input  wire                     mesh_ctx_keep,

    input  wire [1:0]               rf_rd_addr,
    input  wire [1:0]               rf_wr_addr,
    input  wire                     rf_wr_en,
    input  wire                     acc_clear,
    input  wire                     acc_en,

    input  wire [IDX_W-1:0]         idx_a,
    input  wire [IDX_W-1:0]         idx_b,
    output reg  [IDX_W-1:0]         idx_out,

    output reg  [DATA_W-1:0]        pe_out,
    output reg  [DATA_W-1:0]        mesh_ctx_result_out,
    output wire [ACC_W-1:0]         acc_out,
    output wire [ACC_W-1:0]         mul_product_out,
    output wire [DATA_W-1:0]        rf_rd_data
);

    localparam [3:0] OP_MAC     = 4'd0;
    localparam [3:0] OP_ADD     = 4'd1;
    localparam [3:0] OP_SUB     = 4'd2;
    localparam [3:0] OP_ABS     = 4'd3;
    localparam [3:0] OP_CMP     = 4'd4;
    localparam [3:0] OP_SGN     = 4'd5;
    localparam [3:0] OP_SHT     = 4'd6;
    localparam [3:0] OP_PASS    = 4'd7;
    localparam [3:0] OP_SAT_ADD_SHIFT = 4'd8; // src_a + (src_b >>> imm16[3:0]), saturated
    localparam [1:0] MESH_CTX_NONE   = 2'd0;
    localparam [1:0] MESH_CTX_UPDATE = 2'd1;
    localparam [1:0] MESH_CTX_PRUNE  = 2'd2;
    localparam [1:0] MESH_CTX_RESID  = 2'd3;

    localparam signed [DATA_W-1:0] DATA_MAX = {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] DATA_MIN = {1'b1, {(DATA_W-1){1'b0}}};
    localparam signed [ACC_W-1:0]  ACC_MAX  = {1'b0, {(ACC_W-1){1'b1}}};
    localparam signed [ACC_W-1:0]  ACC_MIN  = {1'b1, {(ACC_W-1){1'b0}}};
    localparam [DATA_W-1:0] Q_ONE = {{(DATA_W-Q_FRAC_W-1){1'b0}}, 1'b1, {Q_FRAC_W{1'b0}}};

    integer i;
    reg [DATA_W-1:0] rf [0:RF_DEPTH-1];
    reg signed [ACC_W-1:0]  acc;
    // Shared registered product-token boundary.  Every MAC-class transaction
    // (including LS, residual and border work with acc_en deasserted) captures
    // its product here.  Both the local accumulator and the external wide
    // collectors consume this registered value, so controller/state decode,
    // operand selection and the 24x24 multiplier can never share a capture
    // edge with residual/Gram/LDLT completion arithmetic.  The product data is
    // reset to zero; validity/control still guards observation.
    reg signed [ACC_W-1:0] mac_product_q;
    reg                    mac_valid_q;
    reg                    mac_clear_q;

    assign acc_out    = acc;
    assign rf_rd_data = rf[rf_rd_addr];

    localparam [IDX_W-1:0] GLOBAL_COL_IDX = GLOBAL_COL;
    wire this_is_row0 = (ROW_ID == 0);
    wire this_is_row1 = (ROW_ID == 1);
    wire this_is_row2 = (ROW_ID == 2);
    wire this_is_row3 = (ROW_ID == 3);
    wire [IDX_W-1:0] mesh_ctx_lane_idx = mesh_ctx_base_idx + GLOBAL_COL_IDX;
    wire mesh_ctx_lane_in_range = (mesh_ctx_lane_idx < mesh_ctx_limit);
    wire signed [DATA_W-1:0] mesh_ctx_x_s = $signed(mesh_ctx_x);
    wire signed [DATA_W-1:0] mesh_ctx_delta_s = $signed(mesh_ctx_delta);
    wire signed [DATA_W-1:0] a_s = $signed(src_a);
    wire signed [DATA_W-1:0] b_s = $signed(src_b);

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

    wire signed [DATA_W-1:0] imm_s = imm16_to_q(imm16);

    wire signed [ACC_W-1:0] a_ext = $signed(src_a);
    wire signed [ACC_W-1:0] b_ext = $signed(src_b);

    wire signed [ACC_W:0] add_wide     = {a_ext[ACC_W-1], a_ext} + {b_ext[ACC_W-1], b_ext};
    wire signed [ACC_W:0] sub_wide     = {a_ext[ACC_W-1], a_ext} - {b_ext[ACC_W-1], b_ext};

    function [DATA_W-1:0] sat_data;
        input signed [ACC_W:0] value;
        begin
            if (!value[ACC_W] && |value[ACC_W-1:DATA_W-1])
                sat_data = DATA_MAX[DATA_W-1:0];
            else if (value[ACC_W] && ~&value[ACC_W-1:DATA_W-1])
                sat_data = DATA_MIN[DATA_W-1:0];
            else
                sat_data = value[DATA_W-1:0];
        end
    endfunction

    function [ACC_W-1:0] sat_acc;
        input signed [ACC_W:0] value;
        begin
            if (!value[ACC_W] && value[ACC_W-1])
                sat_acc = ACC_MAX[ACC_W-1:0];
            else if (value[ACC_W] && !value[ACC_W-1])
                sat_acc = ACC_MIN[ACC_W-1:0];
            else
                sat_acc = value[ACC_W-1:0];
        end
    endfunction

    function [DATA_W-1:0] acc_to_q;
        input signed [ACC_W-1:0] value;
        reg signed [ACC_W:0] rounded;
        reg signed [ACC_W:0] shifted;
        begin
            if (Q_FRAC_W > 0)
                rounded = {value[ACC_W-1], value} + (value[ACC_W-1] ? -($signed(1) <<< (Q_FRAC_W-1)) : ($signed(1) <<< (Q_FRAC_W-1)));
            else
                rounded = {value[ACC_W-1], value};
            shifted  = rounded >>> Q_FRAC_W;
            acc_to_q = sat_data(shifted);
        end
    endfunction

    function [DATA_W-1:0] abs_sat;
        input signed [DATA_W-1:0] value;
        begin
            if (value == DATA_MIN)      abs_sat = DATA_MAX[DATA_W-1:0];
            else if (value[DATA_W-1])   abs_sat = -value;
            else                        abs_sat = value;
        end
    endfunction

    wire [DATA_W-1:0]        abs_a    = abs_sat(a_s);
    wire signed [DATA_W-1:0] abs_a_s  = $signed(abs_a);
    wire signed [DATA_W:0]   sht_diff = {1'b0, abs_a_s} - {imm_s[DATA_W-1], imm_s};
    wire [DATA_W-1:0]        sht_mag  = (sht_diff <= 0) ? {DATA_W{1'b0}} :
                                        sat_data({{(ACC_W-DATA_W){sht_diff[DATA_W]}}, sht_diff});
    wire [DATA_W-1:0]        sht_out  = (sht_mag == {DATA_W{1'b0}}) ? {DATA_W{1'b0}} :
                                        (a_s[DATA_W-1] ? (~sht_mag + 1'b1) : sht_mag);

    wire [DATA_W-1:0]        abs_b      = abs_sat(b_s);
    wire signed [DATA_W-1:0] abs_b_s    = $signed(abs_b);
    wire                     a_ge_b     = (a_s >= b_s);
    wire                     a_le_b     = (a_s <= b_s);
    wire                     a_lt_b     = (a_s <  b_s);
    wire                     a_eq_b     = (a_s == b_s);
    wire                     a_wins_abs = (abs_a_s >= abs_b_s);
    wire [DATA_W-1:0]        cmpidx_out = a_wins_abs ? src_a : src_b;

    wire signed [DATA_W-1:0] mul_a_s = a_s;
    wire signed [DATA_W-1:0] mul_b_s = b_s;
    wire signed [(2*DATA_W)-1:0] prod_full = mul_a_s * mul_b_s;
    wire signed [ACC_W-1:0]      prod_ext  = $signed(prod_full);
    assign mul_product_out = mac_product_q;
    wire signed [ACC_W:0] acc_add_wide =
        {acc[ACC_W-1], acc} + {mac_product_q[ACC_W-1], mac_product_q};
    wire signed [ACC_W:0] acc_clear_mac_wide =
        {mac_product_q[ACC_W-1], mac_product_q};
    wire [ACC_W-1:0] acc_mac_next       = sat_acc(acc_add_wide);
    wire [ACC_W-1:0] acc_mac_clear_next = sat_acc(acc_clear_mac_wide);

    wire [4:0] shift_amt = imm16[4:0];
    wire       shift_right = imm16[5];
    wire signed [ACC_W-1:0] shift_left_ext = a_ext <<< shift_amt;
    wire signed [ACC_W-1:0] shift_right_ext = a_ext >>> shift_amt;
    wire signed [ACC_W:0] shift_wide =
        shift_right ? {shift_right_ext[ACC_W-1], shift_right_ext} :
                      {shift_left_ext[ACC_W-1], shift_left_ext};

    wire signed [DATA_W-1:0] sat_add_shift_b = b_s >>> imm16[3:0];
    wire signed [DATA_W-1:0] mesh_ctx_update_delta_s = mesh_ctx_delta_s >>> mesh_ctx_shift;
    wire signed [ACC_W:0] mesh_ctx_update_wide =
        {{(ACC_W-DATA_W+1){mesh_ctx_x_s[DATA_W-1]}}, mesh_ctx_x_s} +
        {{(ACC_W-DATA_W+1){a_s[DATA_W-1]}}, a_s};
    wire signed [ACC_W:0] mesh_ctx_resid_wide =
        {{(ACC_W-DATA_W+1){mesh_ctx_x_s[DATA_W-1]}}, mesh_ctx_x_s} -
        {{(ACC_W-DATA_W+1){a_s[DATA_W-1]}}, a_s};
    wire signed [ACC_W:0] sat_add_shift_wide =
        {{(ACC_W-DATA_W+1){a_s[DATA_W-1]}}, a_s} +
        {{(ACC_W-DATA_W+1){sat_add_shift_b[DATA_W-1]}}, sat_add_shift_b};

    wire cmpflag_value =
        (imm16[1:0] == 2'd0) ? a_le_b :
        (imm16[1:0] == 2'd1) ? a_eq_b :
        (imm16[1:0] == 2'd2) ? a_lt_b :
                                a_wins_abs;

    function [DATA_W-1:0] const_sel;
        input [15:0] sel;
        begin
            case (sel[3:0])
                4'd0: const_sel = {DATA_W{1'b0}};
                4'd1: const_sel = Q_ONE;
                4'd2: const_sel = {{(DATA_W-Q_FRAC_W){1'b0}}, 1'b1, {(Q_FRAC_W-1){1'b0}}};
                4'd3: const_sel = Q_ONE + {{(DATA_W-Q_FRAC_W){1'b0}}, 1'b1, {(Q_FRAC_W-1){1'b0}}};
                4'd4: const_sel = Q_ONE <<< 1;
                4'd5: const_sel = -$signed(Q_ONE);
                4'd6: const_sel = -$signed({{(DATA_W-Q_FRAC_W){1'b0}}, 1'b1, {(Q_FRAC_W-1){1'b0}}});
                default: const_sel = imm16_to_q(sel);
            endcase
        end
    endfunction

    // --- Combinational output mux ---
    reg [DATA_W-1:0]  comb_out;
    reg [IDX_W-1:0]   comb_idx;
    reg [DATA_W-1:0]  mac_out_pipe;

    always @(*) begin
        comb_idx          = idx_a;
        mesh_ctx_result_out = {DATA_W{1'b0}};
        case (pe_op)
            OP_MAC:    comb_out = mac_out_pipe;
            OP_ADD:    comb_out = sat_data(add_wide);
            OP_SUB:    comb_out = sat_data(sub_wide);
            OP_ABS:    comb_out = abs_a;
            OP_CMP:    comb_out = a_ge_b ? src_a : src_b;
            OP_SGN:    comb_out = (a_s > 0) ? Q_ONE : ((a_s == 0) ? {DATA_W{1'b0}} : -$signed(Q_ONE));
            OP_SHT:    comb_out = sht_out;
            OP_PASS:   comb_out = src_a;
            OP_SAT_ADD_SHIFT: comb_out = sat_data(sat_add_shift_wide);
            default:   comb_out = {DATA_W{1'b0}};
        endcase
        if (ENABLE_MESH_CTX && (mesh_ctx_mode != MESH_CTX_NONE)) begin
            if (mesh_ctx_mode == MESH_CTX_UPDATE) begin
                if (this_is_row0)
                    comb_out = mesh_ctx_update_delta_s[DATA_W-1:0];
                else if (this_is_row1)
                    // src_a is the shifted delta forwarded by row 0; x is a
                    // registered sideband that followed the same vertical hop.
                    comb_out = sat_data(mesh_ctx_update_wide);
                else if (this_is_row2)
                    comb_out = mesh_ctx_keep ? src_a : {DATA_W{1'b0}};
                else if (this_is_row3)
                    comb_out = mesh_ctx_lane_in_range ? src_a : {DATA_W{1'b0}};
            end else if (mesh_ctx_mode == MESH_CTX_PRUNE) begin
                if (this_is_row0)
                    comb_out = mesh_ctx_delta;
                else if (this_is_row1)
                    comb_out = (abs_a >= mesh_ctx_threshold) ? src_a : {DATA_W{1'b0}};
                else if (this_is_row2)
                    comb_out = mesh_ctx_keep ? src_a : {DATA_W{1'b0}};
                else if (this_is_row3)
                    comb_out = mesh_ctx_lane_in_range ? src_a : {DATA_W{1'b0}};
            end else begin
                if (this_is_row0)
                    comb_out = mesh_ctx_delta;
                else if (this_is_row1)
                    // src_a is the dot-product delta forwarded by row 0.
                    comb_out = sat_data(mesh_ctx_resid_wide);
                else if (this_is_row2)
                    comb_out = mesh_ctx_keep ? src_a : {DATA_W{1'b0}};
                else if (this_is_row3)
                    comb_out = mesh_ctx_lane_in_range ? src_a : {DATA_W{1'b0}};
            end
            mesh_ctx_result_out = comb_out;
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc    <= {ACC_W{1'b0}};
            mac_product_q <= {ACC_W{1'b0}};
            mac_valid_q <= 1'b0;
            mac_clear_q <= 1'b0;
            pe_out <= {DATA_W{1'b0}};
            mac_out_pipe <= {DATA_W{1'b0}};
            idx_out <= {IDX_W{1'b0}};
            for (i = 0; i < RF_DEPTH; i = i + 1)
                rf[i] <= {DATA_W{1'b0}};
        end else begin
            // Capture a product token for every MAC operation, even when the
            // transaction is a wide LS/residual operation that does not update
            // the local accumulator. Continuous streams retain II=1.
            mac_valid_q <= ce && acc_en && (pe_op == OP_MAC);
            if (ce && (pe_op == OP_MAC))
                mac_product_q <= prod_ext;
            if (ce && acc_en && (pe_op == OP_MAC)) begin
                mac_clear_q <= acc_clear;
            end

            // Commit the preceding registered product.  No state/mode decode
            // or multiplier is present on this accumulator feedback edge.
            if (mac_valid_q) begin
                acc <= mac_clear_q ? acc_mac_clear_next : acc_mac_next;
            end else if (ce && acc_clear) begin
                acc <= {ACC_W{1'b0}};
            end

            if (ce) begin
                // Convert the already-registered accumulator instead of
                // chaining accumulator feedback and Q conversion.
                mac_out_pipe <= acc_to_q(acc);
                pe_out <= comb_out;
                idx_out <= comb_idx;

                if (rf_wr_en)
                    rf[rf_wr_addr] <= comb_out;
            end
        end
    end
endmodule
