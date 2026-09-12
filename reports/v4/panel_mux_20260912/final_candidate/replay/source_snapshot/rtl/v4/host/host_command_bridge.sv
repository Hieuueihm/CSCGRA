`include "host_registers.vh"

module host_command_bridge (
    input wire clk,
    input wire rst,
    input wire cancel,

    input wire cmd_valid,
    output wire cmd_ready,
    output wire cmd_accept,
    input wire [3:0] cmd_opcode,

    input wire [7:0] cmd_start_rows,
    input wire [10:0] cmd_start_cols,
    input wire [127:0] cmd_start_key,
    input wire [31:0] cmd_start_generation,
    input wire [17:0] cmd_start_scale,
    input wire [15:0] cmd_start_job,
    input wire [15:0] cmd_start_tag,
    input wire [7:0] cmd_start_fmt,
    input wire [31:0] cmd_start_instruction_limit,
    input wire [1:0] cmd_start_storage_mode,
    input wire signed [6:0] cmd_start_exponent,
    input wire cmd_start_active_support,

    input wire [7:0] cmd_load_revision,
    input wire cmd_load_verified,
    input wire [10:0] cmd_load_program_count,
    input wire [10:0] cmd_load_constant_count,
    input wire [4:0] cmd_load_template_count,
    input wire [5:0] cmd_load_vector_count,
    input wire [2:0] cmd_load_kind,
    input wire [15:0] cmd_load_index,
    input wire [127:0] cmd_load_data,
    input wire cmd_load_last,

    input wire [31:0] cmd_phi_seed,
    input wire [7:0] cmd_phi_rows,
    input wire [10:0] cmd_phi_cols,
    input wire [127:0] cmd_phi_key,
    input wire [31:0] cmd_phi_generation,
    input wire [15:0] cmd_phi_job,
    input wire [7:0] cmd_phi_fmt,

    input wire cmd_host_write,
    input wire [8:0] cmd_host_block,
    input wire [31:0] cmd_host_mask,
    input wire [863:0] cmd_host_data,
    input wire [15:0] cmd_host_tag,

    input wire [9:0] cmd_result_index,
    input wire [15:0] cmd_result_tag,

    output reg command_active,
    output reg [3:0] active_command,
    output wire mailbox_valid,

    output reg load_status_valid,
    output reg [3:0] load_status_fault,
    input wire load_status_ack,

    output reg host_rsp_valid,
    output reg host_rsp_write,
    output reg [8:0] host_rsp_block,
    output reg [863:0] host_rsp_data,
    output reg [31:0] host_rsp_mask,
    output reg [15:0] host_rsp_tag,
    output reg [3:0] host_rsp_fault,
    input wire host_rsp_ack,

    output reg result_rsp_valid,
    output reg [26:0] result_rsp_data,
    output reg [9:0] result_rsp_index,
    output reg [15:0] result_rsp_request_tag,
    output reg [3:0] result_rsp_fault,
    output reg [1:0] result_rsp_mode,
    output reg signed [6:0] result_rsp_exponent,
    output reg [10:0] result_rsp_length,
    output reg [15:0] result_rsp_job,
    output reg [15:0] result_rsp_tag,
    output reg [7:0] result_rsp_fmt,
    input wire result_rsp_ack,

    output reg done_mailbox_valid,
    output reg [3:0] done_fault,
    output reg [3:0] done_detail,
    output reg [7:0] done_status,
    output reg [15:0] done_outer_iterations,
    output reg [15:0] done_inner_iterations,
    output reg [6:0] done_support_count,
    output reg done_committed,
    output reg [15:0] done_job,
    output reg [15:0] done_tag,
    output reg [7:0] done_fmt,
    output reg [63:0] done_cycles,
    input wire done_ack,

    output wire native_load_begin_valid,
    input wire native_load_begin_ready,
    output wire [7:0] native_load_begin_revision,
    output wire native_load_begin_verified,
    output wire [10:0] native_load_begin_program_count,
    output wire [10:0] native_load_begin_constant_count,
    output wire [4:0] native_load_begin_template_count,
    output wire [5:0] native_load_begin_vector_count,

    output wire native_load_valid,
    input wire native_load_ready,
    output wire [2:0] native_load_kind,
    output wire [15:0] native_load_index,
    output wire [127:0] native_load_data,
    output wire native_load_last,
    input wire native_load_status_valid,
    output wire native_load_status_ready,
    input wire [3:0] native_load_status_fault,

    input wire native_p_begin_ready,
    output wire native_p_begin_valid,
    output wire [31:0] native_p_begin_seed,
    output wire [7:0] native_p_begin_rows,
    output wire [10:0] native_p_begin_cols,
    output wire [127:0] native_p_begin_key,
    output wire [31:0] native_p_begin_generation,
    output wire [15:0] native_p_begin_job,
    output wire [7:0] native_p_begin_fmt,

    output wire native_host_valid,
    input wire native_host_ready,
    output wire native_host_write,
    output wire [8:0] native_host_block,
    output wire [31:0] native_host_mask,
    output wire [863:0] native_host_data,
    output wire [15:0] native_host_tag,
    input wire native_host_rsp_valid,
    output wire native_host_rsp_ready,
    input wire native_host_rsp_write,
    input wire [863:0] native_host_rsp_data,
    input wire [31:0] native_host_rsp_mask,
    input wire [15:0] native_host_rsp_tag,
    input wire [3:0] native_host_rsp_fault,

    input wire native_start_ready,
    output wire native_start_valid,
    output wire [7:0] native_start_rows,
    output wire [10:0] native_start_cols,
    output wire [127:0] native_start_key,
    output wire [31:0] native_start_generation,
    output wire [17:0] native_start_scale,
    output wire [15:0] native_start_job,
    output wire [15:0] native_start_tag,
    output wire [7:0] native_start_fmt,
    output wire [31:0] native_start_instruction_limit,
    output wire [1:0] native_start_storage_mode,
    output wire signed [6:0] native_start_exponent,
    output wire native_start_active_support,
    input wire native_done_valid,
    output wire native_done_ready,
    input wire [3:0] native_done_fault,
    input wire [3:0] native_done_detail,
    input wire [7:0] native_done_status,
    input wire [15:0] native_done_outer_iterations,
    input wire [15:0] native_done_inner_iterations,
    input wire [6:0] native_done_support_count,
    input wire native_done_committed,
    input wire [15:0] native_done_job,
    input wire [15:0] native_done_tag,
    input wire [7:0] native_done_fmt,
    input wire [63:0] native_done_cycles,

    input wire native_read_ready,
    output wire native_read_valid,
    output wire [9:0] native_read_index,
    output wire [15:0] native_read_tag,
    input wire native_read_rsp_valid,
    output wire native_read_rsp_ready,
    input wire [26:0] native_read_rsp_data,
    input wire [9:0] native_read_rsp_index,
    input wire [15:0] native_read_rsp_request_tag,
    input wire [3:0] native_read_rsp_fault,
    input wire [1:0] native_read_rsp_mode,
    input wire signed [6:0] native_read_rsp_exponent,
    input wire [10:0] native_read_rsp_length,
    input wire [15:0] native_read_rsp_job,
    input wire [15:0] native_read_rsp_tag,
    input wire [7:0] native_read_rsp_fmt
);

    reg [7:0] start_rows_q;
    reg [10:0] start_cols_q;
    reg [127:0] start_key_q;
    reg [31:0] start_generation_q;
    reg [17:0] start_scale_q;
    reg [15:0] start_job_q;
    reg [15:0] start_tag_q;
    reg [7:0] start_fmt_q;
    reg [31:0] start_instruction_limit_q;
    reg [1:0] start_storage_mode_q;
    reg signed [6:0] start_exponent_q;
    reg start_active_support_q;

    reg [7:0] load_revision_q;
    reg load_verified_q;
    reg [10:0] load_program_count_q;
    reg [10:0] load_constant_count_q;
    reg [4:0] load_template_count_q;
    reg [5:0] load_vector_count_q;
    reg [2:0] load_kind_q;
    reg [15:0] load_index_q;
    reg [127:0] load_data_q;
    reg load_last_q;

    reg [31:0] phi_seed_q;
    reg [7:0] phi_rows_q;
    reg [10:0] phi_cols_q;
    reg [127:0] phi_key_q;
    reg [31:0] phi_generation_q;
    reg [15:0] phi_job_q;
    reg [7:0] phi_fmt_q;

    reg host_write_q;
    reg [8:0] host_block_q;
    reg [31:0] host_mask_q;
    reg [863:0] host_data_q;
    reg [15:0] host_tag_q;
    reg [9:0] result_index_q;
    reg [15:0] result_tag_q;
    reg active_sent;

    wire command_is_start = active_command == `CSR_HOST_OP_START;
    wire command_is_load_begin = active_command == `CSR_HOST_OP_LOAD_BEGIN;
    wire command_is_load_item = active_command == `CSR_HOST_OP_LOAD_ITEM;
    wire command_is_phi_begin = active_command == `CSR_HOST_OP_PHI_BEGIN;
    wire command_is_host = active_command == `CSR_HOST_OP_HOST_READ ||
        active_command == `CSR_HOST_OP_HOST_WRITE;
    wire command_is_result = active_command == `CSR_HOST_OP_RESULT_READ;
    wire command_mailbox_valid = load_status_valid || host_rsp_valid ||
        result_rsp_valid || done_mailbox_valid;

    assign mailbox_valid = command_mailbox_valid;
    assign cmd_ready = !rst && !cancel && !command_active && !command_mailbox_valid;
    assign cmd_accept = cmd_valid && cmd_ready;

    assign native_load_begin_valid = command_active && command_is_load_begin && !active_sent;
    assign native_load_begin_revision = load_revision_q;
    assign native_load_begin_verified = load_verified_q;
    assign native_load_begin_program_count = load_program_count_q;
    assign native_load_begin_constant_count = load_constant_count_q;
    assign native_load_begin_template_count = load_template_count_q;
    assign native_load_begin_vector_count = load_vector_count_q;

    assign native_load_valid = command_active && command_is_load_item && !active_sent;
    assign native_load_kind = load_kind_q;
    assign native_load_index = load_index_q;
    assign native_load_data = load_data_q;
    assign native_load_last = load_last_q;
    assign native_load_status_ready = !rst && (!load_status_valid || load_status_ack);

    assign native_p_begin_valid = command_active && command_is_phi_begin && !active_sent;
    assign native_p_begin_seed = phi_seed_q;
    assign native_p_begin_rows = phi_rows_q;
    assign native_p_begin_cols = phi_cols_q;
    assign native_p_begin_key = phi_key_q;
    assign native_p_begin_generation = phi_generation_q;
    assign native_p_begin_job = phi_job_q;
    assign native_p_begin_fmt = phi_fmt_q;

    assign native_host_valid = command_active && command_is_host && !active_sent;
    assign native_host_write = host_write_q;
    assign native_host_block = host_block_q;
    assign native_host_mask = host_mask_q;
    assign native_host_data = host_data_q;
    assign native_host_tag = host_tag_q;
    assign native_host_rsp_ready = command_active && command_is_host && active_sent &&
        (!host_rsp_valid || host_rsp_ack);

    assign native_start_valid = command_active && command_is_start && !active_sent;
    assign native_start_rows = start_rows_q;
    assign native_start_cols = start_cols_q;
    assign native_start_key = start_key_q;
    assign native_start_generation = start_generation_q;
    assign native_start_scale = start_scale_q;
    assign native_start_job = start_job_q;
    assign native_start_tag = start_tag_q;
    assign native_start_fmt = start_fmt_q;
    assign native_start_instruction_limit = start_instruction_limit_q;
    assign native_start_storage_mode = start_storage_mode_q;
    assign native_start_exponent = start_exponent_q;
    assign native_start_active_support = start_active_support_q;
    assign native_done_ready = command_active && command_is_start && active_sent &&
        (!done_mailbox_valid || done_ack);

    assign native_read_valid = command_active && command_is_result && !active_sent;
    assign native_read_index = result_index_q;
    assign native_read_tag = result_tag_q;
    assign native_read_rsp_ready = command_active && command_is_result && active_sent &&
        (!result_rsp_valid || result_rsp_ack);

    wire load_begin_fire = native_load_begin_valid && native_load_begin_ready;
    wire load_item_fire = native_load_valid && native_load_ready;
    wire phi_begin_fire = native_p_begin_valid && native_p_begin_ready;
    wire host_fire = native_host_valid && native_host_ready;
    wire start_fire = native_start_valid && native_start_ready;
    wire result_fire = native_read_valid && native_read_ready;
    wire load_status_fire = native_load_status_valid && native_load_status_ready;
    wire host_rsp_fire = native_host_rsp_valid && native_host_rsp_ready;
    wire result_rsp_fire = native_read_rsp_valid && native_read_rsp_ready;
    wire done_fire = native_done_valid && native_done_ready;

    always @(posedge clk) begin
        if (rst) begin
            command_active <= 1'b0;
            active_command <= `CSR_HOST_EVENT_NONE;
            active_sent <= 1'b0;
            load_status_valid <= 1'b0;
            load_status_fault <= 4'b0;
            host_rsp_valid <= 1'b0;
            host_rsp_write <= 1'b0;
            host_rsp_block <= 9'b0;
            host_rsp_data <= 864'b0;
            host_rsp_mask <= 32'b0;
            host_rsp_tag <= 16'b0;
            host_rsp_fault <= 4'b0;
            result_rsp_valid <= 1'b0;
            result_rsp_data <= 27'b0;
            result_rsp_index <= 10'b0;
            result_rsp_request_tag <= 16'b0;
            result_rsp_fault <= 4'b0;
            result_rsp_mode <= 2'b0;
            result_rsp_exponent <= 7'sd0;
            result_rsp_length <= 11'b0;
            result_rsp_job <= 16'b0;
            result_rsp_tag <= 16'b0;
            result_rsp_fmt <= 8'b0;
            done_mailbox_valid <= 1'b0;
            done_fault <= 4'b0;
            done_detail <= 4'b0;
            done_status <= 8'b0;
            done_outer_iterations <= 16'b0;
            done_inner_iterations <= 16'b0;
            done_support_count <= 7'b0;
            done_committed <= 1'b0;
            done_job <= 16'b0;
            done_tag <= 16'b0;
            done_fmt <= 8'b0;
            done_cycles <= 64'b0;
        end else if (cancel) begin
            command_active <= 1'b0;
            active_sent <= 1'b0;
            load_status_valid <= 1'b0;
            host_rsp_valid <= 1'b0;
            result_rsp_valid <= 1'b0;
            done_mailbox_valid <= 1'b0;
        end else begin
            if (load_status_ack)
                load_status_valid <= 1'b0;
            if (host_rsp_ack)
                host_rsp_valid <= 1'b0;
            if (result_rsp_ack)
                result_rsp_valid <= 1'b0;
            if (done_ack)
                done_mailbox_valid <= 1'b0;

            if (cmd_accept) begin
                command_active <= 1'b1;
                active_command <= cmd_opcode;
                active_sent <= 1'b0;
                start_rows_q <= cmd_start_rows;
                start_cols_q <= cmd_start_cols;
                start_key_q <= cmd_start_key;
                start_generation_q <= cmd_start_generation;
                start_scale_q <= cmd_start_scale;
                start_job_q <= cmd_start_job;
                start_tag_q <= cmd_start_tag;
                start_fmt_q <= cmd_start_fmt;
                start_instruction_limit_q <= cmd_start_instruction_limit;
                start_storage_mode_q <= cmd_start_storage_mode;
                start_exponent_q <= cmd_start_exponent;
                start_active_support_q <= cmd_start_active_support;
                load_revision_q <= cmd_load_revision;
                load_verified_q <= cmd_load_verified;
                load_program_count_q <= cmd_load_program_count;
                load_constant_count_q <= cmd_load_constant_count;
                load_template_count_q <= cmd_load_template_count;
                load_vector_count_q <= cmd_load_vector_count;
                load_kind_q <= cmd_load_kind;
                load_index_q <= cmd_load_index;
                load_data_q <= cmd_load_data;
                load_last_q <= cmd_load_last;
                phi_seed_q <= cmd_phi_seed;
                phi_rows_q <= cmd_phi_rows;
                phi_cols_q <= cmd_phi_cols;
                phi_key_q <= cmd_phi_key;
                phi_generation_q <= cmd_phi_generation;
                phi_job_q <= cmd_phi_job;
                phi_fmt_q <= cmd_phi_fmt;
                host_write_q <= cmd_opcode == `CSR_HOST_OP_HOST_WRITE;
                host_block_q <= cmd_host_block;
                host_mask_q <= cmd_host_mask;
                host_data_q <= cmd_host_data;
                host_tag_q <= cmd_host_tag;
                result_index_q <= cmd_result_index;
                result_tag_q <= cmd_result_tag;
            end else if (command_active) begin
                if (load_begin_fire || load_item_fire || phi_begin_fire) begin
                    command_active <= 1'b0;
                    active_sent <= 1'b0;
                end else if (host_fire || start_fire || result_fire) begin
                    active_sent <= 1'b1;
                end

                if (done_fire) begin
                    done_mailbox_valid <= 1'b1;
                    done_fault <= native_done_fault;
                    done_detail <= native_done_detail;
                    done_status <= native_done_status;
                    done_outer_iterations <= native_done_outer_iterations;
                    done_inner_iterations <= native_done_inner_iterations;
                    done_support_count <= native_done_support_count;
                    done_committed <= native_done_committed;
                    done_job <= native_done_job;
                    done_tag <= native_done_tag;
                    done_fmt <= native_done_fmt;
                    done_cycles <= native_done_cycles;
                    command_active <= 1'b0;
                    active_sent <= 1'b0;
                end
                if (host_rsp_fire) begin
                    host_rsp_valid <= 1'b1;
                    host_rsp_write <= native_host_rsp_write;
                    host_rsp_block <= host_block_q;
                    host_rsp_data <= native_host_rsp_data;
                    host_rsp_mask <= native_host_rsp_mask;
                    host_rsp_tag <= native_host_rsp_tag;
                    host_rsp_fault <= native_host_rsp_fault;
                    command_active <= 1'b0;
                    active_sent <= 1'b0;
                end
                if (result_rsp_fire) begin
                    result_rsp_valid <= 1'b1;
                    result_rsp_data <= native_read_rsp_data;
                    result_rsp_index <= native_read_rsp_index;
                    result_rsp_request_tag <= native_read_rsp_request_tag;
                    result_rsp_fault <= native_read_rsp_fault;
                    result_rsp_mode <= native_read_rsp_mode;
                    result_rsp_exponent <= native_read_rsp_exponent;
                    result_rsp_length <= native_read_rsp_length;
                    result_rsp_job <= native_read_rsp_job;
                    result_rsp_tag <= native_read_rsp_tag;
                    result_rsp_fmt <= native_read_rsp_fmt;
                    command_active <= 1'b0;
                    active_sent <= 1'b0;
                end
            end

            if (load_status_fire) begin
                load_status_valid <= 1'b1;
                load_status_fault <= native_load_status_fault;
            end
        end
    end

endmodule
