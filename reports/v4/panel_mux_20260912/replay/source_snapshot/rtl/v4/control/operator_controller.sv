`include "operator_defs.vh"
`include "memory_defs.vh"

module operator_controller (
    input wire clk, rst, cancel, epoch, idle,
    input wire cfg_valid,
    output wire cfg_ready,
    input wire [3:0] cfg_index,
    input wire [7:0] cfg_rev,
    input wire [`CSR_OP_DESC_W-1:0] cfg_data,
    output reg cfg_fault,
    input wire addr_valid,
    output wire addr_ready,
    input wire [2:0] addr_mode,
    input wire [23:0] addr_value,
    input wire [15:0] addr_stride, addr_job, addr_tag,
    input wire [7:0] addr_fmt,
    output wire addr_rsp_valid,
    input wire addr_rsp_ready,
    output wire addr_rsp_fault,
    output wire [15:0] addr_rsp_job, addr_rsp_tag,
    output wire read_valid,
    input wire read_ready,
    output wire [`CSR_OP_DESC_W-1:0] read_desc,
    output reg [10:0] read_out, read_red,
    output reg [2:0] read_step,
    output wire [15:0] read_job, read_tag,
    output wire [7:0] read_fmt,
    input wire read_rsp_valid,
    output wire read_rsp_ready,
    input wire [863:0] read_mat, read_vec,
    input wire [31:0] read_mask,
    input wire [3:0] read_fault,
    input wire [15:0] read_rsp_job, read_rsp_tag,
    input wire [7:0] read_rsp_fmt,
    input wire exec_valid,
    output wire exec_ready,
    input wire [2047:0] exec_words,
    input wire [15:0] exec_job, exec_tag,
    input wire [7:0] exec_fmt,
    input wire exec_last,
    output wire exec_rsp_valid,
    input wire exec_rsp_ready,
    output wire exec_rsp_fault,
    output wire [15:0] exec_rsp_job, exec_rsp_tag,
    output wire [7:0] exec_rsp_fmt,
    input wire [127:0] link_ready,
    output wire result_valid,
    input wire result_ready,
    output wire [863:0] result_data,
    output wire [31:0] result_mask,
    output wire [351:0] result_index,
    output wire [15:0] result_job, result_tag,
    output wire [7:0] result_fmt,
    output wire result_last
);
    localparam [2:0] IDLE=0, READ=1, WAIT_READ=2, ADDRESS=3, FRAME=4, EXEC=5, ERROR=6;
    reg [2:0] state;
    reg [`CSR_OP_DESC_W-1:0] table_data [0:`CSR_OP_DESCRIPTORS-1];
    reg [`CSR_OP_DESCRIPTORS-1:0] table_valid;
    reg [10:0] out_cursor [0:`CSR_OP_DESCRIPTORS-1];
    reg [10:0] red_cursor [0:`CSR_OP_DESCRIPTORS-1];
    reg [2:0] step_cursor [0:`CSR_OP_DESCRIPTORS-1];
    reg [`CSR_OP_DESC_W-1:0] desc;
    reg [3:0] selected;
    reg [10:0] next_out, next_red;
    reg [2:0] next_step;
    reg [15:0] job, tag;
    reg [7:0] fmt;
    reg last, addressed, address_fault, have_output;
    reg [31:0] output_mask;
    reg [351:0] output_index;
    wire active = !rst && !cancel && !epoch;
    wire [`CSR_OP_DESC_W-1:0] candidate = table_data[addr_value[3:0]];
    wire [1:0] mode = candidate[`CSR_OP_MODE_LSB +: 2];
    wire trans = candidate[`CSR_OP_TRANS_LSB];
    wire [7:0] rows = candidate[`CSR_OP_ROWS_LSB +: 8];
    wire [10:0] cols = candidate[`CSR_OP_COLS_LSB +: 11];
    wire [1:0] cfg_mode = cfg_data[`CSR_OP_MODE_LSB +: 2];
    wire cfg_trans = cfg_data[`CSR_OP_TRANS_LSB];
    wire [7:0] cfg_rows = cfg_data[`CSR_OP_ROWS_LSB +: 8];
    wire [10:0] cfg_cols = cfg_data[`CSR_OP_COLS_LSB +: 11];
    wire cfg_good = cfg_rev == `CSR_OP_REV && cfg_rows > 0 && cfg_rows <= 128 && cfg_cols > 0 &&
        int'(cfg_cols) <= (cfg_mode[1] ? 96 : 1024) && (cfg_mode[1] || cfg_trans == cfg_mode[0]) &&
        cfg_data[`CSR_OP_VEC_PLANE_LSB +: 2] < 3 &&
        (cfg_mode[1] || $signed(cfg_data[`CSR_OP_SCALE_LSB +: 18]) > 0);
    integer outputs, reductions, block_size, frame_out, frame_red, frame_step, advanced_out, advanced_red, advanced_step;
    reg descriptor_bad;
    wire response_bad = read_fault != 0 || read_rsp_job != job || read_rsp_tag != tag || read_rsp_fmt != fmt;
    wire frame_ready, frame_valid, frame_fault;
    wire [31:0] frame_store;
    wire issue = exec_valid && exec_ready;
    wire issue_bad = state == FRAME && (exec_job != job || exec_tag != tag || exec_fmt != fmt);
    wire store_bad = (|frame_store) && !have_output;
    wire completion_fault = state == ERROR || frame_fault || store_bad;
    wire store_present = |result_mask;
    wire retire = exec_rsp_valid && exec_rsp_ready;
    integer slot, lane;
    always @* begin
        outputs = trans ? int'(cols) : int'(rows);
        reductions = trans ? int'(rows) : int'(cols);
        block_size = mode[0] ? 8 : 32;
        frame_out = int'(out_cursor[addr_value[3:0]]);
        frame_red = int'(red_cursor[addr_value[3:0]]);
        frame_step = int'(step_cursor[addr_value[3:0]]);
        advanced_out = frame_out; advanced_red = frame_red; advanced_step = frame_step;
        if (mode[0] && frame_step != 7) advanced_step = frame_step+1;
        else begin
            advanced_step = 0;
            advanced_red = frame_red+(mode[0] ? 32 : 1);
            if (advanced_red >= reductions) begin advanced_red = 0; advanced_out = frame_out+block_size; end
        end
        descriptor_bad = addr_mode != `CSR_OP_ADDRESS_MODE || addr_value[23:4] != 0 ||
            !table_valid[addr_value[3:0]] || frame_out >= outputs || addr_stride != 16'd1 ||
            candidate[`CSR_OP_JOB_LSB +: 16] != addr_job || candidate[`CSR_OP_FMT_LSB +: 8] != addr_fmt;
    end
    assign cfg_ready = active && idle && state == IDLE;
    assign addr_ready = active && !idle && state == IDLE;
    assign read_valid = active && state == READ;
    assign read_desc = desc;
    assign read_job = job; assign read_tag = tag; assign read_fmt = fmt;
    assign addr_rsp_valid = active && state == ADDRESS;
    assign addr_rsp_fault = address_fault;
    assign addr_rsp_job = job; assign addr_rsp_tag = tag;
    assign read_rsp_ready = active && ((state == WAIT_READ && response_bad) || (state == FRAME && issue));
    assign exec_ready = active && (state == IDLE || state == FRAME) && frame_ready;
    assign exec_rsp_valid = active && (state == ERROR || (state == EXEC && frame_valid &&
        (completion_fault || !store_present || result_ready)));
    assign exec_rsp_fault = completion_fault;
    assign exec_rsp_job = job; assign exec_rsp_tag = tag; assign exec_rsp_fmt = fmt;
    assign result_valid = active && state == EXEC && frame_valid && !completion_fault && store_present && exec_rsp_ready;
    assign result_mask = frame_store & output_mask;
    assign result_index = output_index;
    assign result_job = job; assign result_tag = tag; assign result_fmt = fmt; assign result_last = last;
    frame_fabric fabric (
        .clk(clk), .rst(rst), .cancel(cancel || epoch), .req_valid(issue && !issue_bad), .req_ready(frame_ready),
        .req_words(exec_words), .req_mat(state == FRAME ? read_mat : 864'b0), .req_vec(state == FRAME ? read_vec : 864'b0),
        .req_mask(state == FRAME ? read_mask : 32'hffffffff), .req_operand_valid(state == FRAME ? read_mask : 32'b0),
        .req_job(exec_job), .req_tag(exec_tag), .req_fmt(exec_fmt), .req_last(exec_last), .link_ready(link_ready),
        .rsp_valid(frame_valid), .rsp_ready(retire), .rsp_data(result_data), .rsp_store(frame_store), .rsp_fault(frame_fault)
    );
    always @(posedge clk) begin
        if (rst || cancel) begin
            table_valid <= '0; cfg_fault <= 1'b0;
            for (slot=0; slot<`CSR_OP_DESCRIPTORS; slot=slot+1) table_data[slot] <= '0;
        end else if (cfg_valid && cfg_ready) begin
            cfg_fault <= !cfg_good; table_valid[cfg_index] <= cfg_good;
            table_data[cfg_index] <= cfg_data;
        end
        if (rst || cancel || epoch) begin
            state <= IDLE; desc <= '0; selected <= '0; next_out <= '0; next_red <= '0; next_step <= '0; job <= '0; tag <= '0; fmt <= '0;
            last <= 1'b0; addressed <= 1'b0; address_fault <= 1'b0; have_output <= 1'b0;
            output_mask <= '0; output_index <= '0; read_out <= '0; read_red <= '0; read_step <= '0;
            for (slot=0; slot<`CSR_OP_DESCRIPTORS; slot=slot+1) begin out_cursor[slot] <= '0; red_cursor[slot] <= '0; step_cursor[slot] <= '0; end
        end else begin
            if (addr_valid && addr_ready) begin
                desc <= candidate; selected <= addr_value[3:0]; next_out <= 11'(advanced_out); next_red <= 11'(advanced_red); next_step <= 3'(advanced_step);
                job <= addr_job; tag <= addr_tag; fmt <= addr_fmt;
                read_out <= 11'(frame_out); read_red <= 11'(frame_red); read_step <= 3'(frame_step);
                address_fault <= descriptor_bad; state <= descriptor_bad ? ADDRESS : READ;
                if (!descriptor_bad) begin
                    have_output <= 1'b1;
                    for (lane=0; lane<32; lane=lane+1) begin
                        output_index[lane*11 +: 11] <= 11'(frame_out+(mode[0] ? lane/4 : lane));
                        output_mask[lane] <= frame_out+(mode[0] ? lane/4 : lane) < outputs && (!mode[0] || lane%4 == 0);
                    end
                end
            end
            if (state == READ && read_ready) state <= WAIT_READ;
            if (state == WAIT_READ && read_rsp_valid) begin address_fault <= response_bad; state <= ADDRESS; end
            if (addr_rsp_valid && addr_rsp_ready) state <= address_fault ? IDLE : FRAME;
            if (issue) begin
                addressed <= state == FRAME; job <= exec_job; tag <= exec_tag; fmt <= exec_fmt; last <= exec_last;
                state <= issue_bad ? ERROR : EXEC;
            end
            if (retire) begin
                if (addressed && !completion_fault) begin out_cursor[selected] <= next_out; red_cursor[selected] <= next_red; step_cursor[selected] <= next_step; end
                state <= IDLE;
            end
        end
    end
endmodule
