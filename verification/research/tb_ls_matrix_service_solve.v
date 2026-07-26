`timescale 1ns/1ps

module tb_ls_matrix_service_solve;
    localparam integer GE_W = 56;
    localparam integer LANES = 8;
    localparam integer K = 4;
    localparam [2:0] OP_CLEAR      = 3'd0;
    localparam [2:0] OP_WRITE      = 3'd1;
    localparam [2:0] OP_READ2      = 3'd2;
    localparam [2:0] OP_ROW_UPDATE = 3'd4;
    localparam [2:0] OP_RHS_WRITE  = 3'd5;
    localparam [2:0] OP_RHS_READ   = 3'd6;
    localparam [2:0] OP_RHS_UPDATE = 3'd7;

    reg clk;
    reg rst_n;
    reg start;
    reg [2:0] op;
    reg [4:0] row_a;
    reg [4:0] col_a;
    reg [4:0] row_b;
    reg [4:0] col_b;
    reg [4:0] row_base;
    reg [LANES-1:0] lane_valid;
    reg signed [LANES*64-1:0] lane_add;
    reg signed [GE_W-1:0] wdata;
    reg signed [63:0] rhs_wdata;
    reg signed [63:0] factor;
    wire busy;
    wire done;
    wire signed [GE_W-1:0] rdata_a;
    wire signed [GE_W-1:0] rdata_b;
    wire signed [GE_W-1:0] update_value;
    wire signed [63:0] rhs_rdata;

    reg signed [GE_W-1:0] ref_mat [0:K-1][0:K-1];
    reg signed [63:0] ref_rhs [0:K-1];
    reg signed [63:0] ref_x [0:K-1];
    reg signed [63:0] svc_x [0:K-1];
    reg signed [63:0] pivot;
    reg signed [63:0] elim_num;
    reg signed [63:0] accum;
    reg signed [63:0] value64;
    integer pass_count;
    integer fail_count;
    integer i;
    integer j;
    integer k;

    ls_matrix_service #(.MAX_K(16), .GE_W(GE_W), .LANES(LANES)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .op(op),
        .row_a(row_a), .col_a(col_a), .row_b(row_b), .col_b(col_b),
        .row_base(row_base), .lane_valid(lane_valid), .lane_add(lane_add),
        .wdata(wdata), .factor(factor), .rhs_wdata(rhs_wdata),
        .busy(busy), .done(done), .rdata_a(rdata_a), .rdata_b(rdata_b),
        .update_value(update_value), .rhs_rdata(rhs_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function signed [63:0] sx_ge;
        input signed [GE_W-1:0] value;
        begin
            sx_ge = {{(64-GE_W){value[GE_W-1]}}, value};
        end
    endfunction

    function signed [GE_W-1:0] trunc_ge;
        input signed [63:0] value;
        begin
            trunc_ge = value[GE_W-1:0];
        end
    endfunction

    task issue;
        input [2:0] op_i;
        begin
            @(negedge clk);
            op = op_i;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done == 1'b1);
            @(negedge clk);
        end
    endtask

    task write_mat;
        input integer r;
        input integer c;
        input signed [GE_W-1:0] value;
        begin
            row_a = r[4:0];
            col_a = c[4:0];
            wdata = value;
            issue(OP_WRITE);
        end
    endtask

    task write_rhs;
        input integer r;
        input signed [63:0] value;
        begin
            row_a = r[4:0];
            rhs_wdata = value;
            issue(OP_RHS_WRITE);
        end
    endtask

    task read_mat;
        input integer ra;
        input integer ca;
        input integer rb;
        input integer cb;
        begin
            row_a = ra[4:0];
            col_a = ca[4:0];
            row_b = rb[4:0];
            col_b = cb[4:0];
            issue(OP_READ2);
        end
    endtask

    task row_update;
        input integer r;
        input integer pivot_row;
        input integer c;
        input signed [63:0] factor_i;
        begin
            row_a = r[4:0];
            col_a = c[4:0];
            row_b = pivot_row[4:0];
            col_b = c[4:0];
            factor = factor_i;
            issue(OP_ROW_UPDATE);
        end
    endtask

    task rhs_update;
        input integer r;
        input integer pivot_row;
        input signed [63:0] factor_i;
        begin
            row_a = r[4:0];
            row_b = pivot_row[4:0];
            factor = factor_i;
            issue(OP_RHS_UPDATE);
        end
    endtask

    task read_rhs;
        input integer r;
        begin
            row_a = r[4:0];
            issue(OP_RHS_READ);
        end
    endtask

    task check64;
        input signed [63:0] got;
        input signed [63:0] exp;
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("PASS got=%0d", got);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL got=%0d exp=%0d", got, exp);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        start = 1'b0;
        op = OP_CLEAR;
        row_a = 5'd0;
        col_a = 5'd0;
        row_b = 5'd0;
        col_b = 5'd0;
        row_base = 5'd0;
        lane_valid = {LANES{1'b0}};
        lane_add = {LANES*64{1'b0}};
        wdata = {GE_W{1'b0}};
        rhs_wdata = 64'sd0;
        factor = 64'sd0;
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        issue(OP_CLEAR);

        ref_mat[0][0] = 56'sd5; ref_mat[0][1] = 56'sd1; ref_mat[0][2] = 56'sd1; ref_mat[0][3] = 56'sd0;
        ref_mat[1][0] = 56'sd1; ref_mat[1][1] = 56'sd6; ref_mat[1][2] = 56'sd2; ref_mat[1][3] = 56'sd1;
        ref_mat[2][0] = 56'sd1; ref_mat[2][1] = 56'sd2; ref_mat[2][2] = 56'sd7; ref_mat[2][3] = 56'sd1;
        ref_mat[3][0] = 56'sd0; ref_mat[3][1] = 56'sd1; ref_mat[3][2] = 56'sd1; ref_mat[3][3] = 56'sd4;
        ref_rhs[0] = 64'sd18; ref_rhs[1] = 64'sd33; ref_rhs[2] = 64'sd39; ref_rhs[3] = 64'sd23;

        for (i = 0; i < K; i = i + 1) begin
            for (j = 0; j < K; j = j + 1)
                write_mat(i, j, ref_mat[i][j]);
            write_rhs(i, ref_rhs[i]);
        end

        for (i = 0; i < K; i = i + 1) begin
            for (j = i + 1; j < K; j = j + 1) begin
                read_mat(j, i, i, i);
                elim_num = sx_ge(rdata_a) <<< 16;
                pivot = (rdata_b != 0) ? sx_ge(rdata_b) : 64'sd1;
                factor = elim_num / pivot;
                for (k = i; k < K; k = k + 1) begin
                    row_update(j, i, k, factor);
                    ref_mat[j][k] = trunc_ge(sx_ge(ref_mat[j][k]) - ((factor * sx_ge(ref_mat[i][k])) >>> 16));
                    read_mat(j, k, 0, 0);
                    check64(sx_ge(rdata_a), sx_ge(ref_mat[j][k]));
                end
                rhs_update(j, i, factor);
                ref_rhs[j] = ref_rhs[j] - ((factor * ref_rhs[i]) >>> 16);
                read_rhs(j);
                check64(rhs_rdata, ref_rhs[j]);
            end
        end

        for (i = K - 1; i >= 0; i = i - 1) begin
            accum = 64'sd0;
            for (j = i + 1; j < K; j = j + 1) begin
                read_mat(i, j, 0, 0);
                accum = accum + ((sx_ge(rdata_a) * svc_x[j]) >>> 16);
            end
            read_rhs(i);
            value64 = rhs_rdata - accum;
            read_mat(i, i, 0, 0);
            pivot = (rdata_a != 0) ? sx_ge(rdata_a) : 64'sd1;
            svc_x[i] = (value64 <<< 16) / pivot;

            accum = 64'sd0;
            for (j = i + 1; j < K; j = j + 1)
                accum = accum + ((sx_ge(ref_mat[i][j]) * ref_x[j]) >>> 16);
            ref_x[i] = ((ref_rhs[i] - accum) <<< 16) / sx_ge(ref_mat[i][i]);
            check64(svc_x[i], ref_x[i]);
        end

        $display("tb_ls_matrix_service_solve: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count != 0)
            $fatal(1, "ls_matrix_service solve micro-ops failed");
        $finish;
    end
endmodule
