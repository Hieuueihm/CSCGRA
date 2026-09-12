`include "host_registers.vh"
`include "payload_dma_regs.vh"

module csr_top (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_ACLK CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:M_AXI, ASSOCIATED_RESET S_AXI_ARESETN, FREQ_HZ 100000000" *)
    input wire s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_ARESETN RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input wire s_axi_rready,
    output wire irq,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    output wire [63:0] m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0] m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0] m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0] m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
    output wire m_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
    output wire [3:0] m_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
    output wire [2:0] m_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
    output wire [3:0] m_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output wire m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input wire m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [127:0] m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [15:0] m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output wire m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input wire m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input wire [1:0] m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input wire m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output wire m_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    output wire [63:0] m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output wire [7:0] m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output wire [2:0] m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output wire [1:0] m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
    output wire m_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
    output wire [3:0] m_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
    output wire [2:0] m_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
    output wire [3:0] m_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output wire m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input wire m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input wire [127:0] m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input wire [1:0] m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input wire m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input wire m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output wire m_axi_rready
);

    localparam [1:0] AXI_OKAY = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;

    reg [1:0] reset_pipe = 2'b00;
    wire core_rst = !s_axi_aresetn || !reset_pipe[1];
    wire bus_ready = s_axi_aresetn && reset_pipe[1];

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            reset_pipe <= 2'b00;
        else
            reset_pipe <= {reset_pipe[0], 1'b1};
    end

    reg aw_hold_valid;
    reg [11:0] aw_hold_addr;
    reg w_hold_valid;
    reg [31:0] w_hold_data;
    reg [3:0] w_hold_strb;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire = s_axi_wvalid && s_axi_wready;
    wire ar_fire = s_axi_arvalid && s_axi_arready;
    wire write_exec = aw_hold_valid && w_hold_valid && !s_axi_bvalid;
    wire [11:0] write_addr = aw_hold_addr;
    wire [31:0] write_data = w_hold_data;
    wire [3:0] write_strb = w_hold_strb;

    assign s_axi_awready = bus_ready && !s_axi_bvalid && !aw_hold_valid;
    assign s_axi_wready = bus_ready && !s_axi_bvalid && !w_hold_valid;
    assign s_axi_arready = bus_ready && !s_axi_rvalid;

    function automatic [31:0] byte_mask(input [3:0] strobe);
        integer byte_number;
        begin
            byte_mask = 32'b0;
            for (byte_number = 0; byte_number < 4; byte_number = byte_number + 1)
                if (strobe[byte_number])
                    byte_mask[byte_number*8 +: 8] = 8'hff;
        end
    endfunction

    function automatic [31:0] merge32(input [31:0] old_value, input [31:0] new_value,
                                       input [3:0] strobe);
        begin
            merge32 = (old_value & ~byte_mask(strobe)) | (new_value & byte_mask(strobe));
        end
    endfunction

    function automatic onehot8(input [7:0] value);
        begin
            onehot8 = value != 8'b0 && ((value & (value - 1'b1)) == 8'b0);
        end
    endfunction

    function automatic [3:0] opcode_for_command(input [7:0] value);
        begin
            case (value)
                `CSR_HOST_COMMAND_START: opcode_for_command = `CSR_HOST_OP_START;
                `CSR_HOST_COMMAND_LOAD_BEGIN: opcode_for_command = `CSR_HOST_OP_LOAD_BEGIN;
                `CSR_HOST_COMMAND_LOAD_ITEM: opcode_for_command = `CSR_HOST_OP_LOAD_ITEM;
                `CSR_HOST_COMMAND_PHI_BEGIN: opcode_for_command = `CSR_HOST_OP_PHI_BEGIN;
                `CSR_HOST_COMMAND_HOST_READ: opcode_for_command = `CSR_HOST_OP_HOST_READ;
                `CSR_HOST_COMMAND_HOST_WRITE: opcode_for_command = `CSR_HOST_OP_HOST_WRITE;
                `CSR_HOST_COMMAND_RESULT_READ: opcode_for_command = `CSR_HOST_OP_RESULT_READ;
                default: opcode_for_command = 4'hf;
            endcase
        end
    endfunction

    wire [31:0] write_masked_data = write_data & byte_mask(write_strb);
    wire [7:0] command_value = write_masked_data[7:0];
    wire command_has_bytes = write_strb != 4'b0;
    wire command_onehot = onehot8(command_value);
    wire command_cancel = command_value == `CSR_HOST_COMMAND_CANCEL;
    wire command_reserved_nonzero = (write_masked_data & 32'hffff_ff00) != 0;
    wire command_non_cancel = command_onehot && !command_cancel && !command_reserved_nonzero;
    wire [3:0] command_opcode = opcode_for_command(command_value);

    reg [7:0] start_rows_q;
    reg [10:0] start_cols_q;
    reg [17:0] start_scale_q;
    reg [31:0] start_generation_q;
    reg [15:0] start_job_q;
    reg [15:0] start_tag_q;
    reg [127:0] start_key_q;
    reg [7:0] start_fmt_q;
    reg [1:0] start_storage_mode_q;
    reg signed [6:0] start_exponent_q;
    reg start_active_support_q;
    reg [31:0] start_limit_q;

    reg [10:0] load_program_count_q;
    reg [10:0] load_constant_count_q;
    reg [7:0] load_revision_q;
    reg [4:0] load_template_count_q;
    reg [5:0] load_vector_count_q;
    reg load_verified_q;
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
    reg [15:0] phi_tag_q;
    reg [7:0] phi_fmt_q;
    reg [31:0] phi_epoch_q;

    reg [8:0] host_block_q;
    reg [31:0] host_mask_q;
    reg [15:0] host_tag_q;
    reg host_write_q;
    reg [31:0] host_lane_q [0:31];
    reg [9:0] result_index_q;
    reg [15:0] result_tag_q;
    reg [863:0] host_data_bridge;
    integer bridge_lane;
    integer reset_lane;
    reg phi_pending_q;
    reg phi_seen_loading_q;
    reg phi_valid_q;
    reg [3:0] phi_fault_q;
    reg [15:0] phi_snapshot_job_q;
    reg [7:0] phi_snapshot_fmt_q;
    reg [31:0] phi_snapshot_generation_q;
    reg [31:0] phi_snapshot_seed_q;
    reg image_loading_q;
    reg cancel_pulse;
    wire native_busy;
    reg irq_enable_q;
    wire bridge_cmd_ready;
    wire bridge_command_active;
    wire bridge_mailbox_valid;
    wire native_p_loading;

    wire stage_safe, cancel_accept, native_committed_valid;
    wire [10:0] native_committed_length;
    reg [1:0] write_resp_calc;
    reg [63:0] dma_address_q;
    reg [31:0] dma_count_q, dma_block_q, dma_tag_q;
    reg dma_mode_q, dma_irq_enable_q, dma_input_tainted_q;
    reg [8:0] dma_tainted_block_q, dma_owned_block_q;
    reg [10:0] dma_tainted_count_q, dma_owned_count_q;
    reg dma_owned_write_q;
    wire dma_busy, dma_done, dma_ready;
    wire dma_start_ready;
    assign dma_ready = dma_start_ready;
    wire [3:0] dma_error;
    wire [31:0] dma_bytes, dma_cycles, dma_read_beats, dma_write_beats, dma_stalls;
    wire dma_host_valid, dma_host_rsp_ready, dma_read_valid, dma_read_rsp_ready;
    wire [8:0] dma_host_block;
    wire [31:0] dma_host_mask;
    wire [863:0] dma_host_data;
    wire [15:0] dma_host_tag, dma_read_tag;
    wire [9:0] dma_read_index;
    wire dma_control_write = write_addr==`CSR_DMA_REG_CONTROL;
    wire dma_stage_write = write_addr==`CSR_DMA_REG_MODE ||
        write_addr==`CSR_DMA_REG_ADDR_LO || write_addr==`CSR_DMA_REG_ADDR_HI ||
        write_addr==`CSR_DMA_REG_COUNT || write_addr==`CSR_DMA_REG_BLOCK || write_addr==`CSR_DMA_REG_TAG;
    wire dma_stage_fields_good = (write_addr!=`CSR_DMA_REG_MODE || (write_masked_data&32'hfffffffe)==0) &&
        (write_addr!=`CSR_DMA_REG_COUNT || (write_masked_data&32'hfffff800)==0) &&
        (write_addr!=`CSR_DMA_REG_BLOCK || (write_masked_data&32'hfffffe00)==0) &&
        (write_addr!=`CSR_DMA_REG_TAG || (write_masked_data&32'hffff0000)==0);
    wire [64:0] dma_end_address = {1'b0,dma_address_q}+(({33'b0,dma_count_q}+65'd3)>>2<<4);
    wire [31:0] dma_end_block = dma_block_q+((dma_count_q+31)>>5);
    wire dma_start_eligible = stage_safe && !image_loading_q && dma_ready &&
        dma_count_q>0 && dma_count_q<=1024 && dma_address_q[3:0]==0 && !dma_end_address[64] &&
        (dma_mode_q ? (native_committed_valid && dma_count_q<=native_committed_length) :
            (dma_end_block<=480 && (!dma_input_tainted_q ||
             (dma_block_q==dma_tainted_block_q && dma_count_q==dma_tainted_count_q))));
    wire dma_start = write_exec && dma_control_write && write_resp_calc==AXI_OKAY && write_masked_data==`CSR_DMA_START;
    wire dma_ack = write_exec && dma_control_write && write_resp_calc==AXI_OKAY && write_masked_data==`CSR_DMA_ACK;
    wire dma_cancel = (cancel_accept && dma_busy) || (write_exec && dma_control_write &&
        write_resp_calc==AXI_OKAY && write_masked_data==`CSR_DMA_CANCEL);
    wire core_cancel_accept = cancel_accept && !dma_busy;
    assign m_axi_awlock=1'b0;
    assign m_axi_arlock=1'b0;
    assign m_axi_awcache=4'b0;
    assign m_axi_arcache=4'b0;
    assign m_axi_awprot=3'b0;
    assign m_axi_arprot=3'b0;
    assign m_axi_awqos=4'b0;
    assign m_axi_arqos=4'b0;
    always @(posedge s_axi_aclk) begin
        if(core_rst) begin
            dma_address_q<=0; dma_count_q<=0; dma_block_q<=0; dma_tag_q<=0;
            dma_mode_q<=0; dma_irq_enable_q<=0; dma_input_tainted_q<=0;
            dma_tainted_block_q<=0; dma_tainted_count_q<=0; dma_owned_block_q<=0;
            dma_owned_count_q<=0; dma_owned_write_q<=0;
        end else begin
            if(write_exec && write_resp_calc==AXI_OKAY) begin
                case(write_addr)
                    `CSR_DMA_REG_ADDR_LO: dma_address_q[31:0]<=merge32(dma_address_q[31:0],write_data,write_strb);
                    `CSR_DMA_REG_ADDR_HI: dma_address_q[63:32]<=merge32(dma_address_q[63:32],write_data,write_strb);
                    `CSR_DMA_REG_COUNT: dma_count_q<=merge32(dma_count_q,write_data,write_strb);
                    `CSR_DMA_REG_BLOCK: dma_block_q<=merge32(dma_block_q,write_data,write_strb);
                    `CSR_DMA_REG_TAG: dma_tag_q<=merge32(dma_tag_q,write_data,write_strb);
                    `CSR_DMA_REG_MODE: if(write_strb[0]) dma_mode_q<=write_data[0];
                    `CSR_DMA_REG_IRQ: if(write_strb[0]) dma_irq_enable_q<=write_data[0];
                    default: begin end
                endcase
            end
            if(dma_done && !dma_busy && dma_error==0 && !dma_owned_write_q &&
               dma_owned_block_q==dma_tainted_block_q && dma_owned_count_q==dma_tainted_count_q)
                dma_input_tainted_q<=0;
            if(dma_start) begin
                dma_owned_write_q<=dma_mode_q;
                dma_owned_block_q<=dma_block_q[8:0]; dma_owned_count_q<=dma_count_q[10:0];
                if(!dma_mode_q) begin
                    dma_input_tainted_q<=1;
                    if(!dma_input_tainted_q) begin
                        dma_tainted_block_q<=dma_block_q[8:0]; dma_tainted_count_q<=dma_count_q[10:0];
                    end
                end
            end
        end
    end

    assign stage_safe = !dma_busy && !bridge_command_active && !bridge_mailbox_valid && !native_busy &&
        !native_p_loading && !phi_pending_q && !cancel_pulse;
    wire stage_write =
        (write_addr == `CSR_HOST_REG_START_ROWS) ||
        (write_addr == `CSR_HOST_REG_START_COLS) ||
        (write_addr == `CSR_HOST_REG_START_SCALE) ||
        (write_addr == `CSR_HOST_REG_START_GENERATION) ||
        (write_addr == `CSR_HOST_REG_START_JOB_TAG) ||
        (write_addr >= `CSR_HOST_REG_START_KEY0 && write_addr <= `CSR_HOST_REG_START_KEY3) ||
        (write_addr == `CSR_HOST_REG_START_FORMAT) ||
        (write_addr == `CSR_HOST_REG_START_STORAGE) ||
        (write_addr == `CSR_HOST_REG_START_LIMIT) ||
        (write_addr == `CSR_HOST_REG_LOAD_PROGRAM_COUNT) ||
        (write_addr == `CSR_HOST_REG_LOAD_CONSTANT_COUNT) ||
        (write_addr == `CSR_HOST_REG_LOAD_CONTROL) ||
        (write_addr == `CSR_HOST_REG_LOAD_ITEM_CONTROL) ||
        (write_addr >= `CSR_HOST_REG_LOAD_ITEM0 && write_addr <= (`CSR_HOST_REG_LOAD_ITEM0 + 12'h00c)) ||
        (write_addr == `CSR_HOST_REG_PHI_SEED) ||
        (write_addr == `CSR_HOST_REG_PHI_SHAPE) ||
        (write_addr >= `CSR_HOST_REG_PHI_KEY0 && write_addr <= `CSR_HOST_REG_PHI_KEY3) ||
        (write_addr == `CSR_HOST_REG_PHI_GENERATION) ||
        (write_addr == `CSR_HOST_REG_PHI_JOB_TAG) ||
        (write_addr == `CSR_HOST_REG_PHI_FORMAT) ||
        (write_addr == `CSR_HOST_REG_HOST_CONTROL) ||
        (write_addr == `CSR_HOST_REG_HOST_MASK) ||
        (write_addr == `CSR_HOST_REG_HOST_TAG) ||
        (write_addr >= `CSR_HOST_REG_HOST_DATA0 && write_addr <= `CSR_HOST_REG_HOST_DATA_LAST) ||
        (write_addr == `CSR_HOST_REG_RESULT_CONTROL);

    reg [3:0] write_error_calc;
    wire command_write = write_addr == `CSR_HOST_REG_COMMAND;
    wire ack_write = write_addr == `CSR_HOST_REG_ACK;
    wire irq_write = write_addr == `CSR_HOST_REG_IRQ;
    wire ack_reserved_nonzero = (write_masked_data & 32'hffff_ffc0) != 0;
    wire irq_reserved_nonzero = (write_masked_data & 32'hffff_fffe) != 0;
    wire command_to_bridge = write_exec && command_write && command_has_bytes &&
        command_non_cancel && bridge_cmd_ready && write_resp_calc == AXI_OKAY;
    assign cancel_accept = write_exec && command_write && command_has_bytes &&
        command_onehot && command_cancel && write_resp_calc == AXI_OKAY;
    wire [31:0] irq_merged = merge32({31'b0, irq_enable_q}, write_data, write_strb);
    wire [7:0] ack_value = write_masked_data[7:0];
    wire ack_done = write_exec && ack_write && write_resp_calc == AXI_OKAY &&
        (ack_value & `CSR_HOST_ACK_DONE);
    wire ack_result = write_exec && ack_write && write_resp_calc == AXI_OKAY &&
        (ack_value & `CSR_HOST_ACK_RESULT);
    wire ack_host = write_exec && ack_write && write_resp_calc == AXI_OKAY &&
        (ack_value & `CSR_HOST_ACK_HOST);
    wire ack_load = write_exec && ack_write && write_resp_calc == AXI_OKAY &&
        (ack_value & `CSR_HOST_ACK_LOAD);
    wire ack_error = write_exec && ack_write && write_resp_calc == AXI_OKAY &&
        (ack_value & `CSR_HOST_ACK_ERROR);
    wire ack_irq = write_exec && ack_write && write_resp_calc == AXI_OKAY &&
        (ack_value & `CSR_HOST_ACK_IRQ);

    always @* begin
        write_resp_calc = AXI_SLVERR;
        write_error_calc = `CSR_HOST_ERROR_BAD_ADDRESS;
        if (write_addr[1:0] != 2'b0) begin
            write_resp_calc = AXI_SLVERR;
            write_error_calc = `CSR_HOST_ERROR_BAD_ALIGNMENT;
        end else if (ack_write) begin
            if (ack_reserved_nonzero) begin
                write_resp_calc = AXI_SLVERR;
                write_error_calc = `CSR_HOST_ERROR_STROBE;
            end else begin
                write_resp_calc = AXI_OKAY;
                write_error_calc = `CSR_HOST_ERROR_NONE;
            end
        end else if (irq_write) begin
            if (irq_reserved_nonzero) begin
                write_resp_calc = AXI_SLVERR;
                write_error_calc = `CSR_HOST_ERROR_STROBE;
            end else begin
                write_resp_calc = AXI_OKAY;
                write_error_calc = `CSR_HOST_ERROR_NONE;
            end
        end else if (command_write) begin
            if (!command_has_bytes) begin
                write_resp_calc = AXI_OKAY;
                write_error_calc = `CSR_HOST_ERROR_NONE;
            end else if (command_reserved_nonzero) begin
                write_resp_calc = AXI_SLVERR;
                write_error_calc = `CSR_HOST_ERROR_STROBE;
            end else if (!command_onehot) begin
                write_resp_calc = AXI_SLVERR;
                write_error_calc = `CSR_HOST_ERROR_COMMAND;
            end else if (command_cancel || (!dma_busy && bridge_cmd_ready &&
                         !(command_value==`CSR_HOST_COMMAND_START && dma_input_tainted_q))) begin
                write_resp_calc = AXI_OKAY;
                write_error_calc = `CSR_HOST_ERROR_NONE;
            end else begin
                write_resp_calc = AXI_SLVERR;
                write_error_calc = `CSR_HOST_ERROR_BUSY;
            end
        end else if (dma_control_write) begin
            if(write_masked_data==0 || write_masked_data==`CSR_DMA_CANCEL ||
               (write_masked_data==`CSR_DMA_ACK && !dma_busy) ||
               (write_masked_data==`CSR_DMA_START && dma_start_eligible)) begin
                write_resp_calc=AXI_OKAY; write_error_calc=`CSR_HOST_ERROR_NONE;
            end else write_error_calc=`CSR_HOST_ERROR_BUSY;
        end else if (write_addr==`CSR_DMA_REG_IRQ) begin
            if((write_masked_data&32'hfffffffe)==0) begin
                write_resp_calc=AXI_OKAY; write_error_calc=`CSR_HOST_ERROR_NONE;
            end else write_error_calc=`CSR_HOST_ERROR_STROBE;
        end else if (dma_stage_write) begin
            if((!write_strb || stage_safe) && dma_stage_fields_good) begin
                write_resp_calc=AXI_OKAY; write_error_calc=`CSR_HOST_ERROR_NONE;
            end else write_error_calc=`CSR_HOST_ERROR_BUSY;
        end else if (stage_write) begin
            if (!write_strb || stage_safe) begin
                write_resp_calc = AXI_OKAY;
                write_error_calc = `CSR_HOST_ERROR_NONE;
            end else begin
                write_resp_calc = AXI_SLVERR;
                write_error_calc = `CSR_HOST_ERROR_BUSY;
            end
        end
    end

    wire [31:0] start_rows_merged = merge32({24'b0, start_rows_q}, write_data, write_strb);
    wire [31:0] start_cols_merged = merge32({21'b0, start_cols_q}, write_data, write_strb);
    wire [31:0] start_scale_merged = merge32({14'b0, start_scale_q}, write_data, write_strb);
    wire [31:0] start_job_tag_merged = merge32({start_tag_q, start_job_q}, write_data, write_strb);
    wire [31:0] start_format_merged = merge32({24'b0, start_fmt_q}, write_data, write_strb);
    wire [31:0] start_storage_current =
        {15'b0, start_active_support_q, 1'b0, start_exponent_q, 6'b0, start_storage_mode_q};
    wire [31:0] start_storage_merged = merge32(start_storage_current, write_data, write_strb);
    wire [31:0] load_program_count_merged = merge32({21'b0, load_program_count_q}, write_data, write_strb);
    wire [31:0] load_constant_count_merged = merge32({21'b0, load_constant_count_q}, write_data, write_strb);
    wire [31:0] load_control_current =
        {12'b0, load_verified_q, load_vector_count_q, load_template_count_q, load_revision_q};
    wire [31:0] load_control_merged = merge32(load_control_current, write_data, write_strb);
    wire [31:0] load_item_control_current = {12'b0, load_last_q, load_index_q, load_kind_q};
    wire [31:0] load_item_control_merged = merge32(load_item_control_current, write_data, write_strb);
    wire [31:0] phi_shape_current = {5'b0, phi_cols_q, 8'b0, phi_rows_q};
    wire [31:0] phi_shape_merged = merge32(phi_shape_current, write_data, write_strb);
    wire [31:0] phi_job_tag_merged = merge32({phi_tag_q, phi_job_q}, write_data, write_strb);
    wire [31:0] phi_format_merged = merge32({24'b0, phi_fmt_q}, write_data, write_strb);
    wire [31:0] host_control_current = {15'b0, host_write_q, 7'b0, host_block_q};
    wire [31:0] host_control_merged = merge32(host_control_current, write_data, write_strb);
    wire [31:0] host_tag_merged = merge32({16'b0, host_tag_q}, write_data, write_strb);
    wire [31:0] result_control_current = {result_tag_q, 6'b0, result_index_q};
    wire [31:0] result_control_merged = merge32(result_control_current, write_data, write_strb);

    wire bridge_cmd_accept;
    wire [3:0] bridge_active_command;
    wire bridge_load_status_valid;
    wire [3:0] bridge_load_status_fault;
    wire bridge_host_rsp_valid;
    wire bridge_host_rsp_write;
    wire [8:0] bridge_host_rsp_block;
    wire [863:0] bridge_host_rsp_data;
    wire [31:0] bridge_host_rsp_mask;
    wire [15:0] bridge_host_rsp_tag;
    wire [3:0] bridge_host_rsp_fault;
    wire bridge_result_rsp_valid;
    wire [26:0] bridge_result_rsp_data;
    wire [9:0] bridge_result_rsp_index;
    wire [15:0] bridge_result_rsp_request_tag;
    wire [3:0] bridge_result_rsp_fault;
    wire [1:0] bridge_result_rsp_mode;
    wire signed [6:0] bridge_result_rsp_exponent;
    wire [10:0] bridge_result_rsp_length;
    wire [15:0] bridge_result_rsp_job;
    wire [15:0] bridge_result_rsp_tag;
    wire [7:0] bridge_result_rsp_fmt;
    wire bridge_done_valid;
    wire [3:0] bridge_done_fault;
    wire [3:0] bridge_done_detail;
    wire [7:0] bridge_done_status;
    wire [15:0] bridge_done_outer_iterations;
    wire [15:0] bridge_done_inner_iterations;
    wire [6:0] bridge_done_support_count;
    wire bridge_done_committed;
    wire [15:0] bridge_done_job;
    wire [15:0] bridge_done_tag;
    wire [7:0] bridge_done_fmt;
    wire [63:0] bridge_done_cycles;

    wire bridge_load_begin_valid;
    wire [7:0] bridge_load_begin_revision;
    wire bridge_load_begin_verified;
    wire [10:0] bridge_load_begin_program_count;
    wire [10:0] bridge_load_begin_constant_count;
    wire [4:0] bridge_load_begin_template_count;
    wire [5:0] bridge_load_begin_vector_count;
    wire bridge_load_valid;
    wire [2:0] bridge_load_kind;
    wire [15:0] bridge_load_index;
    wire [127:0] bridge_load_data;
    wire bridge_load_last;
    wire bridge_load_status_ready;
    wire bridge_p_begin_valid;
    wire [31:0] bridge_p_begin_seed;
    wire [7:0] bridge_p_begin_rows;
    wire [10:0] bridge_p_begin_cols;
    wire [127:0] bridge_p_begin_key;
    wire [31:0] bridge_p_begin_generation;
    wire [15:0] bridge_p_begin_job;
    wire [7:0] bridge_p_begin_fmt;
    wire bridge_host_valid;
    wire bridge_host_write;
    wire [8:0] bridge_host_block;
    wire [31:0] bridge_host_mask;
    wire [863:0] bridge_host_data;
    wire [15:0] bridge_host_tag;
    wire bridge_host_rsp_ready;
    wire bridge_start_valid;
    wire [7:0] bridge_start_rows;
    wire [10:0] bridge_start_cols;
    wire [127:0] bridge_start_key;
    wire [31:0] bridge_start_generation;
    wire [17:0] bridge_start_scale;
    wire [15:0] bridge_start_job;
    wire [15:0] bridge_start_tag;
    wire [7:0] bridge_start_fmt;
    wire [31:0] bridge_start_instruction_limit;
    wire [1:0] bridge_start_storage_mode;
    wire signed [6:0] bridge_start_exponent;
    wire bridge_start_active_support;
    wire bridge_done_ready;
    wire bridge_read_valid;
    wire [9:0] bridge_read_index;
    wire [15:0] bridge_read_tag;
    wire bridge_read_rsp_ready;

    wire native_load_begin_ready;
    wire native_load_ready;
    wire native_p_begin_ready;
    wire native_host_ready;
    wire native_host_rsp_valid;
    wire native_host_rsp_write;
    wire [863:0] native_host_rsp_data;
    wire [31:0] native_host_rsp_mask;
    wire [15:0] native_host_rsp_tag;
    wire [3:0] native_host_rsp_fault;
    wire native_start_ready;
    wire native_done_valid;
    wire native_read_ready;
    wire native_load_status_valid;
    wire [3:0] native_load_status_fault;
    wire native_image_valid;
    wire [3:0] native_p_fault;
    wire native_p_valid;
    wire native_read_rsp_valid;
    wire [26:0] native_read_rsp_data;
    wire [9:0] native_read_rsp_index;
    wire [15:0] native_read_rsp_request_tag;
    wire [3:0] native_read_rsp_fault;
    wire [1:0] native_read_rsp_mode;
    wire signed [6:0] native_read_rsp_exponent;
    wire [10:0] native_read_rsp_length;
    wire [15:0] native_read_rsp_job;
    wire [15:0] native_read_rsp_tag;
    wire [7:0] native_read_rsp_fmt;
    wire [7:0] native_committed_rows;
    wire [1:0] native_committed_mode;
    wire signed [6:0] native_committed_exponent;
    wire native_committed_active_support;
    wire [6:0] native_committed_support_count;
    wire [959:0] native_committed_support;
    wire [7:0] native_committed_status;
    wire [15:0] native_committed_outer_iterations;
    wire [15:0] native_committed_inner_iterations;
    wire [15:0] native_committed_job;
    wire [15:0] native_committed_tag;
    wire [7:0] native_committed_fmt;
    wire [127:0] native_committed_key;
    wire [31:0] native_committed_generation;
    wire [3:0] native_done_detail;
    wire [7:0] native_done_status;
    wire [15:0] native_done_outer_iterations;
    wire [15:0] native_done_inner_iterations;
    wire [6:0] native_done_support_count;
    wire native_done_committed;
    wire [15:0] native_done_job;
    wire [15:0] native_done_tag;
    wire [7:0] native_done_fmt;
    wire [63:0] native_job_cycles;
    wire [3:0] native_done_fault;
    wire [9:0] native_trace_pc;
    wire [127:0] native_trace_word;
    wire native_trace_retire;
    wire [7:0] native_p_rows;
    wire [10:0] native_p_cols;
    wire [127:0] native_p_key;
    wire [31:0] native_p_generation;
    wire [15:0] native_p_job;
    wire [7:0] native_p_fmt;

    reg irq_pending_q;
    reg cancel_seen_q;
    reg error_valid_q;
    reg [3:0] error_code_q;
    reg [3:0] error_detail_q;
    reg [11:0] error_offset_q;
    reg [3:0] last_event_q;
    reg [3:0] last_event_command_q;
    reg [15:0] event_sequence_q;
    reg [31:0] read_data_calc;
    reg [1:0] read_resp_calc;

    wire native_load_status_fire = native_load_status_valid && bridge_load_status_ready;
    wire native_load_begin_fire = bridge_load_begin_valid && native_load_begin_ready;
    wire native_host_rsp_fire = native_host_rsp_valid && bridge_host_rsp_ready && !dma_busy;
    wire native_read_rsp_fire = native_read_rsp_valid && bridge_read_rsp_ready && !dma_busy;
    wire native_done_fire = native_done_valid && bridge_done_ready;
    wire native_phi_fire = bridge_p_begin_valid && native_p_begin_ready;
    wire phi_fill_complete = phi_pending_q && !native_p_loading &&
        (phi_seen_loading_q || native_p_fault != 0);
    wire phi_fill_success = phi_fill_complete && native_p_fault == 0;
    wire new_native_event = native_load_status_fire || native_host_rsp_fire ||
        native_read_rsp_fire || native_done_fire || native_phi_fire || phi_fill_complete;
    wire write_error_event = write_exec && write_resp_calc == AXI_SLVERR;
    wire read_error_event = ar_fire && read_resp_calc == AXI_SLVERR;
    wire new_error_event = write_error_event || read_error_event;

    host_command_bridge host_bridge (
        .clk(s_axi_aclk), .rst(core_rst), .cancel(cancel_pulse),
        .cmd_valid(command_to_bridge), .cmd_ready(bridge_cmd_ready), .cmd_accept(bridge_cmd_accept),
        .cmd_opcode(command_opcode),
        .cmd_start_rows(start_rows_q), .cmd_start_cols(start_cols_q), .cmd_start_key(start_key_q),
        .cmd_start_generation(start_generation_q), .cmd_start_scale(start_scale_q),
        .cmd_start_job(start_job_q), .cmd_start_tag(start_tag_q), .cmd_start_fmt(start_fmt_q),
        .cmd_start_instruction_limit(start_limit_q), .cmd_start_storage_mode(start_storage_mode_q),
        .cmd_start_exponent(start_exponent_q), .cmd_start_active_support(start_active_support_q),
        .cmd_load_revision(load_revision_q), .cmd_load_verified(load_verified_q),
        .cmd_load_program_count(load_program_count_q), .cmd_load_constant_count(load_constant_count_q),
        .cmd_load_template_count(load_template_count_q), .cmd_load_vector_count(load_vector_count_q),
        .cmd_load_kind(load_kind_q), .cmd_load_index(load_index_q), .cmd_load_data(load_data_q),
        .cmd_load_last(load_last_q),
        .cmd_phi_seed(phi_seed_q), .cmd_phi_rows(phi_rows_q), .cmd_phi_cols(phi_cols_q),
        .cmd_phi_key(phi_key_q), .cmd_phi_generation(phi_generation_q), .cmd_phi_job(phi_job_q),
        .cmd_phi_fmt(phi_fmt_q), .cmd_host_write(host_write_q), .cmd_host_block(host_block_q),
        .cmd_host_mask(host_mask_q), .cmd_host_data(host_data_bridge), .cmd_host_tag(host_tag_q),
        .cmd_result_index(result_index_q), .cmd_result_tag(result_tag_q),
        .command_active(bridge_command_active), .active_command(bridge_active_command),
        .mailbox_valid(bridge_mailbox_valid), .load_status_valid(bridge_load_status_valid),
        .load_status_fault(bridge_load_status_fault), .load_status_ack(ack_load),
        .host_rsp_valid(bridge_host_rsp_valid), .host_rsp_write(bridge_host_rsp_write), .host_rsp_block(bridge_host_rsp_block),
        .host_rsp_data(bridge_host_rsp_data), .host_rsp_mask(bridge_host_rsp_mask),
        .host_rsp_tag(bridge_host_rsp_tag), .host_rsp_fault(bridge_host_rsp_fault), .host_rsp_ack(ack_host),
        .result_rsp_valid(bridge_result_rsp_valid), .result_rsp_data(bridge_result_rsp_data),
        .result_rsp_index(bridge_result_rsp_index), .result_rsp_request_tag(bridge_result_rsp_request_tag),
        .result_rsp_fault(bridge_result_rsp_fault), .result_rsp_mode(bridge_result_rsp_mode),
        .result_rsp_exponent(bridge_result_rsp_exponent), .result_rsp_length(bridge_result_rsp_length),
        .result_rsp_job(bridge_result_rsp_job), .result_rsp_tag(bridge_result_rsp_tag),
        .result_rsp_fmt(bridge_result_rsp_fmt), .result_rsp_ack(ack_result),
        .done_mailbox_valid(bridge_done_valid), .done_fault(bridge_done_fault), .done_detail(bridge_done_detail),
        .done_status(bridge_done_status), .done_outer_iterations(bridge_done_outer_iterations),
        .done_inner_iterations(bridge_done_inner_iterations), .done_support_count(bridge_done_support_count),
        .done_committed(bridge_done_committed), .done_job(bridge_done_job), .done_tag(bridge_done_tag),
        .done_fmt(bridge_done_fmt), .done_cycles(bridge_done_cycles), .done_ack(ack_done),
        .native_load_begin_valid(bridge_load_begin_valid), .native_load_begin_ready(native_load_begin_ready),
        .native_load_begin_revision(bridge_load_begin_revision), .native_load_begin_verified(bridge_load_begin_verified),
        .native_load_begin_program_count(bridge_load_begin_program_count),
        .native_load_begin_constant_count(bridge_load_begin_constant_count),
        .native_load_begin_template_count(bridge_load_begin_template_count),
        .native_load_begin_vector_count(bridge_load_begin_vector_count),
        .native_load_valid(bridge_load_valid), .native_load_ready(native_load_ready),
        .native_load_kind(bridge_load_kind), .native_load_index(bridge_load_index),
        .native_load_data(bridge_load_data), .native_load_last(bridge_load_last),
        .native_load_status_valid(native_load_status_valid), .native_load_status_ready(bridge_load_status_ready),
        .native_load_status_fault(native_load_status_fault),
        .native_p_begin_ready(native_p_begin_ready), .native_p_begin_valid(bridge_p_begin_valid),
        .native_p_begin_seed(bridge_p_begin_seed), .native_p_begin_rows(bridge_p_begin_rows),
        .native_p_begin_cols(bridge_p_begin_cols), .native_p_begin_key(bridge_p_begin_key),
        .native_p_begin_generation(bridge_p_begin_generation), .native_p_begin_job(bridge_p_begin_job),
        .native_p_begin_fmt(bridge_p_begin_fmt),
        .native_host_valid(bridge_host_valid), .native_host_ready(native_host_ready && !dma_busy),
        .native_host_write(bridge_host_write), .native_host_block(bridge_host_block),
        .native_host_mask(bridge_host_mask), .native_host_data(bridge_host_data), .native_host_tag(bridge_host_tag),
        .native_host_rsp_valid(native_host_rsp_valid && !dma_busy), .native_host_rsp_ready(bridge_host_rsp_ready),
        .native_host_rsp_write(native_host_rsp_write), .native_host_rsp_data(native_host_rsp_data),
        .native_host_rsp_mask(native_host_rsp_mask), .native_host_rsp_tag(native_host_rsp_tag),
        .native_host_rsp_fault(native_host_rsp_fault),
        .native_start_ready(native_start_ready), .native_start_valid(bridge_start_valid),
        .native_start_rows(bridge_start_rows), .native_start_cols(bridge_start_cols), .native_start_key(bridge_start_key),
        .native_start_generation(bridge_start_generation), .native_start_scale(bridge_start_scale),
        .native_start_job(bridge_start_job), .native_start_tag(bridge_start_tag), .native_start_fmt(bridge_start_fmt),
        .native_start_instruction_limit(bridge_start_instruction_limit),
        .native_start_storage_mode(bridge_start_storage_mode), .native_start_exponent(bridge_start_exponent),
        .native_start_active_support(bridge_start_active_support), .native_done_valid(native_done_valid),
        .native_done_ready(bridge_done_ready), .native_done_fault(native_done_fault),
        .native_done_detail(native_done_detail), .native_done_status(native_done_status),
        .native_done_outer_iterations(native_done_outer_iterations),
        .native_done_inner_iterations(native_done_inner_iterations),
        .native_done_support_count(native_done_support_count), .native_done_committed(native_done_committed),
        .native_done_job(native_done_job), .native_done_tag(native_done_tag), .native_done_fmt(native_done_fmt),
        .native_done_cycles(native_job_cycles), .native_read_ready(native_read_ready && !dma_busy),
        .native_read_valid(bridge_read_valid), .native_read_index(bridge_read_index), .native_read_tag(bridge_read_tag),
        .native_read_rsp_valid(native_read_rsp_valid && !dma_busy), .native_read_rsp_ready(bridge_read_rsp_ready),
        .native_read_rsp_data(native_read_rsp_data), .native_read_rsp_index(native_read_rsp_index),
        .native_read_rsp_request_tag(native_read_rsp_request_tag), .native_read_rsp_fault(native_read_rsp_fault),
        .native_read_rsp_mode(native_read_rsp_mode), .native_read_rsp_exponent(native_read_rsp_exponent),
        .native_read_rsp_length(native_read_rsp_length), .native_read_rsp_job(native_read_rsp_job),
        .native_read_rsp_tag(native_read_rsp_tag), .native_read_rsp_fmt(native_read_rsp_fmt)
    );

    payload_dma_engine payload_dma (
        .clk(s_axi_aclk), .rst(core_rst), .cancel(dma_cancel), .ack(dma_ack),
        .start(dma_start && dma_start_eligible), .start_ready(dma_start_ready),
        .direction_write(dma_mode_q), .base_addr(dma_address_q), .element_count(dma_count_q[10:0]),
        .block_base(dma_block_q[8:0]), .tag(dma_tag_q[15:0]), .busy(dma_busy), .done(dma_done),
        .error_code(dma_error), .completed_bytes(dma_bytes), .active_cycles(dma_cycles),
        .read_beats(dma_read_beats), .write_beats(dma_write_beats), .stall_cycles(dma_stalls),
        .host_valid(dma_host_valid), .host_ready(native_host_ready && dma_busy),
        .host_block(dma_host_block), .host_mask(dma_host_mask), .host_data(dma_host_data), .host_tag(dma_host_tag),
        .host_rsp_valid(native_host_rsp_valid), .host_rsp_ready(dma_host_rsp_ready),
        .host_rsp_write(native_host_rsp_write), .host_rsp_mask(native_host_rsp_mask),
        .host_rsp_tag(native_host_rsp_tag), .host_rsp_fault(native_host_rsp_fault),
        .read_valid(dma_read_valid), .read_ready(native_read_ready && dma_busy),
        .read_index(dma_read_index), .read_tag(dma_read_tag), .read_rsp_valid(native_read_rsp_valid),
        .read_rsp_ready(dma_read_rsp_ready), .read_rsp_data(native_read_rsp_data),
        .read_rsp_index(native_read_rsp_index), .read_rsp_request_tag(native_read_rsp_request_tag),
        .read_rsp_fault(native_read_rsp_fault),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready));

    always @* begin
        host_data_bridge = 864'b0;
        for (bridge_lane = 0; bridge_lane < 32; bridge_lane = bridge_lane + 1)
            host_data_bridge[bridge_lane*27 +: 27] = host_lane_q[bridge_lane][26:0];
    end

    recovery_engine engine (
        .clk(s_axi_aclk), .rst(core_rst), .cancel(cancel_pulse),
        .load_begin_valid(bridge_load_begin_valid), .load_begin_ready(native_load_begin_ready),
        .load_begin_revision(bridge_load_begin_revision), .load_begin_verified(bridge_load_begin_verified),
        .load_begin_program_count(bridge_load_begin_program_count),
        .load_begin_constant_count(bridge_load_begin_constant_count),
        .load_begin_template_count(bridge_load_begin_template_count),
        .load_begin_vector_count(bridge_load_begin_vector_count),
        .load_valid(bridge_load_valid), .load_ready(native_load_ready), .load_kind(bridge_load_kind),
        .load_index(bridge_load_index), .load_data(bridge_load_data), .load_last(bridge_load_last),
        .load_status_valid(native_load_status_valid), .load_status_ready(bridge_load_status_ready),
        .load_status_fault(native_load_status_fault), .image_valid(native_image_valid),
        .p_begin_valid(bridge_p_begin_valid), .p_begin_ready(native_p_begin_ready),
        .p_begin_seed(bridge_p_begin_seed), .p_begin_rows(bridge_p_begin_rows), .p_begin_cols(bridge_p_begin_cols),
        .p_begin_key(bridge_p_begin_key), .p_begin_generation(bridge_p_begin_generation),
        .p_begin_job(bridge_p_begin_job), .p_begin_fmt(bridge_p_begin_fmt), .p_loading(native_p_loading),
        .p_fault(native_p_fault), .p_valid(native_p_valid), .host_valid(dma_busy ? dma_host_valid : bridge_host_valid),
        .host_ready(native_host_ready), .host_write(dma_busy ? 1'b1 : bridge_host_write), .host_block(dma_busy ? dma_host_block : bridge_host_block),
        .host_mask(dma_busy ? dma_host_mask : bridge_host_mask), .host_data(dma_busy ? dma_host_data : bridge_host_data), .host_tag(dma_busy ? dma_host_tag : bridge_host_tag),
        .host_rsp_valid(native_host_rsp_valid), .host_rsp_ready(dma_busy ? dma_host_rsp_ready : bridge_host_rsp_ready),
        .host_rsp_write(native_host_rsp_write), .host_rsp_data(native_host_rsp_data),
        .host_rsp_mask(native_host_rsp_mask), .host_rsp_tag(native_host_rsp_tag),
        .host_rsp_fault(native_host_rsp_fault), .start_valid(bridge_start_valid),
        .start_ready(native_start_ready), .start_rows(bridge_start_rows), .start_cols(bridge_start_cols),
        .start_key(bridge_start_key), .start_generation(bridge_start_generation), .start_scale(bridge_start_scale),
        .start_job(bridge_start_job), .start_tag(bridge_start_tag), .start_fmt(bridge_start_fmt),
        .start_instruction_limit(bridge_start_instruction_limit), .start_storage_mode(bridge_start_storage_mode),
        .start_exponent(bridge_start_exponent), .start_active_support(bridge_start_active_support),
        .done_valid(native_done_valid), .done_ready(bridge_done_ready), .done_fault(native_done_fault),
        .done_detail(native_done_detail), .done_status(native_done_status),
        .done_outer_iterations(native_done_outer_iterations), .done_inner_iterations(native_done_inner_iterations),
        .done_support_count(native_done_support_count), .done_committed(native_done_committed),
        .done_job(native_done_job), .done_tag(native_done_tag), .done_fmt(native_done_fmt),
        .job_cycles(native_job_cycles), .trace_pc(native_trace_pc), .trace_word(native_trace_word),
        .trace_retire(native_trace_retire), .busy(native_busy), .committed_valid(native_committed_valid),
        .committed_rows(native_committed_rows), .committed_length(native_committed_length),
        .committed_mode(native_committed_mode), .committed_exponent(native_committed_exponent),
        .committed_active_support(native_committed_active_support),
        .committed_support_count(native_committed_support_count), .committed_support(native_committed_support),
        .committed_status(native_committed_status),
        .committed_outer_iterations(native_committed_outer_iterations),
        .committed_inner_iterations(native_committed_inner_iterations),
        .committed_job(native_committed_job), .committed_tag(native_committed_tag),
        .committed_fmt(native_committed_fmt), .committed_key(native_committed_key),
        .committed_generation(native_committed_generation), .read_valid(dma_busy ? dma_read_valid : bridge_read_valid),
        .read_ready(native_read_ready), .read_index(dma_busy ? dma_read_index : bridge_read_index), .read_tag(dma_busy ? dma_read_tag : bridge_read_tag),
        .read_rsp_valid(native_read_rsp_valid), .read_rsp_ready(dma_busy ? dma_read_rsp_ready : bridge_read_rsp_ready),
        .read_rsp_data(native_read_rsp_data), .read_rsp_index(native_read_rsp_index),
        .read_rsp_request_tag(native_read_rsp_request_tag), .read_rsp_fault(native_read_rsp_fault),
        .read_rsp_mode(native_read_rsp_mode), .read_rsp_exponent(native_read_rsp_exponent),
        .read_rsp_length(native_read_rsp_length), .read_rsp_job(native_read_rsp_job),
        .read_rsp_tag(native_read_rsp_tag), .read_rsp_fmt(native_read_rsp_fmt)
    );

    always @* begin
        read_data_calc = 32'b0;
        read_resp_calc = AXI_SLVERR;
        if (s_axi_araddr[1:0] == 2'b0) begin
            case (s_axi_araddr)
                `CSR_DMA_REG_ID: begin read_data_calc=32'h00010080; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_CONTROL: begin read_data_calc=0; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_STATUS: begin
                    read_data_calc={27'b0,dma_input_tainted_q,dma_start_eligible,(dma_error!=0),dma_done,dma_busy};
                    read_resp_calc=AXI_OKAY;
                end
                `CSR_DMA_REG_MODE: begin read_data_calc={31'b0,dma_mode_q}; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_ADDR_LO: begin read_data_calc=dma_address_q[31:0]; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_ADDR_HI: begin read_data_calc=dma_address_q[63:32]; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_COUNT: begin read_data_calc=dma_count_q; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_BLOCK: begin read_data_calc=dma_block_q; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_TAG: begin read_data_calc=dma_tag_q; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_IRQ: begin read_data_calc={30'b0,dma_done,dma_irq_enable_q}; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_ERROR: begin read_data_calc={28'b0,dma_error}; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_BYTES: begin read_data_calc=dma_bytes; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_CYCLES: begin read_data_calc=dma_cycles; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_READ_BEATS: begin read_data_calc=dma_read_beats; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_WRITE_BEATS: begin read_data_calc=dma_write_beats; read_resp_calc=AXI_OKAY; end
                `CSR_DMA_REG_STALLS: begin read_data_calc=dma_stalls; read_resp_calc=AXI_OKAY; end
                `CSR_HOST_REG_ID: begin read_data_calc = `CSR_HOST_VERSION; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_STATUS: begin
                    read_data_calc = 32'b0;
                    read_data_calc[0] = native_busy;
                    read_data_calc[1] = native_image_valid;
                    read_data_calc[2] = image_loading_q;
                    read_data_calc[3] = native_p_valid;
                    read_data_calc[4] = native_p_loading;
                    read_data_calc[5] = bridge_command_active;
                    read_data_calc[6] = bridge_mailbox_valid;
                    read_data_calc[7] = bridge_done_valid;
                    read_data_calc[8] = bridge_host_rsp_valid;
                    read_data_calc[9] = bridge_result_rsp_valid;
                    read_data_calc[10] = bridge_load_status_valid;
                    read_data_calc[11] = bridge_cmd_ready;
                    read_data_calc[12] = native_committed_valid;
                    read_data_calc[13] = cancel_seen_q;
                    read_data_calc[14] = error_valid_q;
                    read_data_calc[15] = bus_ready && !s_axi_bvalid && !s_axi_rvalid;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_IRQ: begin read_data_calc = {30'b0, irq_pending_q, irq_enable_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_ACK, `CSR_HOST_REG_COMMAND: begin read_data_calc = 32'b0; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_ERROR: begin
                    read_data_calc = 32'b0;
                    read_data_calc[3:0] = error_code_q;
                    read_data_calc[7:4] = error_detail_q;
                    read_data_calc[15:8] = error_offset_q[7:0];
                    read_data_calc[27:16] = error_offset_q;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_EVENT: begin
                    read_data_calc = {8'b0, event_sequence_q, last_event_command_q, last_event_q};
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_START_ROWS: begin read_data_calc = {24'b0, start_rows_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_COLS: begin read_data_calc = {21'b0, start_cols_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_SCALE: begin read_data_calc = {14'b0, start_scale_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_GENERATION: begin read_data_calc = start_generation_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_JOB_TAG: begin read_data_calc = {start_tag_q, start_job_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_KEY0: begin read_data_calc = start_key_q[31:0]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_KEY1: begin read_data_calc = start_key_q[63:32]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_KEY2: begin read_data_calc = start_key_q[95:64]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_KEY3: begin read_data_calc = start_key_q[127:96]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_FORMAT: begin read_data_calc = {24'b0, start_fmt_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_START_STORAGE: begin
                    read_data_calc = 32'b0; read_data_calc[1:0] = start_storage_mode_q;
                    read_data_calc[14:8] = start_exponent_q; read_data_calc[16] = start_active_support_q;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_START_LIMIT: begin read_data_calc = start_limit_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_PROGRAM_COUNT: begin read_data_calc = {21'b0, load_program_count_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_CONSTANT_COUNT: begin read_data_calc = {21'b0, load_constant_count_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_CONTROL: begin read_data_calc = load_control_current; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_ITEM_CONTROL: begin read_data_calc = load_item_control_current; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_ITEM0: begin read_data_calc = load_data_q[31:0]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_ITEM1: begin read_data_calc = load_data_q[63:32]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_ITEM2: begin read_data_calc = load_data_q[95:64]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_LOAD_ITEM3: begin read_data_calc = load_data_q[127:96]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_SEED: begin read_data_calc = phi_seed_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_SHAPE: begin read_data_calc = phi_shape_current; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_KEY0: begin read_data_calc = phi_key_q[31:0]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_KEY1: begin read_data_calc = phi_key_q[63:32]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_KEY2: begin read_data_calc = phi_key_q[95:64]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_KEY3: begin read_data_calc = phi_key_q[127:96]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_GENERATION: begin read_data_calc = phi_generation_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_JOB_TAG: begin read_data_calc = {phi_tag_q, phi_job_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_FORMAT: begin read_data_calc = {24'b0, phi_fmt_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_HOST_CONTROL: begin read_data_calc = host_control_current; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_HOST_MASK: begin read_data_calc = host_mask_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_HOST_TAG: begin read_data_calc = {16'b0, host_tag_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_RESULT_CONTROL: begin read_data_calc = result_control_current; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_RESULT_DATA: begin read_data_calc = {bridge_result_rsp_fault, 1'b0, bridge_result_rsp_data}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_RESULT_ID: begin read_data_calc = {bridge_result_rsp_request_tag, 6'b0, bridge_result_rsp_index}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_RESULT_META: begin
                    read_data_calc = 32'b0; read_data_calc[1:0] = bridge_result_rsp_mode;
                    read_data_calc[8:2] = bridge_result_rsp_exponent; read_data_calc[19:9] = bridge_result_rsp_length;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_RESULT_JOB_TAG: begin read_data_calc = {bridge_result_rsp_tag, bridge_result_rsp_job}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_RESULT_FORMAT: begin read_data_calc = {15'b0, bridge_result_rsp_valid, 8'b0, bridge_result_rsp_fmt}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_RESULT_STATE: begin read_data_calc = {23'b0, bridge_result_rsp_valid, 4'b0, bridge_result_rsp_fault}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_HOST_RESPONSE_CONTROL: begin
                    read_data_calc = 32'b0; read_data_calc[8:0] = bridge_host_rsp_block;
                    read_data_calc[16] = bridge_host_rsp_write; read_data_calc[24] = bridge_host_rsp_valid;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_HOST_RESPONSE_MASK: begin read_data_calc = bridge_host_rsp_mask; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_HOST_RESPONSE_TAG_FAULT: begin
                    read_data_calc = 32'b0; read_data_calc[15:0] = bridge_host_rsp_tag;
                    read_data_calc[19:16] = bridge_host_rsp_fault; read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_DONE_STATUS: begin
                    read_data_calc = 32'b0; read_data_calc[3:0] = bridge_done_fault;
                    read_data_calc[7:4] = bridge_done_detail; read_data_calc[15:8] = bridge_done_status;
                    read_data_calc[16] = bridge_done_committed; read_data_calc[17] = bridge_done_valid;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_DONE_ITERATIONS: begin read_data_calc = {bridge_done_inner_iterations, bridge_done_outer_iterations}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_DONE_SUPPORT: begin read_data_calc = {bridge_done_job, bridge_done_fmt, 1'b0, bridge_done_support_count}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_DONE_TAG: begin read_data_calc = {16'b0, bridge_done_tag}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_DONE_CYCLES_LO: begin read_data_calc = bridge_done_cycles[31:0]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_DONE_CYCLES_HI: begin read_data_calc = bridge_done_cycles[63:32]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_META: begin
                    read_data_calc = 32'b0; read_data_calc[0] = native_committed_valid;
                    read_data_calc[1] = native_committed_active_support;
                    read_data_calc[9:2] = native_committed_rows; read_data_calc[11:10] = native_committed_mode;
                    read_data_calc[18:12] = native_committed_exponent;
                    read_data_calc[26:19] = native_committed_status;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_COMMITTED_LENGTH: begin
                    read_data_calc = 32'b0; read_data_calc[10:0] = native_committed_length;
                    read_data_calc[18:12] = native_committed_support_count; read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_COMMITTED_ITERATIONS: begin read_data_calc = {native_committed_inner_iterations, native_committed_outer_iterations}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_JOB_TAG: begin read_data_calc = {native_committed_tag, native_committed_job}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_FORMAT: begin read_data_calc = {24'b0, native_committed_fmt}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_KEY0: begin read_data_calc = native_committed_key[31:0]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_KEY1: begin read_data_calc = native_committed_key[63:32]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_KEY2: begin read_data_calc = native_committed_key[95:64]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_KEY3: begin read_data_calc = native_committed_key[127:96]; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMITTED_GENERATION: begin read_data_calc = native_committed_generation; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_IMAGE_STATUS: begin
                    read_data_calc = 32'b0; read_data_calc[0] = native_image_valid;
                    read_data_calc[1] = bridge_load_status_valid; read_data_calc[7:4] = bridge_load_status_fault;
                    read_data_calc[8] = image_loading_q; read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_PHI_STATUS: begin
                    read_data_calc = 32'b0; read_data_calc[0] = phi_valid_q;
                    read_data_calc[1] = phi_pending_q || native_p_loading; read_data_calc[7:4] = phi_fault_q;
                    read_resp_calc = AXI_OKAY;
                end
                `CSR_HOST_REG_PHI_IDENTITY: begin read_data_calc = {8'b0, phi_snapshot_fmt_q, phi_snapshot_job_q}; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_GENERATION_READ: begin read_data_calc = phi_snapshot_generation_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_SEED_READ: begin read_data_calc = phi_snapshot_seed_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_PHI_EPOCH: begin read_data_calc = phi_epoch_q; read_resp_calc = AXI_OKAY; end
                `CSR_HOST_REG_COMMAND_STATE: begin
                    read_data_calc = 32'b0; read_data_calc[3:0] = bridge_active_command;
                    read_data_calc[4] = bridge_command_active; read_data_calc[5] = bridge_mailbox_valid;
                    read_resp_calc = AXI_OKAY;
                end
                default: begin
                    if (s_axi_araddr >= `CSR_HOST_REG_HOST_DATA0 && s_axi_araddr <= `CSR_HOST_REG_HOST_DATA_LAST) begin
                        read_data_calc = {5'b0, host_lane_q[(s_axi_araddr - `CSR_HOST_REG_HOST_DATA0) >> 2][26:0]};
                        read_resp_calc = AXI_OKAY;
                    end else if (s_axi_araddr >= `CSR_HOST_REG_HOST_RESPONSE_DATA0 && s_axi_araddr <= `CSR_HOST_REG_HOST_RESPONSE_DATA_LAST) begin
                        read_data_calc = {5'b0, bridge_host_rsp_data[((s_axi_araddr - `CSR_HOST_REG_HOST_RESPONSE_DATA0) >> 2)*27 +: 27]};
                        read_resp_calc = AXI_OKAY;
                    end else if (s_axi_araddr >= `CSR_HOST_REG_COMMITTED_SUPPORT0 && s_axi_araddr <= `CSR_HOST_REG_COMMITTED_SUPPORT_LAST) begin
                        read_data_calc = native_committed_support[((s_axi_araddr - `CSR_HOST_REG_COMMITTED_SUPPORT0) >> 2)*32 +: 32];
                        read_resp_calc = AXI_OKAY;
                    end
                end
            endcase
        end else begin
            read_resp_calc = AXI_SLVERR;
        end
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || core_rst) begin
            aw_hold_valid <= 1'b0;
            aw_hold_addr <= 12'b0;
            w_hold_valid <= 1'b0;
            w_hold_data <= 32'b0;
            w_hold_strb <= 4'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= AXI_OKAY;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= AXI_OKAY;
            irq_enable_q <= 1'b0;
            irq_pending_q <= 1'b0;
            cancel_pulse <= 1'b0;
            cancel_seen_q <= 1'b0;
            error_valid_q <= 1'b0;
            error_code_q <= `CSR_HOST_ERROR_NONE;
            error_detail_q <= 4'b0;
            error_offset_q <= 12'b0;
            last_event_q <= `CSR_HOST_EVENT_NONE;
            last_event_command_q <= 4'b0;
            event_sequence_q <= 16'b0;
            phi_epoch_q <= 32'b0;
            start_rows_q <= 8'b0;
            start_cols_q <= 11'b0;
            start_scale_q <= 18'b0;
            start_generation_q <= 32'b0;
            start_job_q <= 16'b0;
            start_tag_q <= 16'b0;
            start_key_q <= 128'b0;
            start_fmt_q <= 8'b0;
            start_storage_mode_q <= 2'b0;
            start_exponent_q <= 7'sd0;
            start_active_support_q <= 1'b0;
            start_limit_q <= 32'b0;
            load_program_count_q <= 11'b0;
            load_constant_count_q <= 11'b0;
            load_revision_q <= 8'b0;
            load_template_count_q <= 5'b0;
            load_vector_count_q <= 6'b0;
            load_verified_q <= 1'b0;
            load_kind_q <= 3'b0;
            load_index_q <= 16'b0;
            load_data_q <= 128'b0;
            load_last_q <= 1'b0;
            phi_seed_q <= 32'b0;
            phi_rows_q <= 8'b0;
            phi_cols_q <= 11'b0;
            phi_key_q <= 128'b0;
            phi_generation_q <= 32'b0;
            phi_job_q <= 16'b0;
            phi_tag_q <= 16'b0;
            phi_fmt_q <= 8'b0;
            host_block_q <= 9'b0;
            host_mask_q <= 32'b0;
            host_tag_q <= 16'b0;
            host_write_q <= 1'b0;
            result_index_q <= 10'b0;
            result_tag_q <= 16'b0;
            for (reset_lane = 0; reset_lane < 32; reset_lane = reset_lane + 1)
                host_lane_q[reset_lane] <= 32'b0;
            phi_pending_q <= 1'b0;
            phi_seen_loading_q <= 1'b0;
            phi_valid_q <= 1'b0;
            phi_fault_q <= 4'b0;
            phi_snapshot_job_q <= 16'b0;
            phi_snapshot_fmt_q <= 8'b0;
            phi_snapshot_generation_q <= 32'b0;
            phi_snapshot_seed_q <= 32'b0;
            image_loading_q <= 1'b0;
        end else begin
            cancel_pulse <= 1'b0;
            if (ack_done || ack_result || ack_host || ack_load || ack_error || ack_irq) begin
                if (ack_error)
                    error_valid_q <= 1'b0;
                if (ack_irq)
                    irq_pending_q <= 1'b0;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
            if (aw_fire) begin
                aw_hold_valid <= 1'b1;
                aw_hold_addr <= s_axi_awaddr;
            end
            if (w_fire) begin
                w_hold_valid <= 1'b1;
                w_hold_data <= s_axi_wdata;
                w_hold_strb <= s_axi_wstrb;
            end
            if (write_exec) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= write_resp_calc;
                if (write_resp_calc == AXI_OKAY && stage_safe) begin
                    case (write_addr)
                        `CSR_HOST_REG_START_ROWS: start_rows_q <= start_rows_merged[7:0];
                        `CSR_HOST_REG_START_COLS: start_cols_q <= start_cols_merged[10:0];
                        `CSR_HOST_REG_START_SCALE: start_scale_q <= start_scale_merged[17:0];
                        `CSR_HOST_REG_START_GENERATION: start_generation_q <= merge32(start_generation_q, write_data, write_strb);
                        `CSR_HOST_REG_START_JOB_TAG: begin
                            start_job_q <= start_job_tag_merged[15:0];
                            start_tag_q <= start_job_tag_merged[31:16];
                        end
                        `CSR_HOST_REG_START_KEY0: start_key_q[31:0] <= merge32(start_key_q[31:0], write_data, write_strb);
                        `CSR_HOST_REG_START_KEY1: start_key_q[63:32] <= merge32(start_key_q[63:32], write_data, write_strb);
                        `CSR_HOST_REG_START_KEY2: start_key_q[95:64] <= merge32(start_key_q[95:64], write_data, write_strb);
                        `CSR_HOST_REG_START_KEY3: start_key_q[127:96] <= merge32(start_key_q[127:96], write_data, write_strb);
                        `CSR_HOST_REG_START_FORMAT: start_fmt_q <= start_format_merged[7:0];
                        `CSR_HOST_REG_START_STORAGE: begin
                            start_storage_mode_q <= start_storage_merged[1:0];
                            start_exponent_q <= start_storage_merged[14:8];
                            start_active_support_q <= start_storage_merged[16];
                        end
                        `CSR_HOST_REG_START_LIMIT: start_limit_q <= merge32(start_limit_q, write_data, write_strb);
                        `CSR_HOST_REG_LOAD_PROGRAM_COUNT: load_program_count_q <= load_program_count_merged[10:0];
                        `CSR_HOST_REG_LOAD_CONSTANT_COUNT: load_constant_count_q <= load_constant_count_merged[10:0];
                        `CSR_HOST_REG_LOAD_CONTROL: begin
                            load_revision_q <= load_control_merged[7:0];
                            load_template_count_q <= load_control_merged[12:8];
                            load_vector_count_q <= load_control_merged[18:13];
                            load_verified_q <= load_control_merged[19];
                        end
                        `CSR_HOST_REG_LOAD_ITEM_CONTROL: begin
                            load_kind_q <= load_item_control_merged[2:0];
                            load_index_q <= load_item_control_merged[18:3];
                            load_last_q <= load_item_control_merged[19];
                        end
                        `CSR_HOST_REG_LOAD_ITEM0: load_data_q[31:0] <= merge32(load_data_q[31:0], write_data, write_strb);
                        `CSR_HOST_REG_LOAD_ITEM1: load_data_q[63:32] <= merge32(load_data_q[63:32], write_data, write_strb);
                        `CSR_HOST_REG_LOAD_ITEM2: load_data_q[95:64] <= merge32(load_data_q[95:64], write_data, write_strb);
                        `CSR_HOST_REG_LOAD_ITEM3: load_data_q[127:96] <= merge32(load_data_q[127:96], write_data, write_strb);
                        `CSR_HOST_REG_PHI_SEED: phi_seed_q <= merge32(phi_seed_q, write_data, write_strb);
                        `CSR_HOST_REG_PHI_SHAPE: begin
                            phi_rows_q <= phi_shape_merged[7:0];
                            phi_cols_q <= phi_shape_merged[26:16];
                        end
                        `CSR_HOST_REG_PHI_KEY0: phi_key_q[31:0] <= merge32(phi_key_q[31:0], write_data, write_strb);
                        `CSR_HOST_REG_PHI_KEY1: phi_key_q[63:32] <= merge32(phi_key_q[63:32], write_data, write_strb);
                        `CSR_HOST_REG_PHI_KEY2: phi_key_q[95:64] <= merge32(phi_key_q[95:64], write_data, write_strb);
                        `CSR_HOST_REG_PHI_KEY3: phi_key_q[127:96] <= merge32(phi_key_q[127:96], write_data, write_strb);
                        `CSR_HOST_REG_PHI_GENERATION: phi_generation_q <= merge32(phi_generation_q, write_data, write_strb);
                        `CSR_HOST_REG_PHI_JOB_TAG: begin
                            phi_job_q <= phi_job_tag_merged[15:0];
                            phi_tag_q <= phi_job_tag_merged[31:16];
                        end
                        `CSR_HOST_REG_PHI_FORMAT: phi_fmt_q <= phi_format_merged[7:0];
                        `CSR_HOST_REG_HOST_CONTROL: begin
                            host_block_q <= host_control_merged[8:0];
                            host_write_q <= host_control_merged[16];
                        end
                        `CSR_HOST_REG_HOST_MASK: host_mask_q <= merge32(host_mask_q, write_data, write_strb);
                        `CSR_HOST_REG_HOST_TAG: host_tag_q <= host_tag_merged[15:0];
                        `CSR_HOST_REG_RESULT_CONTROL: begin
                            result_index_q <= result_control_merged[9:0];
                            result_tag_q <= result_control_merged[31:16];
                        end
                        default: begin
                            if (write_addr >= `CSR_HOST_REG_HOST_DATA0 && write_addr <= `CSR_HOST_REG_HOST_DATA_LAST)
                                host_lane_q[(write_addr - `CSR_HOST_REG_HOST_DATA0) >> 2] <= merge32(
                                    host_lane_q[(write_addr - `CSR_HOST_REG_HOST_DATA0) >> 2], write_data, write_strb);
                        end
                    endcase
                end
                if (irq_write && write_resp_calc == AXI_OKAY)
                    irq_enable_q <= irq_merged[0];
                if (core_cancel_accept) begin
                    cancel_pulse <= 1'b1;
                    cancel_seen_q <= 1'b1;
                end
            end
            if (ar_fire) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata <= read_data_calc;
                s_axi_rresp <= read_resp_calc;
            end

            if (native_load_status_fire)
                image_loading_q <= 1'b0;
            else if (core_cancel_accept)
                image_loading_q <= 1'b0;
            else if (native_load_begin_fire)
                image_loading_q <= 1'b1;

            if (core_cancel_accept) begin
                phi_pending_q <= 1'b0;
                phi_seen_loading_q <= 1'b0;
                phi_valid_q <= 1'b0;
                phi_fault_q <= 4'b0;
            end else if (native_phi_fire) begin
                phi_epoch_q <= phi_epoch_q + 1'b1;
                phi_pending_q <= 1'b1;
                phi_seen_loading_q <= 1'b0;
                phi_valid_q <= 1'b0;
                phi_fault_q <= 4'b0;
                phi_snapshot_job_q <= bridge_p_begin_job;
                phi_snapshot_fmt_q <= bridge_p_begin_fmt;
                phi_snapshot_generation_q <= bridge_p_begin_generation;
                phi_snapshot_seed_q <= bridge_p_begin_seed;
            end else begin
                if (phi_pending_q && native_p_loading)
                    phi_seen_loading_q <= 1'b1;
                if (phi_fill_complete) begin
                    phi_pending_q <= 1'b0;
                    phi_seen_loading_q <= 1'b0;
                    phi_valid_q <= phi_fill_success;
                    phi_fault_q <= native_p_fault;
                end
            end

            if (write_error_event || read_error_event) begin
                error_valid_q <= 1'b1;
                error_code_q <= write_error_event ? write_error_calc :
                    (s_axi_araddr[1:0] != 2'b0 ? `CSR_HOST_ERROR_BAD_ALIGNMENT : `CSR_HOST_ERROR_BAD_ADDRESS);
                error_detail_q <= 4'b0;
                error_offset_q <= write_error_event ? write_addr : s_axi_araddr;
            end

            if (new_native_event || core_cancel_accept || new_error_event) begin
                irq_pending_q <= 1'b1;
                event_sequence_q <= event_sequence_q + 1'b1;
                if (native_done_fire) begin
                    last_event_q <= `CSR_HOST_EVENT_DONE;
                    last_event_command_q <= `CSR_HOST_OP_START;
                end else if (native_read_rsp_fire) begin
                    last_event_q <= `CSR_HOST_EVENT_RESULT_RESPONSE;
                    last_event_command_q <= `CSR_HOST_OP_RESULT_READ;
                end else if (native_host_rsp_fire) begin
                    last_event_q <= `CSR_HOST_EVENT_HOST_RESPONSE;
                    last_event_command_q <= bridge_active_command;
                end else if (native_load_status_fire) begin
                    last_event_q <= `CSR_HOST_EVENT_LOAD_STATUS;
                    last_event_command_q <= `CSR_HOST_OP_LOAD_BEGIN;
                end else if (native_phi_fire) begin
                    last_event_q <= `CSR_HOST_EVENT_PHI_BEGIN;
                    last_event_command_q <= `CSR_HOST_OP_PHI_BEGIN;
                end else if (phi_fill_complete) begin
                    last_event_q <= `CSR_HOST_EVENT_PHI_BEGIN;
                    last_event_command_q <= `CSR_HOST_OP_PHI_BEGIN;
                end else if (core_cancel_accept) begin
                    last_event_q <= `CSR_HOST_EVENT_CANCEL;
                    last_event_command_q <= 4'hf;
                end else begin
                    last_event_q <= `CSR_HOST_EVENT_NONE;
                    last_event_command_q <= 4'hf;
                end
            end else if (bridge_cmd_accept) begin
                event_sequence_q <= event_sequence_q + 1'b1;
                case (command_opcode)
                    `CSR_HOST_OP_START: last_event_q <= `CSR_HOST_EVENT_START;
                    `CSR_HOST_OP_LOAD_BEGIN: last_event_q <= `CSR_HOST_EVENT_LOAD_BEGIN;
                    `CSR_HOST_OP_LOAD_ITEM: last_event_q <= `CSR_HOST_EVENT_LOAD_ITEM;
                    `CSR_HOST_OP_PHI_BEGIN: last_event_q <= `CSR_HOST_EVENT_PHI_BEGIN;
                    `CSR_HOST_OP_HOST_READ: last_event_q <= `CSR_HOST_EVENT_HOST_READ;
                    `CSR_HOST_OP_HOST_WRITE: last_event_q <= `CSR_HOST_EVENT_HOST_WRITE;
                    `CSR_HOST_OP_RESULT_READ: last_event_q <= `CSR_HOST_EVENT_RESULT_READ;
                    default: last_event_q <= `CSR_HOST_EVENT_NONE;
                endcase
                last_event_command_q <= command_opcode;
            end
            if (new_native_event || core_cancel_accept || new_error_event)
                irq_pending_q <= 1'b1;
        end
    end

    assign irq = !core_rst && ((irq_enable_q && irq_pending_q) || (dma_irq_enable_q && dma_done));

endmodule
