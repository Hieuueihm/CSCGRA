module switchbox #(
    parameter integer DATA_W = 24,
    parameter integer IDX_W  = 10
)(
    input  wire [DATA_W-1:0] inN,
    input  wire [DATA_W-1:0] inS,
    input  wire [DATA_W-1:0] inE,
    input  wire [DATA_W-1:0] inW,
    input  wire [DATA_W-1:0] inPE,
    input  wire [IDX_W-1:0]  inN_idx,
    input  wire [IDX_W-1:0]  inS_idx,
    input  wire [IDX_W-1:0]  inE_idx,
    input  wire [IDX_W-1:0]  inW_idx,
    input  wire [IDX_W-1:0]  inPE_idx,
    input  wire [2:0]        sel,
    output reg  [DATA_W-1:0] outN,
    output reg  [DATA_W-1:0] outS,
    output reg  [DATA_W-1:0] outE,
    output reg  [DATA_W-1:0] outW,
    output reg  [DATA_W-1:0] outPE,
    output reg  [IDX_W-1:0]  outN_idx,
    output reg  [IDX_W-1:0]  outS_idx,
    output reg  [IDX_W-1:0]  outE_idx,
    output reg  [IDX_W-1:0]  outW_idx,
    output reg  [IDX_W-1:0]  outPE_idx
);
    always @(*) begin
        outN  = {DATA_W{1'b0}};
        outS  = {DATA_W{1'b0}};
        outE  = {DATA_W{1'b0}};
        outW  = {DATA_W{1'b0}};
        outPE = {DATA_W{1'b0}};
        outN_idx  = {IDX_W{1'b0}};
        outS_idx  = {IDX_W{1'b0}};
        outE_idx  = {IDX_W{1'b0}};
        outW_idx  = {IDX_W{1'b0}};
        outPE_idx = {IDX_W{1'b0}};
        case (sel)
            3'd0: begin outS = inN; outS_idx = inN_idx; end
            3'd1: begin outN = inS; outN_idx = inS_idx; end
            3'd2: begin outW = inE; outW_idx = inE_idx; end
            3'd3: begin outE = inW; outE_idx = inW_idx; end
            3'd4: begin
                outN  = inPE; outN_idx  = inPE_idx;
                outS  = inPE; outS_idx  = inPE_idx;
                outE  = inPE; outE_idx  = inPE_idx;
                outW  = inPE; outW_idx  = inPE_idx;
                outPE = inPE; outPE_idx = inPE_idx;
            end
            3'd5: begin
                outN = inS; outN_idx = inS_idx;
                outS = inN; outS_idx = inN_idx;
            end
            3'd6: begin
                outE = inW; outE_idx = inW_idx;
                outW = inE; outW_idx = inE_idx;
            end
            default: begin
                outN = {DATA_W{1'b0}};
                outS = {DATA_W{1'b0}};
                outE = {DATA_W{1'b0}};
                outW = {DATA_W{1'b0}};
                outPE = {DATA_W{1'b0}};
            end
        endcase
    end
endmodule

