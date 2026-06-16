module pe_core #(
    parameter integer DATA_W   = 24,
    parameter integer ACC_W    = 64,
    parameter integer RF_DEPTH = 4,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter integer IDX_W    = 10,
    parameter integer SCALAR_FN = 0   // 1: enable scalar-lane ops (LZNORM/DENORM/RSEED)
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     ce,

    input  wire [DATA_W-1:0]        src_a,
    input  wire [DATA_W-1:0]        src_b,
    input  wire [4:0]               pe_op,   // v3: 5-bit ({ctx[3],ctx[2],ctx[15:13]})
    input  wire [15:0]              imm16,

    input  wire [1:0]               rf_rd_addr,
    input  wire [1:0]               rf_wr_addr,
    input  wire                     rf_wr_en,
    input  wire                     acc_clear,
    input  wire                     acc_en,

    input  wire [IDX_W-1:0]         idx_a,
    input  wire [IDX_W-1:0]         idx_b,
    output reg  [IDX_W-1:0]         idx_out,

    output reg  [DATA_W-1:0]        pe_out,
    output wire [ACC_W-1:0]         acc_out,
    output wire [DATA_W-1:0]        rf_rd_data
);

    localparam [4:0] OP_MAC     = 5'd0;
    localparam [4:0] OP_ADD     = 5'd1;
    localparam [4:0] OP_SUB     = 5'd2;
    localparam [4:0] OP_ABS     = 5'd3;
    localparam [4:0] OP_CMP     = 5'd4;
    localparam [4:0] OP_SGN     = 5'd5;
    localparam [4:0] OP_SHT     = 5'd6;
    localparam [4:0] OP_PASS    = 5'd7;
    localparam [4:0] OP_CMPIDX  = 5'd8;
    localparam [4:0] OP_MINA    = 5'd9;
    localparam [4:0] OP_MACABS  = 5'd10;
    localparam [4:0] OP_NORM1   = 5'd11;
    localparam [4:0] OP_MUL     = 5'd12;
    localparam [4:0] OP_SHIFT   = 5'd13;
    localparam [4:0] OP_CMPFLAG = 5'd14;
    localparam [4:0] OP_CONST   = 5'd15;
    // --- v3 extended ops (pe_op[4]=1) ---
    localparam [4:0] OP_IDXMAX  = 5'd16;
    localparam [4:0] OP_LZNORM  = 5'd17;
    localparam [4:0] OP_SELECT  = 5'd18;
    localparam [4:0] OP_DENORM  = 5'd19;
    localparam [4:0] OP_RSEED   = 5'd20;

    localparam signed [DATA_W-1:0] DATA_MAX = {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] DATA_MIN = {1'b1, {(DATA_W-1){1'b0}}};
    localparam signed [ACC_W-1:0]  ACC_MAX  = {1'b0, {(ACC_W-1){1'b1}}};
    localparam signed [ACC_W-1:0]  ACC_MIN  = {1'b1, {(ACC_W-1){1'b0}}};
    localparam [DATA_W-1:0] Q_ONE = {{(DATA_W-Q_FRAC_W-1){1'b0}}, 1'b1, {Q_FRAC_W{1'b0}}};

    integer i;
    reg [DATA_W-1:0] rf [0:RF_DEPTH-1];
    reg signed [ACC_W-1:0]  acc;

    assign acc_out    = acc;
    assign rf_rd_data = rf[rf_rd_addr];

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

    wire signed [DATA_W-1:0] mul_a_s = (pe_op == OP_MACABS) ? abs_a_s : a_s;
    wire signed [DATA_W-1:0] mul_b_s = (pe_op == OP_MACABS) ? abs_b_s : b_s;
    wire signed [(2*DATA_W)-1:0] prod_full = mul_a_s * mul_b_s;
    wire signed [ACC_W-1:0]      prod_ext  = $signed(prod_full);
    wire signed [ACC_W:0] acc_add_wide = {acc[ACC_W-1], acc} + {prod_ext[ACC_W-1], prod_ext};
    wire signed [ACC_W:0] prod_round_ext = {prod_ext[ACC_W-1], prod_ext} + (prod_ext[ACC_W-1] ? -($signed(1) <<< (Q_FRAC_W-1)) : ($signed(1) <<< (Q_FRAC_W-1)));
    wire signed [ACC_W-1:0] prod_q_ext = prod_round_ext >>> Q_FRAC_W;
    wire signed [ACC_W:0] mul_q_wide = {prod_q_ext[ACC_W-1], prod_q_ext};
    wire signed [ACC_W:0] acc_macabs_wide = {acc[ACC_W-1], acc} + {prod_ext[ACC_W-1], prod_ext};

    wire signed [ACC_W-1:0] abs_a_acc_q = $signed({{(ACC_W-DATA_W){1'b0}}, abs_a_s}) <<< Q_FRAC_W;
    wire signed [ACC_W:0] acc_norm1_wide = {acc[ACC_W-1], acc} + {abs_a_acc_q[ACC_W-1], abs_a_acc_q};
    wire signed [ACC_W:0] acc_clear_mac_wide    = {prod_ext[ACC_W-1], prod_ext};
    wire signed [ACC_W:0] acc_clear_macabs_wide = {prod_ext[ACC_W-1], prod_ext};
    wire signed [ACC_W:0] acc_clear_norm1_wide  = {abs_a_acc_q[ACC_W-1], abs_a_acc_q};
    wire [ACC_W-1:0] acc_mac_next          = sat_acc(acc_add_wide);
    wire [ACC_W-1:0] acc_macabs_next       = sat_acc(acc_macabs_wide);
    wire [ACC_W-1:0] acc_norm1_next        = sat_acc(acc_norm1_wide);
    wire [ACC_W-1:0] acc_mac_clear_next    = sat_acc(acc_clear_mac_wide);
    wire [ACC_W-1:0] acc_macabs_clear_next = sat_acc(acc_clear_macabs_wide);
    wire [ACC_W-1:0] acc_norm1_clear_next  = sat_acc(acc_clear_norm1_wide);

    wire [4:0] shift_amt = imm16[4:0];
    wire       shift_right = imm16[5];
    wire signed [ACC_W-1:0] shift_left_ext = a_ext <<< shift_amt;
    wire signed [ACC_W-1:0] shift_right_ext = a_ext >>> shift_amt;
    wire signed [ACC_W:0] shift_wide =
        shift_right ? {shift_right_ext[ACC_W-1], shift_right_ext} :
                      {shift_left_ext[ACC_W-1], shift_left_ext};

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

    // --- v3: leading-bit normalize for reciprocal/rsqrt ---
    function integer find_msb;
        input [DATA_W-1:0] value;
        integer j;
        begin
            find_msb = 0;
            for (j = 0; j < DATA_W; j = j + 1)
                if (value[j]) find_msb = j;
        end
    endfunction

    localparam integer NORM_BIT = Q_FRAC_W - 1; // target MSB pos -> value in [0.5,1.0)
    wire [DATA_W-1:0]   lz_abs   = abs_a;
    wire signed [7:0]   lz_shift = $signed(NORM_BIT[7:0]) - $signed(find_msb(lz_abs));
    wire [DATA_W-1:0]   lz_mag   = (lz_shift >= 0) ? (lz_abs <<  lz_shift)
                                                   : (lz_abs >> (-lz_shift));
    wire [DATA_W-1:0]   lz_out   = a_s[DATA_W-1] ? (~lz_mag + 1'b1) : lz_mag;
    wire signed [ACC_W-1:0] lz_acc = {{(ACC_W-8){lz_shift[7]}}, lz_shift};

    // OP_DENORM: apply signed shift in acc (same direction as LZNORM): 1/b = q << s
    wire signed [7:0]   dn_shift = acc[7:0];
    wire [DATA_W-1:0]   dn_out   = (dn_shift >= 0) ? (a_s <<< dn_shift)
                                                   : (a_s >>> (-dn_shift));

    // OP_RSEED: multiplier-less linear seeds for NR on normalized x in [0.5,1).
    localparam signed [DATA_W-1:0] RC0 = 24'h02D300; // ~2.82421875
    localparam signed [DATA_W-1:0] SC0 = 24'h01D400; // ~1.828125
    wire signed [ACC_W-1:0] rseed_recip_slope =
        a_ext + (a_ext >>> 1) + (a_ext >>> 2) + (a_ext >>> 3) + (a_ext >>> 7); // ~1.8828125*x
    wire signed [ACC_W-1:0] rseed_rsqrt_slope =
        (a_ext >>> 1) + (a_ext >>> 2) + (a_ext >>> 4) + (a_ext >>> 6);         // ~0.828125*x
    wire signed [ACC_W:0] rseed_recip_w =
        {{(ACC_W+1-DATA_W){RC0[DATA_W-1]}}, RC0} -
        {rseed_recip_slope[ACC_W-1], rseed_recip_slope};
    wire signed [ACC_W:0] rseed_rsqrt_w =
        {{(ACC_W+1-DATA_W){SC0[DATA_W-1]}}, SC0} -
        {rseed_rsqrt_slope[ACC_W-1], rseed_rsqrt_slope};
    wire [DATA_W-1:0] rseed_recip = sat_data(rseed_recip_w);
    wire [DATA_W-1:0] rseed_rsqrt = sat_data(rseed_rsqrt_w);
    // --- Combinational output mux ---
    reg [DATA_W-1:0]  comb_out;
    reg [ACC_W-1:0]   comb_acc_next;
    reg               comb_acc_override;
    reg [IDX_W-1:0]   comb_idx;

    always @(*) begin
        comb_acc_override = 1'b0;
        comb_acc_next     = {ACC_W{1'b0}};
        comb_idx          = idx_a;
        case (pe_op)
            OP_MAC:    comb_out = acc_to_q(acc_clear ? acc_mac_clear_next : acc_mac_next);
            OP_ADD:    comb_out = sat_data(add_wide);
            OP_SUB:    comb_out = sat_data(sub_wide);
            OP_ABS:    comb_out = abs_a;
            OP_CMP:    comb_out = a_ge_b ? src_a : src_b;
            OP_SGN:    comb_out = (a_s > 0) ? Q_ONE : ((a_s == 0) ? {DATA_W{1'b0}} : -$signed(Q_ONE));
            OP_SHT:    comb_out = sht_out;
            OP_PASS:   comb_out = src_a;
            OP_CMPIDX: begin
                comb_out          = cmpidx_out;
                comb_acc_override = 1'b1;
                comb_acc_next     = {{(ACC_W-1){1'b0}}, a_wins_abs};
            end
            OP_MINA:   comb_out = a_le_b ? src_a : src_b;
            OP_MACABS: comb_out = acc_to_q(acc_clear ? acc_macabs_clear_next : acc_macabs_next);
            OP_NORM1:  comb_out = acc_to_q(acc_clear ? acc_norm1_clear_next : acc_norm1_next);
            OP_MUL:    comb_out = sat_data(mul_q_wide);
            OP_SHIFT:  comb_out = sat_data(shift_wide);
            OP_CMPFLAG: begin
                comb_out          = src_a;
                comb_acc_override = 1'b1;
                comb_acc_next     = {{(ACC_W-1){1'b0}}, cmpflag_value};
            end
            OP_CONST:  comb_out = const_sel(imm16);
            OP_IDXMAX: begin
                comb_out          = cmpidx_out;
                comb_idx          = a_wins_abs ? idx_a : idx_b;
                comb_acc_override = 1'b1;
                comb_acc_next     = {{(ACC_W-1){1'b0}}, a_wins_abs};
            end
            OP_LZNORM: begin
                comb_out          = SCALAR_FN ? lz_out : {DATA_W{1'b0}};
                comb_acc_override = SCALAR_FN ? 1'b1 : 1'b0;
                comb_acc_next     = lz_acc;
            end
            OP_SELECT: begin
                comb_out = acc[0] ? src_a : src_b;
                comb_idx = acc[0] ? idx_a : idx_b;
            end
            OP_DENORM: comb_out = SCALAR_FN ? dn_out : {DATA_W{1'b0}};
            OP_RSEED:  comb_out = SCALAR_FN ? (imm16[0] ? rseed_rsqrt : rseed_recip) : {DATA_W{1'b0}};
            default:   comb_out = {DATA_W{1'b0}};
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc    <= {ACC_W{1'b0}};
            pe_out <= {DATA_W{1'b0}};
            idx_out <= {IDX_W{1'b0}};
            for (i = 0; i < RF_DEPTH; i = i + 1)
                rf[i] <= {DATA_W{1'b0}};
        end else if (ce) begin
            pe_out <= comb_out;
            idx_out <= comb_idx;

            if (acc_clear) begin
                if (acc_en) begin
                    case (pe_op)
                        OP_MAC:    acc <= acc_mac_clear_next;
                        OP_MACABS: acc <= acc_macabs_clear_next;
                        OP_NORM1:  acc <= acc_norm1_clear_next;
                        default:   acc <= {ACC_W{1'b0}};
                    endcase
                end else begin
                    acc <= {ACC_W{1'b0}};
                end
            end else if (comb_acc_override)
                acc <= comb_acc_next;
            else if (acc_en) begin
                case (pe_op)
                    OP_MAC:    acc <= acc_mac_next;
                    OP_MACABS: acc <= acc_macabs_next;
                    OP_NORM1:  acc <= acc_norm1_next;
                    default:   acc <= acc;
                endcase
            end

            if (rf_wr_en)
                rf[rf_wr_addr] <= comb_out;
        end
    end
endmodule








