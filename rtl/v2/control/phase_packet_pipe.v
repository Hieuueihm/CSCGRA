// Narrow phase packet carried by the PE0 -> PE1 -> PE2 -> PE3 south link.
//
// The packet deliberately carries control metadata only.  Wide arithmetic
// payloads remain on their existing registered data paths so packetization
// does not create a new fanout or memory-port critical path.
module phase_packet_pipe #(
    parameter integer VERSION_W = 8,
    parameter integer IDX_W = 10,
    parameter integer DATA_W = 24,
    parameter integer STAGES = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   flush,
    input  wire                   in_valid,
    input  wire [3:0]             in_phase,
    input  wire [3:0]             in_mode,
    input  wire [3:0]             in_owner,
    input  wire [7:0]             in_dependency_mask,
    input  wire [VERSION_W-1:0]   in_version,
    input  wire [IDX_W-1:0]       in_idx,
    input  wire [DATA_W-1:0]      in_data,
    output wire                   out_valid,
    output wire [3:0]             out_phase,
    output wire [3:0]             out_mode,
    output wire [3:0]             out_owner,
    output wire [7:0]             out_dependency_mask,
    output wire [VERSION_W-1:0]   out_version,
    output wire [IDX_W-1:0]       out_idx,
    output wire [DATA_W-1:0]      out_data
);
    reg [STAGES-1:0] valid_q;
    reg [3:0] phase_q [0:STAGES-1];
    reg [3:0] mode_q [0:STAGES-1];
    reg [3:0] owner_q [0:STAGES-1];
    reg [7:0] dependency_q [0:STAGES-1];
    reg [VERSION_W-1:0] version_q [0:STAGES-1];
    reg [IDX_W-1:0] idx_q [0:STAGES-1];
    reg [DATA_W-1:0] data_q [0:STAGES-1];
    integer stage_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            valid_q <= {STAGES{1'b0}};
            for (stage_i = 0; stage_i < STAGES; stage_i = stage_i + 1) begin
                phase_q[stage_i] <= 4'd0;
                mode_q[stage_i] <= 4'd0;
                owner_q[stage_i] <= 4'd0;
                dependency_q[stage_i] <= 8'd0;
                version_q[stage_i] <= {VERSION_W{1'b0}};
                idx_q[stage_i] <= {IDX_W{1'b0}};
                data_q[stage_i] <= {DATA_W{1'b0}};
            end
        end else begin
            valid_q[0] <= in_valid;
            phase_q[0] <= in_phase;
            mode_q[0] <= in_mode;
            owner_q[0] <= in_owner;
            dependency_q[0] <= in_dependency_mask;
            version_q[0] <= in_version;
            idx_q[0] <= in_idx;
            data_q[0] <= in_data;
            for (stage_i = 1; stage_i < STAGES; stage_i = stage_i + 1) begin
                valid_q[stage_i] <= valid_q[stage_i-1];
                phase_q[stage_i] <= phase_q[stage_i-1];
                mode_q[stage_i] <= mode_q[stage_i-1];
                owner_q[stage_i] <= owner_q[stage_i-1];
                dependency_q[stage_i] <= dependency_q[stage_i-1];
                version_q[stage_i] <= version_q[stage_i-1];
                idx_q[stage_i] <= idx_q[stage_i-1];
                data_q[stage_i] <= data_q[stage_i-1];
            end
        end
    end

    assign out_valid = valid_q[STAGES-1];
    assign out_phase = phase_q[STAGES-1];
    assign out_mode = mode_q[STAGES-1];
    assign out_owner = owner_q[STAGES-1];
    assign out_dependency_mask = dependency_q[STAGES-1];
    assign out_version = version_q[STAGES-1];
    assign out_idx = idx_q[STAGES-1];
    assign out_data = data_q[STAGES-1];
endmodule
