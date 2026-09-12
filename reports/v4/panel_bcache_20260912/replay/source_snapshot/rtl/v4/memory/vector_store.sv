`include "memory_defs.vh"

module vector_store (
    input wire clk, rst, cancel,
    input wire begin_valid,
    output wire begin_ready,
    input wire [1:0] begin_plane,
    input wire [12:0] begin_length,
    input wire [31:0] begin_generation,
    input wire [15:0] begin_job,
    input wire [7:0] begin_fmt,
    input wire fill_valid,
    output wire fill_ready,
    input wire [6:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [32*`CSR_PE_S_W-1:0] fill_data,
    input wire fill_last,
    output reg loading,
    output reg [2:0] plane_valid,
    output reg [3:0] load_fault,
    input wire [1:0] rd_valid,
    output wire [1:0] rd_ready,
    input wire [3:0] rd_plane,
    input wire [63:0] rd_mask,
    input wire [64*`CSR_MEM_V_AW-1:0] rd_addr,
    input wire [63:0] rd_generation,
    input wire [31:0] rd_job, rd_tag,
    input wire [15:0] rd_fmt,
    output wire [1:0] rsp_valid,
    input wire [1:0] rsp_ready,
    output wire [64*`CSR_PE_S_W-1:0] rsp_data,
    output reg [63:0] rsp_mask,
    output reg [63:0] rsp_generation,
    output reg [31:0] rsp_job, rsp_tag,
    output reg [15:0] rsp_fmt,
    output reg [7:0] rsp_fault
);
    localparam integer SW = `CSR_PE_S_W;
    reg [12:0] length [0:2];
    reg [31:0] generation [0:2];
    reg [15:0] job [0:2];
    reg [7:0] fmt [0:2];
    reg [1:0] fill_plane, pending;
    reg [6:0] next_block;
    reg [31:0] expected_mask;
    reg padding_bad;
    reg [7:0] faults;
    integer port_id, bank_id, plane_id, address;
    wire active = !rst && !cancel;
    wire last_block = (int'(next_block)+1)*32 >= int'(length[fill_plane]);
    wire fill_good = fill_block == next_block && fill_mask == expected_mask && fill_last == last_block && !padding_bad;
    wire write_en = fill_valid && fill_ready && fill_good;
    assign begin_ready = active && !loading && pending == 0;
    assign fill_ready = active && loading;
    assign rd_ready = {2{active && !begin_valid}} & ~pending;
    assign rsp_valid = {2{active}} & pending;

    always @* begin
        expected_mask = '0; padding_bad = 1'b0;
        faults = '0; plane_id = 0; address = 0;
        for (bank_id = 0; bank_id < 32; bank_id = bank_id + 1) begin
            expected_mask[bank_id] = int'(next_block)*32+bank_id < int'(length[fill_plane]);
            if (!expected_mask[bank_id] && fill_data[bank_id*SW +: SW] != 0) padding_bad = 1'b1;
        end
        for (port_id = 0; port_id < 2; port_id = port_id + 1) begin
            plane_id = int'(rd_plane[port_id*2 +: 2]);
            if (plane_id > 2) faults[port_id*4 +: 4] = `CSR_MEM_FAULT_PLANE;
            else if (!plane_valid[plane_id] || generation[plane_id] != rd_generation[port_id*32 +: 32] ||
                     job[plane_id] != rd_job[port_id*16 +: 16] || fmt[plane_id] != rd_fmt[port_id*8 +: 8])
                faults[port_id*4 +: 4] = `CSR_MEM_FAULT_KEY;
            else begin
                for (bank_id = 0; bank_id < 32; bank_id = bank_id + 1) begin
                    address = int'(rd_addr[(port_id*32+bank_id)*7 +: 7]);
                    if (rd_mask[port_id*32+bank_id] && address*32+bank_id >= int'(length[plane_id]))
                        faults[port_id*4 +: 4] = `CSR_MEM_FAULT_RANGE;
                end
            end
        end
    end

    genvar plane, bank, port_num;
    wire [3*64*SW-1:0] read_data;
    generate
        for (plane = 0; plane < 3; plane = plane + 1) begin : plane_mem
            for (bank = 0; bank < 32; bank = bank + 1) begin : bank_mem
                reg [SW-1:0] ram [0:`CSR_MEM_V_DEPTH-1];
                always @(posedge clk) begin
                    if (write_en && fill_plane == plane && fill_mask[bank]) ram[next_block] <= fill_data[bank*SW +: SW];
                end
                for (port_num = 0; port_num < 2; port_num = port_num + 1) begin : read_port
                    reg [SW-1:0] data;
                    assign read_data[(plane*64+port_num*32+bank)*SW +: SW] = data;
                    always @(posedge clk) begin
                        if (!active) data <= '0;
                        else if (rd_valid[port_num] && rd_ready[port_num]) begin
                            if (rd_plane[port_num*2 +: 2] == plane && faults[port_num*4 +: 4] == 0 && rd_mask[port_num*32+bank])
                                data <= ram[rd_addr[(port_num*32+bank)*7 +: 7]];
                            else data <= '0;
                        end
                    end
                end
            end
        end
        for (port_num = 0; port_num < 2; port_num = port_num + 1) begin : responses
            for (bank = 0; bank < 32; bank = bank + 1) begin : result_bank
                assign rsp_data[(port_num*32+bank)*SW +: SW] = read_data[(port_num*32+bank)*SW +: SW] |
                    read_data[(64+port_num*32+bank)*SW +: SW] | read_data[(128+port_num*32+bank)*SW +: SW];
            end
            always @(posedge clk) begin
                if (!active) begin
                    pending[port_num] <= 1'b0; rsp_mask[port_num*32 +: 32] <= '0; rsp_fault[port_num*4 +: 4] <= '0;
                    rsp_generation[port_num*32 +: 32] <= '0; rsp_job[port_num*16 +: 16] <= '0;
                    rsp_tag[port_num*16 +: 16] <= '0; rsp_fmt[port_num*8 +: 8] <= '0;
                end else begin
                    if (rsp_valid[port_num] && rsp_ready[port_num]) pending[port_num] <= 1'b0;
                    if (rd_valid[port_num] && rd_ready[port_num]) begin
                        pending[port_num] <= 1'b1; rsp_fault[port_num*4 +: 4] <= faults[port_num*4 +: 4];
                        rsp_mask[port_num*32 +: 32] <= faults[port_num*4 +: 4] == 0 ? rd_mask[port_num*32 +: 32] : 32'b0;
                        rsp_generation[port_num*32 +: 32] <= rd_generation[port_num*32 +: 32];
                        rsp_job[port_num*16 +: 16] <= rd_job[port_num*16 +: 16];
                        rsp_tag[port_num*16 +: 16] <= rd_tag[port_num*16 +: 16]; rsp_fmt[port_num*8 +: 8] <= rd_fmt[port_num*8 +: 8];
                    end
                end
            end
        end
    endgenerate
    integer desc;
    always @(posedge clk) begin
        if (!active) begin
            loading <= 1'b0; plane_valid <= '0; load_fault <= '0; fill_plane <= '0; next_block <= '0;
            for (desc = 0; desc < 3; desc = desc + 1) begin length[desc] <= '0; generation[desc] <= '0; job[desc] <= '0; fmt[desc] <= '0; end
        end else begin
            if (begin_valid && begin_ready) begin
                load_fault <= '0;
                if (begin_plane > 2) load_fault <= `CSR_MEM_FAULT_PLANE;
                else begin
                    plane_valid[begin_plane] <= 1'b0;
                    if (begin_length == 0 || begin_length > `CSR_MEM_V_LEN) load_fault <= `CSR_MEM_FAULT_SHAPE;
                    else begin
                        loading <= 1'b1; fill_plane <= begin_plane; next_block <= '0;
                        length[begin_plane] <= begin_length; generation[begin_plane] <= begin_generation;
                        job[begin_plane] <= begin_job; fmt[begin_plane] <= begin_fmt;
                    end
                end
            end
            if (fill_valid && fill_ready) begin
                if (!fill_good) begin loading <= 1'b0; load_fault <= `CSR_MEM_FAULT_STREAM; end
                else if (last_block) begin loading <= 1'b0; plane_valid[fill_plane] <= 1'b1; end
                else next_block <= next_block + 1'b1;
            end
        end
    end
endmodule
