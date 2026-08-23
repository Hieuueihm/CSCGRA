module dma_ctrl #(
    parameter integer AXI_AW  = 32,
    parameter integer AXI_DW  = 32,
    parameter integer COLS    = 8,
    parameter integer MEM_AW  = 10,
    parameter integer DATA_W  = 24,
    parameter integer IDX_W   = 10
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     start,
    input  wire                     dir,
    input  wire [2:0]               vec_id,
    input  wire [IDX_W-1:0]         length,
    input  wire [AXI_AW-1:0]        ddr_addr,
    output reg                      done,
    output reg                      error,
    output reg  [3:0]               error_code,
    // High whenever a transaction is in flight (state != S_IDLE).  The top
    // level uses this to hold the soft reset off the AXI master until it is
    // back at a transaction boundary.
    output wire                     busy,

    output reg  [AXI_AW-1:0]        m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output reg  [2:0]               m_axi_arsize,
    output reg  [1:0]               m_axi_arburst,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,
    input  wire [AXI_DW-1:0]        m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rvalid,
    input  wire                     m_axi_rlast,
    output reg                      m_axi_rready,

    output reg  [AXI_AW-1:0]        m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output reg  [2:0]               m_axi_awsize,
    output reg  [1:0]               m_axi_awburst,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,
    output reg  [AXI_DW-1:0]        m_axi_wdata,
    output reg  [AXI_DW/8-1:0]      m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,

    output reg  [COLS*MEM_AW-1:0]   spm_addr,
    output reg  [COLS*DATA_W-1:0]   spm_wdata,
    output reg  [COLS-1:0]          spm_wen,
    input  wire [COLS*DATA_W-1:0]   spm_rdata
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_AR   = 3'd1;
    localparam [2:0] S_R    = 3'd2;
    localparam [2:0] S_AW   = 3'd3;
    localparam [2:0] S_W    = 3'd4;
    localparam [2:0] S_B    = 3'd5;
    localparam [2:0] S_DONE = 3'd6;

    localparam [3:0] ERR_NONE   = 4'd0;
    localparam [3:0] ERR_READ   = 4'd1;
    localparam [3:0] ERR_WRITE  = 4'd2;
    localparam [3:0] ERR_RANGE  = 4'd3;
    localparam [3:0] ERR_LEN0   = 4'd4;
    localparam [3:0] ERR_ALIGN  = 4'd5;

    reg [2:0] state;
    reg [IDX_W-1:0] beat_idx;
    reg [IDX_W-1:0] remaining;
    // AXI4 encodes a 256-beat burst as ARLEN/AWLEN=8'hFF.  Keep the
    // internal count at nine bits so 256 is not confused with zero.
    reg [8:0] burst_left;
    reg [AXI_AW-1:0] addr_q;
    reg [1:0] spm_read_wait;
    // Set once an error has been latched but the slave may still owe beats
    // of the current burst.  AXI4 obliges the master to accept every beat
    // through rlast, so the FSM keeps rready asserted and discards data.
    reg rd_err_drain_q;

    function [MEM_AW-1:0] vec_base;
        input [2:0] v;
        begin
            case (v)
                3'd0: vec_base = {MEM_AW{1'b0}};
                3'd1: vec_base = (128 >> (10-MEM_AW));
                3'd2: vec_base = (256 >> (10-MEM_AW));
                3'd3: vec_base = (384 >> (10-MEM_AW));
                3'd4: vec_base = (512 >> (10-MEM_AW));
                3'd5: vec_base = (640 >> (10-MEM_AW));
                3'd6: vec_base = (768 >> (10-MEM_AW));
                3'd7: vec_base = (896 >> (10-MEM_AW));
                default: vec_base = {MEM_AW{1'b0}};
            endcase
        end
    endfunction

    function [2:0] axi_size;
        input integer bytes;
        begin
            case (bytes)
                1: axi_size = 3'd0;
                2: axi_size = 3'd1;
                4: axi_size = 3'd2;
                8: axi_size = 3'd3;
                default: axi_size = 3'd1;
            endcase
        end
    endfunction

    function [7:0] idx_to_u8;
        input [IDX_W-1:0] value;
        integer k;
        begin
            idx_to_u8 = 8'd0;
            for (k = 0; k < IDX_W; k = k + 1) begin
                if (k < 8) idx_to_u8[k] = value[k];
            end
        end
    endfunction

    wire [2:0] lane = beat_idx[2:0];
    wire addr_misaligned =
        ((AXI_DW/8) == 4) ? (ddr_addr[1:0] != 2'b00) :
        ((AXI_DW/8) == 2) ? (ddr_addr[0] != 1'b0) :
                             1'b0;
    wire [MEM_AW-1:0] bank_addr = vec_base(vec_id) + beat_idx[IDX_W-1:3];
    wire [7:0] remaining_u8 = idx_to_u8(remaining);
    wire [7:0] length_u8 = idx_to_u8(length);
    wire [7:0] burst_len_minus_one = burst_left - 1'b1;

    integer j;

    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            error <= 1'b0;
            error_code <= ERR_NONE;
            m_axi_araddr <= {AXI_AW{1'b0}};
            m_axi_arlen <= 8'd0;
            m_axi_arsize <= axi_size(AXI_DW/8);
            m_axi_arburst <= 2'b01;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
            m_axi_awaddr <= {AXI_AW{1'b0}};
            m_axi_awlen <= 8'd0;
            m_axi_awsize <= axi_size(AXI_DW/8);
            m_axi_awburst <= 2'b01;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= {AXI_DW{1'b0}};
            m_axi_wstrb <= {(AXI_DW/8){1'b1}};
            m_axi_wlast <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            spm_addr <= {COLS*MEM_AW{1'b0}};
            spm_wdata <= {COLS*DATA_W{1'b0}};
            spm_wen <= {COLS{1'b0}};
            beat_idx <= {IDX_W{1'b0}};
            remaining <= {IDX_W{1'b0}};
            burst_left <= 9'd0;
            addr_q <= {AXI_AW{1'b0}};
            spm_read_wait <= 2'd0;
            rd_err_drain_q <= 1'b0;
        end else begin
            done <= 1'b0;
            spm_wen <= {COLS{1'b0}};

            for (j = 0; j < COLS; j = j + 1)
                spm_addr[j*MEM_AW +: MEM_AW] <= vec_base(vec_id) + beat_idx[IDX_W-1:3];

            case (state)
                S_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid <= 1'b0;
                    m_axi_rready <= 1'b0;
                    m_axi_bready <= 1'b0;
                    error <= 1'b0;
                    error_code <= ERR_NONE;
                    if (start) begin
                        if (length == 0) begin
                            error <= 1'b1;
                            error_code <= ERR_LEN0;
                            state <= S_DONE;
                        end else if (addr_misaligned) begin
                            error <= 1'b1;
                            error_code <= ERR_ALIGN;
                            state <= S_DONE;
                        end else begin
                            beat_idx <= {IDX_W{1'b0}};
                            remaining <= length;
                            burst_left <= (length > 256) ? 9'd256 : length;
                            addr_q <= ddr_addr;
                            if (dir) begin
                                m_axi_awaddr <= ddr_addr;
                                m_axi_awlen <= ((length > 256) ? 8'd0 : length_u8) - 1'b1;
                                m_axi_awsize <= axi_size(AXI_DW/8);
                                m_axi_awburst <= 2'b01;
                                m_axi_awvalid <= 1'b1;
                            end else begin
                                m_axi_araddr <= ddr_addr;
                                m_axi_arlen <= ((length > 256) ? 8'd0 : length_u8) - 1'b1;
                                m_axi_arsize <= axi_size(AXI_DW/8);
                                m_axi_arburst <= 2'b01;
                                m_axi_arvalid <= 1'b1;
                            end
                            state <= dir ? S_AW : S_AR;
                        end
                    end
                end
                S_AR: begin
                    if (!m_axi_arvalid) begin
                        m_axi_araddr <= addr_q;
                        m_axi_arlen <= burst_len_minus_one;
                        m_axi_arsize <= axi_size(AXI_DW/8);
                        m_axi_arburst <= 2'b01;
                        m_axi_arvalid <= 1'b1;
                    end else if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b1;
                        state <= S_R;
                    end
                end
                S_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (rd_err_drain_q) begin
                            // An error is already latched.  Keep rready
                            // asserted and discard beats until rlast so the
                            // slave can retire the burst; abandoning it
                            // mid-flight would stall the read channel.
                            if (m_axi_rlast) begin
                                m_axi_rready <= 1'b0;
                                rd_err_drain_q <= 1'b0;
                                state <= S_DONE;
                            end
                        end else if ((m_axi_rresp == 2'b10) || (m_axi_rresp == 2'b11)) begin
                            // RRESP is part of the AXI read handshake.  Only
                            // the two error encodings are actionable; OKAY and
                            // EXOKAY both carry valid data.
                            error <= 1'b1;
                            error_code <= ERR_READ;
                            if (m_axi_rlast)
                                state <= S_DONE;
                            else
                                rd_err_drain_q <= 1'b1;
                        end else if ((burst_left == 1) && !m_axi_rlast) begin
                            // The slave must terminate an ARLEN+1-beat burst
                            // with rlast and has not.  Latch the error and
                            // drain whatever beats still follow.
                            error <= 1'b1;
                            error_code <= ERR_READ;
                            rd_err_drain_q <= 1'b1;
                        end else if ((burst_left != 1) && m_axi_rlast) begin
                            // An early rlast terminates the burst itself, so
                            // no further beats can follow: fail immediately.
                            m_axi_rready <= 1'b0;
                            error <= 1'b1;
                            error_code <= ERR_READ;
                            state <= S_DONE;
                        end else begin
                            spm_addr[lane*MEM_AW +: MEM_AW] <= bank_addr;
                            spm_wdata[lane*DATA_W +: DATA_W] <= m_axi_rdata[DATA_W-1:0];
                            spm_wen[lane] <= 1'b1;
                            beat_idx <= beat_idx + 1'b1;
                            remaining <= remaining - 1'b1;

                            if (remaining == 1) begin
                                m_axi_rready <= 1'b0;
                                state <= S_DONE;
                            end else if (burst_left == 1) begin
                                // This edge ends a full 256-beat burst: bursts
                                // are only re-issued at full length (see the
                                // sizing above), so advance the DDR address by
                                // one whole burst, matching the write path.
                                m_axi_rready <= 1'b0;
                                addr_q <= addr_q + (256 * (AXI_DW/8));
                                burst_left <= (((remaining - 1) > 256) ? 9'd256 : (remaining - 1));
                                state <= S_AR;
                            end else begin
                                burst_left <= burst_left - 1'b1;
                            end
                        end
                    end
                end
                S_AW: begin
                    if (!m_axi_awvalid) begin
                        m_axi_awaddr <= addr_q;
                        m_axi_awlen <= burst_len_minus_one;
                        m_axi_awsize <= axi_size(AXI_DW/8);
                        m_axi_awburst <= 2'b01;
                        m_axi_awvalid <= 1'b1;
                    end else if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        spm_read_wait <= 2'd2;
                        state <= S_W;
                    end
                end
                S_W: begin
                    if (!m_axi_wvalid && (spm_read_wait != 2'd0)) begin
                        spm_read_wait <= spm_read_wait - 1'b1;
                    end else if (!m_axi_wvalid) begin
                        m_axi_wdata <= {{(AXI_DW-DATA_W){spm_rdata[lane*DATA_W + DATA_W-1]}},
                                        spm_rdata[lane*DATA_W +: DATA_W]};
                        m_axi_wstrb <= {(AXI_DW/8){1'b1}};
                        m_axi_wlast <= (burst_left == 1);
                        m_axi_wvalid <= 1'b1;
                    end else if (m_axi_wready) begin
                        beat_idx <= beat_idx + 1'b1;
                        remaining <= remaining - 1'b1;
                        burst_left <= burst_left - 1'b1;
                        m_axi_wvalid <= 1'b0;
                        if (burst_left == 1) begin
                            m_axi_bready <= 1'b1;
                            state <= S_B;
                        end else begin
                            spm_read_wait <= 2'd2;
                        end
                    end
                end
                S_B: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        if (m_axi_bresp != 2'b00) begin
                            error <= 1'b1;
                            error_code <= ERR_WRITE;
                            state <= S_DONE;
                        end else if (remaining == 0) begin
                            state <= S_DONE;
                        end else begin
                            addr_q <= addr_q + 256 * (AXI_DW/8);
                            burst_left <= (remaining > 256) ? 9'd256 : remaining;
                            state <= S_AW;
                        end
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule



