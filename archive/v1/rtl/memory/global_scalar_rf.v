module global_scalar_rf #(
    parameter integer SCALAR_W = 56,
    parameter integer N_REGS   = 16,
    parameter integer ADDR_W   = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     wr_en,
    input  wire [ADDR_W-1:0]        wr_addr,
    input  wire [SCALAR_W-1:0]      wr_data,

    input  wire [ADDR_W-1:0]        rd_a_addr,
    input  wire [ADDR_W-1:0]        rd_b_addr,
    input  wire [ADDR_W-1:0]        broadcast_addr,

    output wire [SCALAR_W-1:0]      rd_a_data,
    output wire [SCALAR_W-1:0]      rd_b_data,
    output wire [SCALAR_W-1:0]      broadcast_data
);

    reg [SCALAR_W-1:0] rf [0:N_REGS-1];
    integer i;

    assign rd_a_data      = rf[rd_a_addr];
    assign rd_b_data      = rf[rd_b_addr];
    assign broadcast_data = rf[broadcast_addr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_REGS; i = i + 1)
                rf[i] <= {SCALAR_W{1'b0}};
        end else begin
            if (clear) begin
                for (i = 0; i < N_REGS; i = i + 1)
                    rf[i] <= {SCALAR_W{1'b0}};
            end else if (wr_en) begin
                rf[wr_addr] <= wr_data;
            end
        end
    end

endmodule
