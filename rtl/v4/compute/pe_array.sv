`include "context_defs.vh"

module pe_array #(
    parameter integer ARRAY_ID = 0
) (
    input wire clk, rst, cancel,
    input wire req_valid,
    output wire req_ready,
    input wire [16*64-1:0] req_words,
    input wire [7:0] req_rev,
    input wire req_mode,
    input wire [16*`CSR_PE_S_W-1:0] req_mat, req_vec,
    input wire [15:0] req_mask, req_operand_valid,
    input wire [`CSR_PE_JOB_W-1:0] req_job,
    input wire [`CSR_PE_TAG_W-1:0] req_tag,
    input wire [`CSR_PE_FMT_W-1:0] req_fmt,
    input wire req_last,
    input wire [63:0] link_ready,
    output wire rsp_valid,
    input wire rsp_ready, rsp_drop,
    output wire [16*`CSR_PE_S_W-1:0] rsp_data,
    output wire [16*`CSR_PE_ACC_W-1:0] rsp_acc,
    output wire [63:0] rsp_faults,
    output wire [15:0] rsp_store, rsp_exec, rsp_halt,
    output wire rsp_fault
);
    localparam integer SW = `CSR_PE_S_W;
    localparam integer AW = `CSR_PE_ACC_W;
    localparam [2:0] IDLE = 0, EXEC = 1, ROUTE = 2, WAIT_LINK = 3, DONE = 4;
    reg [2:0] state;
    wire active = !rst && !cancel;
    wire [15:0] ctx_ready, ctx_valid, route_ready, route_done;
    wire [63:0] ctx_faults;
    reg [63:0] route_faults;
    wire [16*12-1:0] routes;
    wire [16*AW-1:0] values, old_acc;
    wire [15:0] value_valid;
            wire [16*4*AW-1:0] unused_out_data;
    wire [63:0] out_valid;
    reg [63:0] link_valid, staged_valid;
    reg [AW-1:0] links [0:63];
    reg [AW-1:0] staged [0:63];
    reg [`CSR_PE_JOB_W-1:0] link_jobs [0:63];
    reg [`CSR_PE_FMT_W-1:0] link_fmts [0:63];
    reg [`CSR_PE_JOB_W-1:0] job_q;
    reg [`CSR_PE_TAG_W-1:0] tag_q;
    reg [`CSR_PE_FMT_W-1:0] fmt_q;
    reg last_q;
    reg [63:0] check_faults;
    integer tile, dir, index;
    wire retire = rsp_valid && rsp_ready;
    wire issue = req_valid && req_ready;
    wire route_issue = active && state == ROUTE && (&route_ready);

    assign req_ready = active && state == IDLE && (&ctx_ready);
    assign rsp_valid = active && state == DONE;
    assign rsp_faults = ctx_faults | route_faults;
    assign rsp_fault = |rsp_faults;

    always @* begin
        check_faults = '0;
        for (tile = 0; tile < 16; tile = tile + 1) begin
            for (dir = 0; dir < 4; dir = dir + 1) begin
                if (rsp_exec[tile] && routes[tile*12+dir*3 +: 3] == `CSR_CTX_ROUTE_VALUE && !value_valid[tile])
                    check_faults[tile*4 +: 4] = `CSR_TILE_FAULT_SOURCE;
            end
        end
    end

    genvar pos, side;
    generate
        for (pos = 0; pos < 16; pos = pos + 1) begin : pe
            wire [4*SW-1:0] narrow;
            wire [4*AW-1:0] wide;
            wire [3:0] valid;
            wire [3:0] router_fault;
            wire [2:0] unused_rsp_cmp_0;
            wire [15:0] unused_rsp_job_1;
            wire [15:0] unused_rsp_tag_2;
            wire [7:0] unused_rsp_fmt_3;
            wire [0:0] unused_rsp_last_4;
            wire [0:0] unused_rsp_lane_5;
            wire [11:0] unused_out_sel_7;
            wire [15:0] unused_out_job_8;
            wire [15:0] unused_out_tag_9;
            wire [7:0] unused_out_fmt_10;
            wire [0:0] unused_out_last_11;
            wire [15:0] unused_rsp_job_12;
            wire [15:0] unused_rsp_tag_13;
            wire [7:0] unused_rsp_fmt_14;
            wire [0:0] unused_rsp_last_15;
            wire [0:0] unused_rsp_lane_16;
            wire [0:0] unused_rsp_exec_17;
            for (side = 0; side < 4; side = side + 1) begin : ingress
                assign wide[side*AW +: AW] = links[pos*4+side];
                assign narrow[side*SW +: SW] = links[pos*4+side][SW-1:0];
                assign valid[side] = link_valid[pos*4+side] && link_jobs[pos*4+side] == req_job &&
                                     link_fmts[pos*4+side] == req_fmt;
            end
            pe_context #(.TILE_ID(ARRAY_ID*16+pos), .ROUTING(1)) ctx (
                .clk(clk), .rst(rst), .cancel(cancel), .req_valid(issue), .req_ready(ctx_ready[pos]),
                .req_word(req_words[pos*64 +: 64]), .req_rev(req_rev), .req_mode(req_mode),
                .req_mat(req_mat[pos*SW +: SW]), .req_vec(req_vec[pos*SW +: SW]),
                .req_links(narrow), .req_wlinks(wide), .req_link_valid(valid),
                .req_mat_valid(req_operand_valid[pos]), .req_vec_valid(req_operand_valid[pos]), .req_lane(req_mask[pos]),
                .req_job(req_job), .req_tag(req_tag), .req_fmt(req_fmt), .req_last(req_last),
                .rsp_valid(ctx_valid[pos]), .rsp_ready(retire), .rsp_drop(rsp_fault || rsp_drop),
                .rsp_data(rsp_data[pos*SW +: SW]), .rsp_acc(rsp_acc[pos*AW +: AW]),
                .rsp_fault(ctx_faults[pos*4 +: 4]), .rsp_exec(rsp_exec[pos]), .rsp_store(rsp_store[pos]),
                .rsp_routes(routes[pos*12 +: 12]), .rsp_rval(values[pos*AW +: AW]),
                .rsp_oldacc(old_acc[pos*AW +: AW]), .rsp_rvalid(value_valid[pos]),
                .rsp_cmp(unused_rsp_cmp_0), .rsp_job(unused_rsp_job_1), .rsp_tag(unused_rsp_tag_2), .rsp_fmt(unused_rsp_fmt_3), .rsp_last(unused_rsp_last_4), .rsp_lane(unused_rsp_lane_5), .rsp_halt(rsp_halt[pos])
            );
            mesh_router #(.TILE_ID(ARRAY_ID*16+pos)) router (
                .clk(clk), .rst(rst), .cancel(cancel), .req_valid(route_issue), .req_ready(route_ready[pos]),
                .req_routes(routes[pos*12 +: 12]), .req_val(values[pos*AW +: AW]),
                .req_acc(old_acc[pos*AW +: AW]),
                .req_res({{(AW-SW){rsp_data[pos*SW+SW-1]}}, rsp_data[pos*SW +: SW]}),
                .req_src({2'b11, value_valid[pos]}), .req_lane(rsp_exec[pos]), .req_exec(rsp_exec[pos]),
                .req_job(job_q), .req_tag(tag_q), .req_fmt(fmt_q), .req_last(last_q),
                .out_valid(out_valid[pos*4 +: 4]), .out_ready(link_ready[pos*4 +: 4]),
                .out_data(unused_out_data[pos*4*AW +: 4*AW]), .out_sel(unused_out_sel_7), .out_job(unused_out_job_8), .out_tag(unused_out_tag_9), .out_fmt(unused_out_fmt_10), .out_last(unused_out_last_11),
                .rsp_valid(route_done[pos]), .rsp_ready(retire), .rsp_fault(router_fault),
                .rsp_job(unused_rsp_job_12), .rsp_tag(unused_rsp_tag_13), .rsp_fmt(unused_rsp_fmt_14), .rsp_last(unused_rsp_last_15), .rsp_lane(unused_rsp_lane_16), .rsp_exec(unused_rsp_exec_17)
            );
            always @(posedge clk) begin
                if (rst || cancel) begin
                    route_faults[pos*4 +: 4] <= '0;
                end else if (issue) begin
                    route_faults[pos*4 +: 4] <= '0;
                end else if (state == EXEC && (&ctx_valid)) begin
                    route_faults[pos*4 +: 4] <= check_faults[pos*4 +: 4];
                end else if (state == WAIT_LINK && (&route_done) && router_fault != 0) begin
                    route_faults[pos*4 +: 4] <= `CSR_CTX_FAULT_EXEC;
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rst || cancel) begin
            state <= IDLE; link_valid <= '0;
            job_q <= '0; tag_q <= '0; fmt_q <= '0; last_q <= 1'b0;
            for (index = 0; index < 64; index = index + 1) begin
                links[index] <= '0; link_jobs[index] <= '0; link_fmts[index] <= '0;
            end
        end else begin
            case (state)
                IDLE: if (issue) begin
                    state <= EXEC;
                    job_q <= req_job; tag_q <= req_tag; fmt_q <= req_fmt; last_q <= req_last;
                end
                EXEC: if (&ctx_valid) state <= (|ctx_faults) || (|check_faults) ? DONE : ROUTE;
                ROUTE: if (route_issue) state <= WAIT_LINK;
                WAIT_LINK: if (&route_done) state <= DONE;
                DONE: if (retire) begin
                    state <= IDLE;
                    if (!rsp_fault && !rsp_drop) begin
                        for (index = 0; index < 64; index = index + 1) begin
                            if (staged_valid[index]) begin
                                links[index] <= staged[index]; link_valid[index] <= 1'b1;
                                link_jobs[index] <= job_q; link_fmts[index] <= fmt_q;
                            end
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    genvar dest, direction;
    generate
        for (dest = 0; dest < 16; dest = dest + 1) begin : destination
            for (direction = 0; direction < 4; direction = direction + 1) begin : edge_link
                localparam bit EXISTS = direction == 0 ? dest >= 4 : direction == 1 ? dest%4 < 3 :
                                            direction == 2 ? dest < 12 : dest%4 > 0;
                localparam integer SRC = direction == 0 ? dest-4 : direction == 1 ? dest+1 :
                                         direction == 2 ? dest+4 : dest-1;
                localparam integer OPP = (direction+2)%4;
                if (EXISTS) begin : connected
                    always @(posedge clk) begin
                        if (rst || cancel) begin
                            staged[dest*4+direction] <= '0; staged_valid[dest*4+direction] <= 1'b0;
                        end else if (issue) begin
                            staged_valid[dest*4+direction] <= 1'b0;
                        end else if (out_valid[SRC*4+OPP] && link_ready[SRC*4+OPP]) begin
                            staged[dest*4+direction] <= unused_out_data[(SRC*4+OPP)*AW +: AW];
                            staged_valid[dest*4+direction] <= 1'b1;
                        end
                    end
                end else begin : boundary
                    always @(posedge clk) begin
                        if (rst || cancel) begin
                            staged[dest*4+direction] <= '0; staged_valid[dest*4+direction] <= 1'b0;
                        end
                    end
                end
            end
        end
    endgenerate
endmodule
