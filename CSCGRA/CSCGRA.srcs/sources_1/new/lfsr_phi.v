module lfsr_phi #(
    parameter integer LFSR_W = 32,
    parameter integer COLS   = 8,
    parameter integer DATA_W = 24,
    parameter integer Q_FRAC_W = DATA_W - 8,
    parameter [31:0]  TAPS   = 32'h80200003
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire [LFSR_W-1:0]        seed,
    input  wire [DATA_W-1:0]        phi_scale_q8_8,
    input  wire                     gen_en,
    input  wire                     reseed,
    input  wire                     advance_masked_lanes,
    input  wire [COLS-1:0]          lane_valid,
    output reg  [COLS*DATA_W-1:0]   phi_bus,
    output reg                      phi_valid
);

    localparam [LFSR_W-1:0] DEFAULT_SEED = 32'hDEADBEEF;

    reg [LFSR_W-1:0] sreg;

    function [LFSR_W-1:0] galois_step;
        input [LFSR_W-1:0] state;
        reg [LFSR_W-1:0] shifted;
        begin
            shifted = {1'b0, state[LFSR_W-1:1]};
            if (state[0])
                galois_step = shifted ^ TAPS[LFSR_W-1:0];
            else
                galois_step = shifted;
        end
    endfunction

    wire [LFSR_W-1:0] safe_seed = (|seed) ? seed : DEFAULT_SEED;
    wire [DATA_W-1:0] phi_plus  = phi_scale_q8_8;
    wire [DATA_W-1:0] phi_minus = (~phi_scale_q8_8) + 1'b1;

    integer i;
    reg [LFSR_W-1:0] next_state;
    reg [COLS*DATA_W-1:0] next_phi;

    always @(*) begin
        next_state = reseed ? safe_seed : sreg;
        next_phi   = {COLS*DATA_W{1'b0}};
        for (i = 0; i < COLS; i = i + 1) begin
            if (!advance_masked_lanes || lane_valid[i]) begin
                next_phi[i*DATA_W +: DATA_W] = next_state[0] ? phi_plus : phi_minus;
                next_state = galois_step(next_state);
            end else begin
                next_phi[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sreg      <= DEFAULT_SEED;
            phi_bus   <= {COLS*DATA_W{1'b0}};
            phi_valid <= 1'b0;
        end else begin
            if (gen_en) begin
                sreg      <= next_state;
                phi_bus   <= next_phi;
                phi_valid <= 1'b1;
            end else begin
                if (reseed)
                    sreg <= safe_seed;
                phi_valid <= 1'b0;
            end
        end
    end

endmodule

module lfsr #(
    parameter                  LFSR_W       = 32,
    parameter                  COLS         = 8,
    parameter                  DATA_W       = 24,
    parameter                  Q_FRAC_W     = DATA_W - 8,
    parameter [LFSR_W-1:0]     TAPS         = 32'h80200003,
    parameter [LFSR_W-1:0]     INITIAL_FILL = 32'hDEADBEEF
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire [LFSR_W-1:0]          seed,
    input  wire                       gen_en,
    input  wire                       reseed,
    output wire [COLS*DATA_W-1:0]     phi_out,
    output wire                       phi_valid
);

    lfsr_phi #(
        .LFSR_W(LFSR_W),
        .COLS(COLS),
        .DATA_W(DATA_W),
        .Q_FRAC_W(Q_FRAC_W),
        .TAPS(TAPS)
    ) u_lfsr_phi (
        .clk(clk),
        .rst_n(rst_n),
        .seed((|seed) ? seed : INITIAL_FILL),
        .phi_scale_q8_8({{(DATA_W-Q_FRAC_W-1){1'b0}}, 1'b1, {Q_FRAC_W{1'b0}}}),
        .gen_en(gen_en),
        .reseed(reseed),
        .advance_masked_lanes(1'b0),
        .lane_valid({COLS{1'b1}}),
        .phi_bus(phi_out),
        .phi_valid(phi_valid)
    );

endmodule
