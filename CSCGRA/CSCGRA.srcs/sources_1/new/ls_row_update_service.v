module ls_row_update_service #(
    parameter integer DATA_W = 56,
    parameter integer FACTOR_W = 64,
    parameter integer FRAC_W = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire signed [FACTOR_W-1:0]   factor_q,
    input  wire signed [DATA_W-1:0]     pivot_value,
    input  wire signed [DATA_W-1:0]     row_value,
    output reg                          valid,
    output reg signed [DATA_W-1:0]      row_next,
    output reg                          busy,
    output reg                          done
);
    localparam integer MUL_W = FACTOR_W + DATA_W;

    reg signed [DATA_W-1:0] row_value_r;
    reg signed [MUL_W-1:0] product_q;
    reg pipe_q;

    wire signed [DATA_W-1:0] delta_w = $signed(product_q >>> FRAC_W);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_value_r <= {DATA_W{1'b0}};
            product_q <= {MUL_W{1'b0}};
            row_next <= {DATA_W{1'b0}};
            valid <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            pipe_q <= 1'b0;
        end else begin
            valid <= 1'b0;
            done <= 1'b0;
            if (start) begin
                row_value_r <= row_value;
                product_q <= $signed(factor_q) * $signed(pivot_value);
                busy <= 1'b1;
                pipe_q <= 1'b1;
            end else if (pipe_q) begin
                row_next <= $signed(row_value_r) - $signed(delta_w);
                valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                pipe_q <= 1'b0;
            end
        end
    end
endmodule
