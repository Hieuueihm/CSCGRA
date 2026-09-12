`include "memory_defs.vh"

module paired_support_store (
    input wire clk, rst, cancel,
    input wire begin_valid,
    output wire begin_ready,
    input wire [7:0] begin_rows,
    input wire [6:0] begin_cols,
    input wire [127:0] begin_key,
    input wire [31:0] begin_generation,
    input wire [15:0] begin_job,
    input wire [7:0] begin_fmt,
    input wire fill_valid,
    output wire fill_ready,
    input wire [6:0] fill_slot,
    input wire [1:0] fill_block,
    input wire [31:0] fill_mask,
    input wire [32*`CSR_PE_C_W-1:0] fill_data,
    input wire fill_last,
    output reg loading, cache_valid,
    output reg [3:0] load_fault,
    input wire rd_valid,
    output wire rd_ready,
    input wire [31:0] rd_mask,
    input wire [32*`CSR_MEM_B_AW-1:0] rd_addr,
    input wire [127:0] rd_key,
    input wire [31:0] rd_generation,
    input wire [15:0] rd_job, rd_tag,
    input wire [7:0] rd_fmt,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [32*`CSR_PE_C_W-1:0] rsp_data,
    output wire [31:0] rsp_mask,
    output wire [31:0] rsp_generation,
    output wire [15:0] rsp_job, rsp_tag,
    output wire [7:0] rsp_fmt,
    output wire [3:0] rsp_fault
);
    localparam integer CW = `CSR_PE_C_W;
    reg [7:0] rows;
    reg [6:0] cols, next_slot;
    reg [1:0] next_block;
    reg [127:0] key;
    reg [31:0] generation;
    reg [15:0] job;
    reg [7:0] fmt;
    reg [1:0] reserved,queued;
    reg head,tail,pipe_valid;
    reg [75:0] pipe_meta,queue_meta[0:1];
    reg [31:0] pipe_mask,queue_mask[0:1];
    reg [575:0] queue_data[0:1];
    wire [575:0] ram_data;
    wire pop=rsp_valid&&rsp_ready;
    assign rsp_data=queue_data[head];
    assign rsp_mask=queue_mask[head];
    assign {rsp_fault,rsp_generation,rsp_job,rsp_tag,rsp_fmt}=queue_meta[head];
    reg [31:0] expected_mask;
    reg padding_bad;
    reg [3:0] read_fault;
    integer groups, bank_id, lane_id, address, row_idx, col_idx;
    wire active = !rst && !cancel;
    wire last_block = (int'(next_block)+1)*32 >= int'(rows);
    wire last_word = last_block && next_slot+1 == cols;
    wire fill_good = fill_slot == next_slot && fill_block == next_block && fill_mask == expected_mask &&
                     fill_last == last_word && !padding_bad;
    wire write_en = fill_valid && fill_ready && fill_good;
    wire take = rd_valid && rd_ready;
    assign begin_ready = active && !loading && reserved==0;
    assign fill_ready = active && loading;
    assign rd_ready = active && !loading && (reserved<2||pop) && !begin_valid;
    assign rsp_valid = active && queued!=0;
    always @* begin
        groups = (int'(cols)+31)/32;
        if (groups == 0) groups = 1;
        expected_mask = '0; padding_bad = 1'b0; read_fault = '0;
        address = 0; row_idx = 0; col_idx = 0;
        for (lane_id = 0; lane_id < 32; lane_id = lane_id + 1) begin
            expected_mask[lane_id] = int'(next_block)*32+lane_id < int'(rows);
            if (!expected_mask[lane_id] && fill_data[lane_id*CW +: CW] != 0) padding_bad = 1'b1;
        end
        if (!cache_valid || key != rd_key || generation != rd_generation || job != rd_job || fmt != rd_fmt)
            read_fault = `CSR_MEM_FAULT_KEY;
        else begin
            for (bank_id = 0; bank_id < 32; bank_id = bank_id + 1) begin
                address = int'(rd_addr[bank_id*9 +: 9]);
                row_idx = address/groups;
                col_idx = (address%groups)*32 + (bank_id+32-row_idx%32)%32;
                if (rd_mask[bank_id] && (address >= `CSR_MEM_B_DEPTH || row_idx >= int'(rows) || col_idx >= int'(cols)))
                    read_fault = `CSR_MEM_FAULT_RANGE;
            end
        end
    end
    genvar bank,port;
    generate for(bank=0;bank<16;bank=bank+1) begin : bank_mem
        (* ram_style="block" *) reg [17:0] ram[0:1023];
        for(port=0;port<2;port=port+1) begin : ports
            localparam integer LOGICAL=bank+16*port;
            wire [4:0] lane=5'(LOGICAL-int'(next_slot));
            wire [8:0] logical_write=9'((int'(next_block)*32+int'(lane))*groups+int'(next_slot)/32);
            wire [9:0] write_address={1'(port),logical_write};
            wire [9:0] read_address={1'(port),rd_addr[LOGICAL*9 +: 9]};
            reg [17:0] data;
            assign ram_data[LOGICAL*18 +: 18]=data;
            always @(posedge clk) begin
                if(write_en&&fill_mask[lane]) ram[write_address]<=fill_data[int'(lane)*18 +: 18];
                if(take) data<=read_fault==0&&rd_mask[LOGICAL] ? ram[read_address] : 18'b0;
            end
        end
    end endgenerate
    always @(posedge clk) begin
        if(!active) begin
            reserved<=0;queued<=0;head<=0;tail<=0;pipe_valid<=0;pipe_meta<=0;pipe_mask<=0;
        end else begin
            case({take,pop})
                2'b10:reserved<=reserved+1'b1;
                2'b01:reserved<=reserved-1'b1;
                default:reserved<=reserved;
            endcase
            case({pipe_valid,pop})
                2'b10:queued<=queued+1'b1;
                2'b01:queued<=queued-1'b1;
                default:queued<=queued;
            endcase
            pipe_valid<=take;
            if(take) begin
                pipe_meta<={read_fault,rd_generation,rd_job,rd_tag,rd_fmt};
                pipe_mask<=read_fault==0 ? rd_mask : 32'b0;
            end
            if(pipe_valid) begin
                queue_data[tail]<=ram_data;queue_meta[tail]<=pipe_meta;queue_mask[tail]<=pipe_mask;tail<=~tail;
            end
            if(pop) head<=~head;
        end
    end
    always @(posedge clk) begin
        if (!active) begin
            loading <= 1'b0; cache_valid <= 1'b0; load_fault <= '0;
            rows <= '0; cols <= '0; key <= '0; generation <= '0; job <= '0; fmt <= '0;
            next_slot <= '0; next_block <= '0;
        end else begin
            if (begin_valid && begin_ready) begin
                cache_valid <= 1'b0; load_fault <= '0; next_slot <= '0; next_block <= '0;
                if (begin_rows == 0 || begin_rows > `CSR_MEM_B_ROWS || begin_cols == 0 || begin_cols > `CSR_MEM_B_COLS)
                    load_fault <= `CSR_MEM_FAULT_SHAPE;
                else begin
                    loading <= 1'b1; rows <= begin_rows; cols <= begin_cols;
                    key <= begin_key; generation <= begin_generation; job <= begin_job; fmt <= begin_fmt;
                end
            end
            if (fill_valid && fill_ready) begin
                if (!fill_good) begin loading <= 1'b0; load_fault <= `CSR_MEM_FAULT_STREAM; end
                else if (last_word) begin loading <= 1'b0; cache_valid <= 1'b1; end
                else if (last_block) begin next_block <= '0; next_slot <= next_slot + 1'b1; end
                else next_block <= next_block + 1'b1;
            end
        end
    end
endmodule
