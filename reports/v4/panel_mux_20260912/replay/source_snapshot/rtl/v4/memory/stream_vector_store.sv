// Full-N pool: 32 logical lanes paired onto 16 common-clock TDP arrays.
// Two read credits include the synchronous RAM stage; writes have no response.
// Reset/cancel flush transactions only. Publication/epochs belong to the owner.
module stream_vector_store (
    input wire clk, rst, cancel,
    input wire req_valid, output wire req_ready,
    input wire req_write,
    input wire [8:0] req_block,
    input wire [31:0] req_mask,
    input wire [863:0] req_data,
    input wire [15:0] req_tag,
    output wire rsp_valid, input wire rsp_ready,
    output wire [863:0] rsp_data,
    output wire [31:0] rsp_mask,
    output wire [15:0] rsp_tag
);
    wire active = !rst && !cancel;
    reg [1:0] reserved, queued;
    reg head, tail, pipe_valid;
    reg [31:0] pipe_mask;
    reg [15:0] pipe_tag;
    reg [863:0] queue_data [0:1];
    reg [31:0] queue_mask [0:1];
    reg [15:0] queue_tag [0:1];
    wire [863:0] ram_data;
    wire pop = rsp_valid && rsp_ready;
    assign req_ready = active && (req_write || reserved < 2 || pop);
    wire take = req_valid && req_ready;
    wire read_take = take && !req_write;
    assign rsp_valid = active && queued != 0;
    assign rsp_data = queue_data[head];
    assign rsp_mask = queue_mask[head];
    assign rsp_tag = queue_tag[head];
    genvar bank, port;
    generate for (bank=0; bank<16; bank=bank+1) begin : banks
        // 27 useful bits; intended primitive geometry is 1024x36 RAMB36 TDP.
        // No array reset, no simultaneous third access, no cross-port alias.
        (* ram_style = "block" *) reg [26:0] ram [0:1023];
        for (port=0; port<2; port=port+1) begin : ports
            localparam integer LANE = bank+16*port;
            wire [9:0] address = {1'(port),req_block};
            reg [26:0] data;
            assign ram_data[LANE*27 +: 27] = data;
            always @(posedge clk) begin
                if (take && req_write && req_mask[LANE])
                    ram[address] <= req_data[LANE*27 +: 27];
                if (read_take)
                    data <= req_mask[LANE] ? ram[address] : 27'b0;
            end
        end
    end endgenerate
    always @(posedge clk) begin
        if (!active) begin
            reserved <= 0; queued <= 0; head <= 0; tail <= 0;
            pipe_valid <= 0; pipe_mask <= 0; pipe_tag <= 0;
        end else begin
            case ({read_take,pop})
                2'b10: reserved <= reserved+1'b1;
                2'b01: reserved <= reserved-1'b1;
                default: reserved <= reserved;
            endcase
            pipe_valid <= read_take;
            if (read_take) begin pipe_mask <= req_mask; pipe_tag <= req_tag; end
            case ({pipe_valid,pop})
                2'b10: queued <= queued+1'b1;
                2'b01: queued <= queued-1'b1;
                default: queued <= queued;
            endcase
            if (pipe_valid) begin
                queue_data[tail] <= ram_data;
                queue_mask[tail] <= pipe_mask; queue_tag[tail] <= pipe_tag;
                tail <= ~tail;
            end
            if (pop) head <= ~head;
        end
    end
endmodule
