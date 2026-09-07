`timescale 1ns/1ps
`default_nettype none

module recon_sdp_ram #(
    parameter integer DATA_W = 32,
    parameter integer DEPTH = 1024,
    parameter integer ADDR_W = 10,
    parameter integer INITIALIZE_TO_ZERO = 0
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  write_enable,
    input  wire [ADDR_W-1:0]     write_address,
    input  wire [DATA_W-1:0]     write_data,
    input  wire                  read_enable,
    input  wire [ADDR_W-1:0]     read_address,
    output reg                   read_valid,
    output wire [DATA_W-1:0]     read_data
);
`ifdef SYNTHESIS
    wire unused_single_bit_error;
    wire unused_double_bit_error;
    wire [DATA_W-1:0] block_read_data;
    reg collision_forward_valid;
    reg [DATA_W-1:0] collision_forward_data;
    assign read_data = collision_forward_valid ?
        collision_forward_data : block_read_data;

    xpm_memory_sdpram #(
        .MEMORY_SIZE(DATA_W * DEPTH),
        .MEMORY_PRIMITIVE("block"),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .USE_MEM_INIT(INITIALIZE_TO_ZERO),
        .WAKEUP_TIME("disable_sleep"),
        .AUTO_SLEEP_TIME(0),
        .MESSAGE_CONTROL(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .MEMORY_OPTIMIZATION("true"),
        .WRITE_DATA_WIDTH_A(DATA_W),
        .BYTE_WRITE_WIDTH_A(DATA_W),
        .ADDR_WIDTH_A(ADDR_W),
        .READ_DATA_WIDTH_B(DATA_W),
        .ADDR_WIDTH_B(ADDR_W),
        .READ_RESET_VALUE_B("0"),
        .READ_LATENCY_B(1),
        .WRITE_MODE_B("read_first")
    ) u_block_memory (
        .sleep(1'b0),
        .clka(clk),
        .ena(write_enable),
        .wea(write_enable),
        .addra(write_address),
        .dina(write_data),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .clkb(clk),
        .rstb(!rst_n),
        .enb(read_enable),
        .regceb(1'b1),
        .addrb(read_address),
        .doutb(block_read_data),
        .sbiterrb(unused_single_bit_error),
        .dbiterrb(unused_double_bit_error)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            collision_forward_valid <= 1'b0;
        end else begin
            collision_forward_valid <= read_enable && write_enable &&
                (write_address == read_address);
            if (read_enable && write_enable &&
                (write_address == read_address))
                collision_forward_data <= write_data;
        end
    end
`else
    reg [DATA_W-1:0] memory [0:DEPTH-1];
    reg [DATA_W-1:0] behavioral_read_data;
    integer initialize_index;
    assign read_data = behavioral_read_data;

    initial begin
        if (INITIALIZE_TO_ZERO != 0) begin
            for (initialize_index = 0; initialize_index < DEPTH;
                 initialize_index = initialize_index + 1)
                memory[initialize_index] = {DATA_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (write_enable)
            memory[write_address] <= write_data;
        if (read_enable) begin
            if (write_enable && (write_address == read_address))
                behavioral_read_data <= write_data;
            else
                behavioral_read_data <= memory[read_address];
        end
    end
`endif

    always @(posedge clk) begin
        if (!rst_n)
            read_valid <= 1'b0;
        else
            read_valid <= read_enable;
    end
endmodule

`default_nettype wire
