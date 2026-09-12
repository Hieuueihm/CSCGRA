`include "pe_interface.vh"

module mesh_router #(
    parameter integer TILE_ID = 0
) (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [11:0] req_routes,
    input wire [`CSR_PE_ACC_W-1:0] req_val, req_acc, req_res,
    input wire [2:0] req_src,
    input wire req_lane, req_exec,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    output wire [3:0] out_valid,
    input wire [3:0] out_ready,
    output reg [4*`CSR_PE_ACC_W-1:0] out_data,
    output reg [11:0] out_sel,
    output wire [`CSR_PE_JOB_W-1:0] out_job,
    output wire [`CSR_PE_TAG_W-1:0] out_tag,
    output wire [`CSR_PE_FMT_W-1:0] out_fmt,
    output wire out_last,
    output wire rsp_valid,
    input wire rsp_ready,
    output reg [`CSR_PE_FAULT_W-1:0] rsp_fault,
    output reg [`CSR_PE_JOB_W-1:0] rsp_job,
    output reg [`CSR_PE_TAG_W-1:0] rsp_tag,
    output reg [`CSR_PE_FMT_W-1:0] rsp_fmt,
    output reg rsp_last, rsp_lane, rsp_exec
);
    localparam integer ROW = (TILE_ID % 16) / `CSR_PE_COLS;
    localparam integer COL = TILE_ID % `CSR_PE_COLS;
    localparam [3:0] EDGES = {COL > 0, ROW < `CSR_PE_ROWS-1, COL < `CSR_PE_COLS-1, ROW > 0};
    reg [3:0] pending, mask;
    reg done;
    reg [4*`CSR_PE_ACC_W-1:0] data_next;
    reg [11:0] sel_next;
    reg [`CSR_PE_FAULT_W-1:0] fault_next;
    reg bad_sel, bad_edge, bad_src;
    reg [2:0] sel;
    integer dir;
    wire active = !rst && !cancel;
    wire [3:0] remaining = pending & ~out_ready;

    assign req_ready = active && pending == 0 && !done;
    assign out_valid = active ? pending : 4'b0;
    assign rsp_valid = active && done;
    assign out_job = rsp_job;
    assign out_tag = rsp_tag;
    assign out_fmt = rsp_fmt;
    assign out_last = rsp_last;

    always @* begin
        mask = '0; data_next = '0; sel_next = '0;
        fault_next = `CSR_PE_ROUTE_FAULT_NONE;
        bad_sel = 1'b0; bad_edge = 1'b0; bad_src = 1'b0; sel = '0;
        if (req_lane && req_exec) begin
            for (dir = 0; dir < 4; dir = dir + 1) begin
                sel = req_routes[dir*3 +: 3];
                if (sel != `CSR_PE_ROUTE_NONE) begin
                    mask[dir] = 1'b1;
                    sel_next[dir*3 +: 3] = sel;
                    if (!EDGES[dir] || TILE_ID < 0 || TILE_ID >= `CSR_PE_TILES) bad_edge = 1'b1;
                    case (sel)
                        `CSR_PE_ROUTE_VALUE: begin
                            data_next[dir*`CSR_PE_ACC_W +: `CSR_PE_ACC_W] = req_val;
                            if (!req_src[0]) bad_src = 1'b1;
                        end
                        `CSR_PE_ROUTE_ACC: begin
                            data_next[dir*`CSR_PE_ACC_W +: `CSR_PE_ACC_W] = req_acc;
                            if (!req_src[1]) bad_src = 1'b1;
                        end
                        `CSR_PE_ROUTE_RESULT: begin
                            data_next[dir*`CSR_PE_ACC_W +: `CSR_PE_ACC_W] = req_res;
                            if (!req_src[2]) bad_src = 1'b1;
                        end
                        default: bad_sel = 1'b1;
                    endcase
                end
            end
            if (bad_sel) fault_next = `CSR_PE_ROUTE_FAULT_SEL;
            else if (bad_edge) fault_next = `CSR_PE_ROUTE_FAULT_EDGE;
            else if (bad_src) fault_next = `CSR_PE_ROUTE_FAULT_SRC;
            if (fault_next != 0) begin mask = '0; data_next = '0; sel_next = '0; end
        end
    end

    always @(posedge clk) begin
        if (rst || cancel) begin
            pending <= '0; done <= 1'b0; out_data <= '0; out_sel <= '0;
            rsp_fault <= '0; rsp_job <= '0; rsp_tag <= '0; rsp_fmt <= '0;
            rsp_last <= 1'b0; rsp_lane <= 1'b0; rsp_exec <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready) done <= 1'b0;
            if (pending != 0) begin
                pending <= remaining;
                if (remaining == 0) done <= 1'b1;
            end
            if (req_valid && req_ready) begin
                pending <= mask; done <= mask == 0;
                out_data <= data_next; out_sel <= sel_next; rsp_fault <= fault_next;
                rsp_job <= req_job; rsp_tag <= req_tag; rsp_fmt <= req_fmt;
                rsp_last <= req_last; rsp_lane <= req_lane; rsp_exec <= req_lane && req_exec;
            end
        end
    end
endmodule
