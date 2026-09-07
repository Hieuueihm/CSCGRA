`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "context_isa_defs.vh"

(* use_dsp = "no" *) module phi_stream_provider (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         abort_flush,
    input  wire [63:0]  active_seed,
    input  wire [8:0]   active_measurement_count,
    input  wire [10:0]  active_signal_length,
    input  wire [6:0]   active_work_count,
    input  wire [6:0]   support_list_count,
    input  wire         command_valid,
    output wire         command_ready,
    input  wire [1:0]   command,
    input  wire [5:0]   configuration_id,
    input  wire         configuration_valid,
    input  wire [`RECON_MEMORY_CONFIGURATION_W-1:0] configuration_data,
    input  wire         support_column_valid,
    output wire         support_column_ready,
    input  wire [`RECON_PHI_COLUMN_W-1:0] support_column,
    output wire         cache_replay_valid,
    input  wire         cache_replay_ready,
    output wire [6:0]   cache_replay_slot,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] cache_replay_row_block,
    output wire [`RECON_PHI_TAG_W-1:0] cache_replay_tag,
    input  wire         cache_symbol_valid,
    output wire         cache_symbol_ready,
    input  wire [31:0]  cache_nonzero,
    input  wire [31:0]  cache_sign,
    input  wire [`RECON_PHI_COLUMN_W-1:0] cache_column,
    input  wire [`RECON_PHI_ROW_BLOCK_W-1:0] cache_row_block,
    input  wire [`RECON_PHI_TAG_W-1:0] cache_tag,
    input  wire         cache_valid,
    output wire         phi_symbol_valid,
    input  wire         phi_symbol_ready,
    output wire [31:0]  phi_nonzero,
    output wire [31:0]  phi_sign,
    output wire [`RECON_PHI_COLUMN_W-1:0] phi_column,
    output wire [`RECON_PHI_ROW_BLOCK_W-1:0] phi_row_block,
    output wire [`RECON_PHI_TAG_W-1:0] phi_tag,
    output wire         provider_busy,
    output reg          stream_done,
    output reg          configuration_error,
    output wire         event_generate_request_fire,
    output wire         event_replay_request_fire,
    output wire         event_replay_response_fire
);
    localparam [2:0] MODE_SEQUENTIAL = 3'd0;
    localparam [2:0] MODE_SUPPORT_LIST = 3'd1;
    localparam [2:0] MODE_REPEAT = 3'd2;
    localparam [2:0] MODE_CACHE = 3'd3;
    localparam [2:0] MODE_CACHE_ROW_MAJOR = 3'd5;

    wire [15:0] cfg_base =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BASE_WORD_ADDRESS_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_BASE_WORD_ADDRESS_W];
    wire [15:0] cfg_count =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_COUNT_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_COUNT_W];
    wire [11:0] cfg_stride =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_STRIDE_WORDS_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_ELEMENT_STRIDE_WORDS_W];
    wire [2:0] cfg_first_row_pair =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BANK_BASE_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_BANK_BASE_W];
    wire [1:0] cfg_row_pair_count_log2 =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BANK_COUNT_LOG2_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_BANK_COUNT_LOG2_W];
    wire [2:0] cfg_mode =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_BANK_MODE_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_BANK_MODE_W];
    wire cfg_read_enable =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_READ_ENABLE_LSB];
    wire cfg_write_enable =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_WRITE_ENABLE_LSB];
    wire cfg_atomic_commit =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_ATOMIC_COMMIT_LSB];
    wire [1:0] cfg_memory_space =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_MEMORY_SPACE_LSB +:
                           `RECON_MEMORY_CONFIGURATION_FIELD_MEMORY_SPACE_W];
    wire cfg_reserved =
        configuration_data[`RECON_MEMORY_CONFIGURATION_FIELD_RESERVED_LSB];
    wire [3:0] cfg_row_pair_count = 4'd1 << cfg_row_pair_count_log2;
    wire [3:0] active_row_pair_limit =
        ({1'b0, active_measurement_count} + 10'd63) >> 6;
    wire [31:0] cfg_last_item = cfg_base +
        ((cfg_count == 0 ? 16'd0 : cfg_count - 1'b1) * cfg_stride);
    wire direct_base_legal = cfg_base < active_signal_length;
    wire sequential_legal = (cfg_mode != MODE_SEQUENTIAL) ||
        ((cfg_stride != 0) && (cfg_last_item < active_signal_length));
    wire cache_legal = ((cfg_mode != MODE_CACHE) &&
                        (cfg_mode != MODE_CACHE_ROW_MAJOR)) ||
        (cache_valid && (cfg_base < `RECON_PHI_SUPPORT_CACHE_SLOTS) &&
         (cfg_stride != 0) &&
         (cfg_last_item < `RECON_PHI_SUPPORT_CACHE_SLOTS));
    wire cfg_legal = configuration_valid &&
        (cfg_memory_space == `RECON_MEMORY_SPACE_PHI_COORDINATE_STREAM) &&
        cfg_read_enable && !cfg_write_enable && !cfg_atomic_commit && !cfg_reserved &&
        (cfg_mode <= MODE_CACHE_ROW_MAJOR) && (cfg_mode != 3'd4) &&
        (cfg_count != 0) &&
        (cfg_first_row_pair + cfg_row_pair_count <= active_row_pair_limit) &&
        (((cfg_mode == MODE_CACHE) ||
          (cfg_mode == MODE_CACHE_ROW_MAJOR)) ? cache_legal :
         ((cfg_mode == MODE_SUPPORT_LIST) || direct_base_legal)) &&
        sequential_legal;

    reg active;
    reg [2:0] active_mode;
    reg [15:0] column_count;
    reg [`RECON_PHI_COLUMN_W-1:0] column_stride;
    reg [2:0] first_row_pair;
    reg [3:0] row_pair_count;
    reg [5:0] active_configuration_id;
    reg [`RECON_PHI_COLUMN_W-1:0] current_column;
    reg [6:0] current_cache_slot;
    reg [6:0] first_cache_slot;
    reg [2:0] current_row_pair;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] current_cache_row_block;
    reg [15:0] issued_columns;
    reg [23:0] words_remaining;
    reg have_support_column;
    reg all_requests_issued;

    wire start_selected = command == `RECON_PHI_COMMAND_START;
    wire stop_selected = command == `RECON_PHI_COMMAND_STOP;
    assign command_ready = start_selected ? (!active && configuration_valid) :
                           stop_selected ? 1'b1 : 1'b0;
    wire command_fire = command_valid && command_ready;
    wire generator_flush = abort_flush || (command_fire && stop_selected) ||
                           (command_fire && start_selected && !cfg_legal);
    assign provider_busy = active;
    assign support_column_ready = active &&
        (active_mode == MODE_SUPPORT_LIST) &&
        !have_support_column && !all_requests_issued;
    wire support_column_fire = support_column_valid && support_column_ready;

    wire generator_request_valid = active &&
        (active_mode != MODE_CACHE) &&
        (active_mode != MODE_CACHE_ROW_MAJOR) && !all_requests_issued &&
        ((active_mode != MODE_SUPPORT_LIST) || have_support_column);
    wire generator_request_ready;
    wire generator_symbol_valid;
    wire generator_symbol_ready;
    wire [31:0] generator_nonzero;
    wire [31:0] generator_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] generator_column;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] generator_row_block;
    wire [`RECON_PHI_TAG_W-1:0] generator_tag;

    phi_symbol_generator u_generator (
        .clk(clk), .rst_n(rst_n), .flush(generator_flush),
        .phi_request_valid(generator_request_valid),
        .phi_request_ready(generator_request_ready),
        .phi_request_seed(active_seed), .phi_request_column(current_column),
        .phi_request_row_pair(current_row_pair),
        .phi_request_tag({2'b00, active_configuration_id}),
        .phi_request_measurement_count(active_measurement_count),
        .phi_symbol_valid(generator_symbol_valid),
        .phi_symbol_ready(generator_symbol_ready),
        .phi_nonzero_bits(generator_nonzero), .phi_sign_bits(generator_sign),
        .phi_symbol_column(generator_column),
        .phi_symbol_row_block(generator_row_block),
        .phi_symbol_tag(generator_tag)
    );

    wire generator_request_fire =
        generator_request_valid && generator_request_ready;
    assign cache_replay_valid = active &&
                                ((active_mode == MODE_CACHE) ||
                                 (active_mode == MODE_CACHE_ROW_MAJOR)) &&
                                !all_requests_issued;
    assign cache_replay_slot = current_cache_slot;
    assign cache_replay_row_block = current_cache_row_block;
    assign cache_replay_tag = {2'b00, active_configuration_id};
    wire cache_replay_fire = cache_replay_valid && cache_replay_ready;
    assign event_generate_request_fire = generator_request_fire;
    assign event_replay_request_fire = cache_replay_fire;

    wire cache_selected = active &&
        ((active_mode == MODE_CACHE) ||
         (active_mode == MODE_CACHE_ROW_MAJOR));
    assign event_replay_response_fire = cache_selected &&
        cache_symbol_valid && cache_symbol_ready;
    wire raw_symbol_valid = cache_selected ? cache_symbol_valid :
                                              generator_symbol_valid;
    wire [31:0] raw_nonzero = cache_selected ? cache_nonzero : generator_nonzero;
    wire [31:0] raw_sign = cache_selected ? cache_sign : generator_sign;
    wire [`RECON_PHI_COLUMN_W-1:0] raw_column =
        cache_selected ? cache_column : generator_column;
    wire [`RECON_PHI_ROW_BLOCK_W-1:0] raw_row_block =
        cache_selected ? cache_row_block : generator_row_block;
    wire [`RECON_PHI_TAG_W-1:0] raw_tag =
        cache_selected ? cache_tag : generator_tag;
    wire [3:0] active_row_block_limit =
        ({1'b0, active_measurement_count} + 10'd31) >> 5;
    wire padding_symbol = raw_symbol_valid &&
        ({1'b0, raw_row_block} >= active_row_block_limit);
    wire raw_symbol_ready = padding_symbol || phi_symbol_ready;

    assign phi_symbol_valid = raw_symbol_valid && !padding_symbol;
    assign phi_nonzero = raw_nonzero;
    assign phi_sign = raw_sign;
    assign phi_column = raw_column;
    assign phi_row_block = raw_row_block;
    assign phi_tag = raw_tag;
    assign cache_symbol_ready = cache_selected && raw_symbol_ready;
    assign generator_symbol_ready = !cache_selected && active && raw_symbol_ready;
    wire raw_symbol_fire = raw_symbol_valid && raw_symbol_ready;
    wire symbol_fire = phi_symbol_valid && phi_symbol_ready;

    always @(posedge clk) begin
        if (!rst_n || abort_flush) begin
            active <= 1'b0;
            active_mode <= MODE_SEQUENTIAL;
            column_count <= 16'd0;
            column_stride <= {`RECON_PHI_COLUMN_W{1'b0}};
            first_row_pair <= 3'd0;
            row_pair_count <= 4'd0;
            active_configuration_id <= 6'd0;
            current_column <= {`RECON_PHI_COLUMN_W{1'b0}};
            current_cache_slot <= 7'd0;
            first_cache_slot <= 7'd0;
            current_row_pair <= 3'd0;
            current_cache_row_block <= {`RECON_PHI_ROW_BLOCK_W{1'b0}};
            issued_columns <= 16'd0;
            words_remaining <= 24'd0;
            have_support_column <= 1'b0;
            all_requests_issued <= 1'b0;
            stream_done <= 1'b0;
            configuration_error <= 1'b0;
        end else begin
            stream_done <= 1'b0;
            configuration_error <= 1'b0;
            if (command_fire && stop_selected) begin
                active <= 1'b0;
                all_requests_issued <= 1'b0;
                words_remaining <= 24'd0;
                have_support_column <= 1'b0;
            end
            if (command_fire && start_selected) begin
                if (!cfg_legal) begin
                    configuration_error <= 1'b1;
                    active <= 1'b0;
                end else begin
                    active <= 1'b1;
                    active_mode <= cfg_mode;
                    column_count <= (cfg_mode == MODE_SUPPORT_LIST) ?
                        {9'd0, support_list_count} : cfg_count;
                    column_stride <= cfg_stride[`RECON_PHI_COLUMN_W-1:0];
                    first_row_pair <= cfg_first_row_pair;
                    row_pair_count <= cfg_row_pair_count;
                    active_configuration_id <= configuration_id;
                    current_column <= cfg_base[`RECON_PHI_COLUMN_W-1:0];
                    current_cache_slot <= cfg_base[6:0];
                    first_cache_slot <= cfg_base[6:0];
                    current_row_pair <= cfg_first_row_pair;
                    current_cache_row_block <= {cfg_first_row_pair, 1'b0};
                    issued_columns <= 16'd0;
                    words_remaining <=
                        (((cfg_mode == MODE_CACHE) ||
                          (cfg_mode == MODE_CACHE_ROW_MAJOR)) ?
                          active_work_count :
                         (cfg_mode == MODE_SUPPORT_LIST) ? support_list_count :
                          cfg_count) *
                        cfg_row_pair_count * 2;
                    have_support_column <= cfg_mode != MODE_SUPPORT_LIST;
                    all_requests_issued <= 1'b0;
                end
            end
            if (support_column_fire) begin
                if (support_column >= active_signal_length) begin
                    configuration_error <= 1'b1;
                    active <= 1'b0;
                end else begin
                    current_column <= support_column;
                    have_support_column <= 1'b1;
                end
            end
            if (generator_request_fire) begin
                if (current_row_pair + 1'b1 == first_row_pair + row_pair_count) begin
                    current_row_pair <= first_row_pair;
                    issued_columns <= issued_columns + 1'b1;
                    if (issued_columns + 1'b1 == column_count) begin
                        all_requests_issued <= 1'b1;
                    end else if (active_mode == MODE_SUPPORT_LIST) begin
                        have_support_column <= 1'b0;
                    end else if (active_mode == MODE_SEQUENTIAL) begin
                        current_column <= current_column + column_stride;
                    end
                end else begin
                    current_row_pair <= current_row_pair + 1'b1;
                end
            end
            if (cache_replay_fire) begin
                if (active_mode == MODE_CACHE_ROW_MAJOR) begin
                    if (current_cache_slot + 1'b1 ==
                        first_cache_slot + active_work_count) begin
                        current_cache_slot <= first_cache_slot;
                        if (current_cache_row_block + 1'b1 ==
                            ({first_row_pair, 1'b0} +
                             {row_pair_count, 1'b0})) begin
                            all_requests_issued <= 1'b1;
                        end else begin
                            current_cache_row_block <=
                                current_cache_row_block + 1'b1;
                        end
                    end else begin
                        current_cache_slot <= current_cache_slot + 1'b1;
                    end
                end else if (current_cache_row_block + 1'b1 ==
                    ({first_row_pair, 1'b0} + {row_pair_count, 1'b0})) begin
                    current_cache_row_block <= {first_row_pair, 1'b0};
                    issued_columns <= issued_columns + 1'b1;
                    if (issued_columns + 1'b1 == column_count) begin
                        all_requests_issued <= 1'b1;
                    end else begin
                        current_cache_slot <= current_cache_slot + column_stride;
                    end
                end else begin
                    current_cache_row_block <= current_cache_row_block + 1'b1;
                end
            end
            if (raw_symbol_fire) begin
                if (words_remaining == 1) begin
                    words_remaining <= 24'd0;
                    active <= 1'b0;
                    stream_done <= 1'b1;
                    all_requests_issued <= 1'b0;
                    have_support_column <= 1'b0;
                end else begin
                    words_remaining <= words_remaining - 1'b1;
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    reg f_stalled;
    reg [31:0] f_nonzero;
    reg [31:0] f_sign;
    reg [`RECON_PHI_COLUMN_W-1:0] f_column;
    reg [`RECON_PHI_ROW_BLOCK_W-1:0] f_row_block;
    reg [`RECON_PHI_TAG_W-1:0] f_tag;
    initial f_past_valid = 1'b0;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (rst_n && f_past_valid && f_stalled && !abort_flush &&
            !(command_fire && stop_selected)) begin
            assert(phi_symbol_valid);
            assert(phi_nonzero == f_nonzero);
            assert(phi_sign == f_sign);
            assert(phi_column == f_column);
            assert(phi_row_block == f_row_block);
            assert(phi_tag == f_tag);
        end
        if (padding_symbol)
            assert(!phi_symbol_valid && raw_symbol_ready);
        f_stalled <= (!rst_n || abort_flush ||
                      (command_fire && stop_selected)) ? 1'b0 :
                     (phi_symbol_valid && !phi_symbol_ready);
        f_nonzero <= phi_nonzero;
        f_sign <= phi_sign;
        f_column <= phi_column;
        f_row_block <= phi_row_block;
        f_tag <= phi_tag;
    end
`endif
endmodule

`default_nettype wire
