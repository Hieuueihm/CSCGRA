`timescale 1ns/1ps
`default_nettype none

`include "architecture_parameters.vh"
`include "loader_control_defs.vh"
`include "reconstruction_control_defs.vh"

module m13_loader_aperture #(
    parameter integer AXIL_AW = 12
)(
    input  wire clk,
    input  wire rst_n,

    input  wire [AXIL_AW-1:0] s_axi_awaddr,
    input  wire s_axi_awvalid,
    output wire s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0] s_axi_wstrb,
    input  wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input  wire s_axi_bready,
    input  wire [AXIL_AW-1:0] s_axi_araddr,
    input  wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input  wire s_axi_rready,

    input  wire engine_busy,
    output wire loader_busy,

    output wire img_finalize_valid,
    input  wire img_finalize_ready,
    output wire img_finalize_bank,
    input  wire img_finalize_resp_valid,
    output wire img_finalize_resp_ready,
    input  wire img_finalize_resp_error,
    input  wire [7:0] img_finalize_resp_code,
    input  wire [31:0] img_finalize_resp_detail,

    output wire img_wr_valid,
    input  wire img_wr_ready,
    output wire img_wr_bank,
    output wire [3:0] img_wr_plane,
    output wire [7:0] img_wr_addr,
    output wire [2*`RECON_TILE_CONTEXT_W-1:0] img_wr_data,
    input  wire img_wr_resp_valid,
    output wire img_wr_resp_ready,
    input  wire img_wr_resp_error,
    input  wire [7:0] img_wr_resp_code,
    input  wire [31:0] img_wr_resp_detail,

    output wire mem_cfg_wr_valid,
    input  wire mem_cfg_wr_ready,
    output wire mem_cfg_wr_bank,
    output wire [5:0] mem_cfg_wr_id,
    output wire [63:0] mem_cfg_wr_data,
    input  wire mem_cfg_wr_resp_valid,
    output wire mem_cfg_wr_resp_ready,
    input  wire mem_cfg_wr_resp_error,
    input  wire [7:0] mem_cfg_wr_resp_code,
    input  wire [31:0] mem_cfg_wr_resp_detail,

    output wire scalar_state_clear,
    output wire scalar_preload_valid,
    input  wire scalar_preload_ready,
    output wire scalar_preload_address,
    output wire signed [`RECON_ACC_W-1:0] scalar_preload_data,

    output wire scratch_init_valid,
    input  wire scratch_init_ready,
    output wire [2:0] scratch_init_bank,
    output wire [8:0] scratch_init_addr,
    output wire [71:0] scratch_init_data,

    output wire preload_valid,
    input  wire preload_ready,
    output wire [63:0] preload_src_addr,
    output wire [5:0] preload_cfg_id,
    output wire [63:0] preload_cfg,
    input  wire preload_done_valid,
    output wire preload_done_ready,
    input  wire [5:0] preload_done_cfg_id,
    input  wire preload_done_error,
    input  wire [7:0] preload_done_code
);
    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_ISSUE = 2'd1;
    localparam [1:0] STATE_WAIT = 2'd2;

    wire csr_wr_valid;
    wire [AXIL_AW-1:0] csr_wr_addr;
    wire [31:0] csr_wr_data;
    wire [3:0] csr_wr_strb;
    reg [1:0] csr_wr_resp;
    wire csr_rd_valid;
    wire [AXIL_AW-1:0] csr_rd_addr;
    reg [31:0] csr_rd_data;
    reg [1:0] csr_rd_resp;

    reg [31:0] image_meta_reg;
    reg [31:0] image_data_lo_reg;
    reg [31:0] image_data_mid_reg;
    reg [31:0] image_data_hi_reg;
    reg [31:0] memory_meta_reg;
    reg [31:0] memory_data_lo_reg;
    reg [31:0] memory_data_hi_reg;
    reg [31:0] scalar_meta_reg;
    reg [31:0] scalar_data_lo_reg;
    reg [31:0] scalar_data_hi_reg;
    reg [31:0] scratch_meta_reg;
    reg [31:0] scratch_data_lo_reg;
    reg [31:0] scratch_data_mid_reg;
    reg [31:0] scratch_data_hi_reg;
    reg [31:0] preload_src_lo_reg;
    reg [31:0] preload_src_hi_reg;
    reg [31:0] preload_meta_reg;
    reg [31:0] preload_cfg_lo_reg;
    reg [31:0] preload_cfg_hi_reg;

    reg [1:0] state;
    reg [2:0] active_command;
    reg [2:0] completed_command;
    reg completion_pending;
    reg completion_error;
    reg [7:0] completion_code;
    reg [31:0] completion_detail;

    reg command_img_bank;
    reg [3:0] command_img_plane;
    reg [7:0] command_img_addr;
    reg [71:0] command_img_data;
    reg command_mem_bank;
    reg [5:0] command_mem_id;
    reg [63:0] command_mem_data;
    reg command_scalar_address;
    reg signed [`RECON_ACC_W-1:0] command_scalar_data;
    reg [2:0] command_scratch_bank;
    reg [8:0] command_scratch_addr;
    reg [71:0] command_scratch_data;
    reg [63:0] command_preload_src;
    reg [5:0] command_preload_id;
    reg [63:0] command_preload_cfg;

    wire [31:0] write_mask = {
        {8{csr_wr_strb[3]}}, {8{csr_wr_strb[2]}},
        {8{csr_wr_strb[1]}}, {8{csr_wr_strb[0]}}
    };
    wire [2:0] requested_command = csr_wr_data[2:0];
    wire requested_command_valid = requested_command >=
        `RECON_LOADER_COMMAND_IMAGE_WRITE;
    wire command_write_ok = csr_wr_strb[0] &&
        !(|csr_wr_data[31:3]) && requested_command_valid &&
        (state == STATE_IDLE) && !engine_busy;
    wire clear_completion_ok = csr_wr_strb[0] &&
        csr_wr_data[1] && !(|csr_wr_data[31:2]) && !csr_wr_data[0];
    wire command_fire = csr_wr_valid &&
        (csr_wr_addr == `RECON_LOADER_CSR_COMMAND) &&
        (csr_wr_resp == `AXI_RESP_OKAY);
    wire clear_completion_fire = csr_wr_valid &&
        (csr_wr_addr == `RECON_LOADER_CSR_STATUS) &&
        (csr_wr_resp == `AXI_RESP_OKAY);

    wire issue_image_write = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_IMAGE_WRITE);
    wire issue_image_finalize = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_IMAGE_FINALIZE);
    wire issue_memory_write = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_MEMORY_WRITE);
    wire issue_scalar_preload = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_SCALAR_PRELOAD);
    wire issue_scalar_clear = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_SCALAR_CLEAR);
    wire issue_scratch_write = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_SCRATCH_WRITE);
    wire issue_scratch_preload = (state == STATE_ISSUE) &&
        (active_command == `RECON_LOADER_COMMAND_SCRATCH_PRELOAD);

    assign img_wr_valid = issue_image_write;
    assign img_wr_bank = command_img_bank;
    assign img_wr_plane = command_img_plane;
    assign img_wr_addr = command_img_addr;
    assign img_wr_data = command_img_data;
    assign img_wr_resp_ready = (state == STATE_WAIT) &&
        (active_command == `RECON_LOADER_COMMAND_IMAGE_WRITE);
    assign img_finalize_valid = issue_image_finalize;
    assign img_finalize_bank = command_img_bank;
    assign img_finalize_resp_ready = (state == STATE_WAIT) &&
        (active_command == `RECON_LOADER_COMMAND_IMAGE_FINALIZE);
    assign mem_cfg_wr_valid = issue_memory_write;
    assign mem_cfg_wr_bank = command_mem_bank;
    assign mem_cfg_wr_id = command_mem_id;
    assign mem_cfg_wr_data = command_mem_data;
    assign mem_cfg_wr_resp_ready = (state == STATE_WAIT) &&
        (active_command == `RECON_LOADER_COMMAND_MEMORY_WRITE);
    assign scalar_state_clear = issue_scalar_clear;
    assign scalar_preload_valid = issue_scalar_preload;
    assign scalar_preload_address = command_scalar_address;
    assign scalar_preload_data = command_scalar_data;
    assign scratch_init_valid = issue_scratch_write;
    assign scratch_init_bank = command_scratch_bank;
    assign scratch_init_addr = command_scratch_addr;
    assign scratch_init_data = command_scratch_data;
    assign preload_valid = issue_scratch_preload;
    assign preload_src_addr = command_preload_src;
    assign preload_cfg_id = command_preload_id;
    assign preload_cfg = command_preload_cfg;
    assign preload_done_ready = (state == STATE_WAIT) &&
        (active_command == `RECON_LOADER_COMMAND_SCRATCH_PRELOAD);
    assign loader_busy = state != STATE_IDLE;

    axilite_slave #(.AXIL_AW(AXIL_AW)) u_axi_transport (
        .aclk(clk), .aresetn(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready), .csr_wr_valid(csr_wr_valid),
        .csr_wr_addr(csr_wr_addr), .csr_wr_data(csr_wr_data),
        .csr_wr_strb(csr_wr_strb), .csr_wr_resp(csr_wr_resp),
        .csr_rd_valid(csr_rd_valid), .csr_rd_addr(csr_rd_addr),
        .csr_rd_data(csr_rd_data), .csr_rd_resp(csr_rd_resp)
    );

    always @* begin
        csr_wr_resp = `AXI_RESP_DECERR;
        if (csr_wr_addr[1:0] != 2'b00) begin
            csr_wr_resp = `AXI_RESP_DECERR;
        end else begin
            case (csr_wr_addr)
                `RECON_LOADER_CSR_COMMAND:
                    csr_wr_resp = command_write_ok ?
                        `AXI_RESP_OKAY : `AXI_RESP_SLVERR;
                `RECON_LOADER_CSR_STATUS:
                    csr_wr_resp = clear_completion_ok ?
                        `AXI_RESP_OKAY : `AXI_RESP_SLVERR;
                `RECON_LOADER_CSR_IMAGE_META,
                `RECON_LOADER_CSR_IMAGE_DATA_LO,
                `RECON_LOADER_CSR_IMAGE_DATA_MID,
                `RECON_LOADER_CSR_IMAGE_DATA_HI,
                `RECON_LOADER_CSR_MEMORY_META,
                `RECON_LOADER_CSR_MEMORY_DATA_LO,
                `RECON_LOADER_CSR_MEMORY_DATA_HI,
                `RECON_LOADER_CSR_SCALAR_META,
                `RECON_LOADER_CSR_SCALAR_DATA_LO,
                `RECON_LOADER_CSR_SCALAR_DATA_HI,
                `RECON_LOADER_CSR_SCRATCH_META,
                `RECON_LOADER_CSR_SCRATCH_DATA_LO,
                `RECON_LOADER_CSR_SCRATCH_DATA_MID,
                `RECON_LOADER_CSR_SCRATCH_DATA_HI,
                `RECON_LOADER_CSR_PRELOAD_SRC_LO,
                `RECON_LOADER_CSR_PRELOAD_SRC_HI,
                `RECON_LOADER_CSR_PRELOAD_META,
                `RECON_LOADER_CSR_PRELOAD_CFG_LO,
                `RECON_LOADER_CSR_PRELOAD_CFG_HI:
                    csr_wr_resp = `AXI_RESP_OKAY;
                `RECON_LOADER_CSR_IDENTIFICATION,
                `RECON_LOADER_CSR_VERSION,
                `RECON_LOADER_CSR_DETAIL:
                    csr_wr_resp = `AXI_RESP_SLVERR;
                default:
                    csr_wr_resp = `AXI_RESP_DECERR;
            endcase
        end
    end

    always @* begin
        csr_rd_data = 32'd0;
        csr_rd_resp = `AXI_RESP_DECERR;
        if (csr_rd_valid && (csr_rd_addr[1:0] == 2'b00)) begin
            case (csr_rd_addr)
                `RECON_LOADER_CSR_IDENTIFICATION: begin
                    csr_rd_data = `RECON_LOADER_IDENTIFICATION;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_VERSION: begin
                    csr_rd_data = `RECON_LOADER_VERSION;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_COMMAND: begin
                    csr_rd_data = 32'd0;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_STATUS: begin
                    csr_rd_data = {12'd0, preload_done_cfg_id,
                        completion_code, completed_command,
                        completion_error, completion_pending,
                        state != STATE_IDLE};
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_DETAIL: begin
                    csr_rd_data = completion_detail;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_IMAGE_META: begin
                    csr_rd_data = image_meta_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_IMAGE_DATA_LO: begin
                    csr_rd_data = image_data_lo_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_IMAGE_DATA_MID: begin
                    csr_rd_data = image_data_mid_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_IMAGE_DATA_HI: begin
                    csr_rd_data = image_data_hi_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_MEMORY_META: begin
                    csr_rd_data = memory_meta_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_MEMORY_DATA_LO: begin
                    csr_rd_data = memory_data_lo_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_MEMORY_DATA_HI: begin
                    csr_rd_data = memory_data_hi_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCALAR_META: begin
                    csr_rd_data = scalar_meta_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCALAR_DATA_LO: begin
                    csr_rd_data = scalar_data_lo_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCALAR_DATA_HI: begin
                    csr_rd_data = scalar_data_hi_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCRATCH_META: begin
                    csr_rd_data = scratch_meta_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCRATCH_DATA_LO: begin
                    csr_rd_data = scratch_data_lo_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCRATCH_DATA_MID: begin
                    csr_rd_data = scratch_data_mid_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_SCRATCH_DATA_HI: begin
                    csr_rd_data = scratch_data_hi_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_PRELOAD_SRC_LO: begin
                    csr_rd_data = preload_src_lo_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_PRELOAD_SRC_HI: begin
                    csr_rd_data = preload_src_hi_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_PRELOAD_META: begin
                    csr_rd_data = preload_meta_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_PRELOAD_CFG_LO: begin
                    csr_rd_data = preload_cfg_lo_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                `RECON_LOADER_CSR_PRELOAD_CFG_HI: begin
                    csr_rd_data = preload_cfg_hi_reg;
                    csr_rd_resp = `AXI_RESP_OKAY;
                end
                default: begin
                    csr_rd_data = 32'd0;
                    csr_rd_resp = `AXI_RESP_DECERR;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            image_meta_reg <= 32'd0;
            image_data_lo_reg <= 32'd0;
            image_data_mid_reg <= 32'd0;
            image_data_hi_reg <= 32'd0;
            memory_meta_reg <= 32'd0;
            memory_data_lo_reg <= 32'd0;
            memory_data_hi_reg <= 32'd0;
            scalar_meta_reg <= 32'd0;
            scalar_data_lo_reg <= 32'd0;
            scalar_data_hi_reg <= 32'd0;
            scratch_meta_reg <= 32'd0;
            scratch_data_lo_reg <= 32'd0;
            scratch_data_mid_reg <= 32'd0;
            scratch_data_hi_reg <= 32'd0;
            preload_src_lo_reg <= 32'd0;
            preload_src_hi_reg <= 32'd0;
            preload_meta_reg <= 32'd0;
            preload_cfg_lo_reg <= 32'd0;
            preload_cfg_hi_reg <= 32'd0;
            state <= STATE_IDLE;
            active_command <= 3'd0;
            completed_command <= 3'd0;
            completion_pending <= 1'b0;
            completion_error <= 1'b0;
            completion_code <= 8'd0;
            completion_detail <= 32'd0;
            command_img_bank <= 1'b0;
            command_img_plane <= 4'd0;
            command_img_addr <= 8'd0;
            command_img_data <= 72'd0;
            command_mem_bank <= 1'b0;
            command_mem_id <= 6'd0;
            command_mem_data <= 64'd0;
            command_scalar_address <= 1'b0;
            command_scalar_data <= {`RECON_ACC_W{1'b0}};
            command_scratch_bank <= 3'd0;
            command_scratch_addr <= 9'd0;
            command_scratch_data <= 72'd0;
            command_preload_src <= 64'd0;
            command_preload_id <= 6'd0;
            command_preload_cfg <= 64'd0;
        end else begin
            if (clear_completion_fire)
                completion_pending <= 1'b0;

            if (csr_wr_valid && (csr_wr_resp == `AXI_RESP_OKAY)) begin
                case (csr_wr_addr)
                    `RECON_LOADER_CSR_IMAGE_META:
                        image_meta_reg <= (image_meta_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_IMAGE_DATA_LO:
                        image_data_lo_reg <=
                            (image_data_lo_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_IMAGE_DATA_MID:
                        image_data_mid_reg <=
                            (image_data_mid_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_IMAGE_DATA_HI:
                        image_data_hi_reg <=
                            (image_data_hi_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_MEMORY_META:
                        memory_meta_reg <= (memory_meta_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_MEMORY_DATA_LO:
                        memory_data_lo_reg <=
                            (memory_data_lo_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_MEMORY_DATA_HI:
                        memory_data_hi_reg <=
                            (memory_data_hi_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCALAR_META:
                        scalar_meta_reg <= (scalar_meta_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCALAR_DATA_LO:
                        scalar_data_lo_reg <=
                            (scalar_data_lo_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCALAR_DATA_HI:
                        scalar_data_hi_reg <=
                            (scalar_data_hi_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCRATCH_META:
                        scratch_meta_reg <=
                            (scratch_meta_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCRATCH_DATA_LO:
                        scratch_data_lo_reg <=
                            (scratch_data_lo_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCRATCH_DATA_MID:
                        scratch_data_mid_reg <=
                            (scratch_data_mid_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_SCRATCH_DATA_HI:
                        scratch_data_hi_reg <=
                            (scratch_data_hi_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_PRELOAD_SRC_LO:
                        preload_src_lo_reg <=
                            (preload_src_lo_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_PRELOAD_SRC_HI:
                        preload_src_hi_reg <=
                            (preload_src_hi_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_PRELOAD_META:
                        preload_meta_reg <=
                            (preload_meta_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_PRELOAD_CFG_LO:
                        preload_cfg_lo_reg <=
                            (preload_cfg_lo_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    `RECON_LOADER_CSR_PRELOAD_CFG_HI:
                        preload_cfg_hi_reg <=
                            (preload_cfg_hi_reg & ~write_mask) |
                            (csr_wr_data & write_mask);
                    default: begin
                    end
                endcase
            end

            if (command_fire) begin
                state <= STATE_ISSUE;
                active_command <= requested_command;
                completion_pending <= 1'b0;
                completion_error <= 1'b0;
                completion_code <= 8'd0;
                completion_detail <= 32'd0;
                command_img_bank <= image_meta_reg[0];
                command_img_plane <= image_meta_reg[7:4];
                command_img_addr <= image_meta_reg[15:8];
                command_img_data <= {image_data_hi_reg[7:0],
                    image_data_mid_reg, image_data_lo_reg};
                command_mem_bank <= memory_meta_reg[0];
                command_mem_id <= memory_meta_reg[13:8];
                command_mem_data <= {memory_data_hi_reg,
                    memory_data_lo_reg};
                command_scalar_address <= scalar_meta_reg[0];
                command_scalar_data <= {scalar_data_hi_reg[29:0],
                    scalar_data_lo_reg};
                command_scratch_bank <= scratch_meta_reg[2:0];
                command_scratch_addr <= scratch_meta_reg[17:9];
                command_scratch_data <= {scratch_data_hi_reg[7:0],
                    scratch_data_mid_reg, scratch_data_lo_reg};
                command_preload_src <= {preload_src_hi_reg,
                    preload_src_lo_reg};
                command_preload_id <= preload_meta_reg[5:0];
                command_preload_cfg <= {preload_cfg_hi_reg,
                    preload_cfg_lo_reg};
            end

            if (state == STATE_ISSUE) begin
                if ((issue_image_write && img_wr_ready) ||
                    (issue_image_finalize && img_finalize_ready) ||
                    (issue_memory_write && mem_cfg_wr_ready) ||
                    (issue_scratch_preload && preload_ready)) begin
                    state <= STATE_WAIT;
                end else if (issue_scalar_clear ||
                    (issue_scalar_preload && scalar_preload_ready) ||
                    (issue_scratch_write && scratch_init_ready)) begin
                    state <= STATE_IDLE;
                    completed_command <= active_command;
                    completion_pending <= 1'b1;
                    completion_error <= 1'b0;
                    completion_code <= 8'd0;
                    completion_detail <= 32'd0;
                end
            end

            if ((state == STATE_WAIT) &&
                (active_command == `RECON_LOADER_COMMAND_IMAGE_WRITE) &&
                img_wr_resp_valid) begin
                state <= STATE_IDLE;
                completed_command <= active_command;
                completion_pending <= 1'b1;
                completion_error <= img_wr_resp_error;
                completion_code <= img_wr_resp_code;
                completion_detail <= img_wr_resp_detail;
            end else if ((state == STATE_WAIT) &&
                (active_command == `RECON_LOADER_COMMAND_IMAGE_FINALIZE) &&
                img_finalize_resp_valid) begin
                state <= STATE_IDLE;
                completed_command <= active_command;
                completion_pending <= 1'b1;
                completion_error <= img_finalize_resp_error;
                completion_code <= img_finalize_resp_code;
                completion_detail <= img_finalize_resp_detail;
            end else if ((state == STATE_WAIT) &&
                (active_command == `RECON_LOADER_COMMAND_MEMORY_WRITE) &&
                mem_cfg_wr_resp_valid) begin
                state <= STATE_IDLE;
                completed_command <= active_command;
                completion_pending <= 1'b1;
                completion_error <= mem_cfg_wr_resp_error;
                completion_code <= mem_cfg_wr_resp_code;
                completion_detail <= mem_cfg_wr_resp_detail;
            end else if ((state == STATE_WAIT) &&
                (active_command == `RECON_LOADER_COMMAND_SCRATCH_PRELOAD) &&
                preload_done_valid) begin
                state <= STATE_IDLE;
                completed_command <= active_command;
                completion_pending <= 1'b1;
                completion_error <= preload_done_error;
                completion_code <= preload_done_code;
                completion_detail <= {26'd0, preload_done_cfg_id};
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk) begin
        if (rst_n) begin
            assert($onehot0({img_wr_valid, img_finalize_valid,
                mem_cfg_wr_valid, scalar_preload_valid, scalar_state_clear,
                scratch_init_valid, preload_valid}));
            assert(!(completion_pending && (completed_command == 3'd0)));
        end
    end
`endif
endmodule

`default_nettype wire
