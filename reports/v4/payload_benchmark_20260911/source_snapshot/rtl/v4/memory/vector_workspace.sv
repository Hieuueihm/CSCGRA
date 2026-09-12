`include "pe_interface.vh"
// 16 independent S27 vector slots; exactly 32 banks, two read ports, one write port.
module vector_workspace (
    input wire clk, rst, cancel,
    input wire [1:0] rd_valid,
    output wire [1:0] rd_ready,
    input wire [7:0] rd_slot,
    input wire [3:0] rd_block,
    output wire [1:0] rsp_valid,
    input wire [1:0] rsp_ready,
    output wire [1727:0] rsp_data,
    output reg [63:0] rsp_mask,
    output reg [7:0] rsp_fault,
    input wire wr_valid,
    output wire wr_ready,
    input wire [3:0] wr_slot,
    input wire [1:0] wr_block,
    input wire [863:0] wr_data,
    input wire [31:0] wr_mask,
    input wire invalidate,
    input wire [3:0] invalidate_slot,
    input wire publish,
    input wire [3:0] publish_slot,
    input wire [7:0] publish_length,
    output reg [15:0] slot_valid,
    output wire [127:0] slot_lengths
);
    reg [7:0] lengths[0:15];
    reg [1:0] pending;
    wire active=!rst&&!cancel;
    wire [1:0] take=rd_valid & rd_ready;
    assign rd_ready={2{active}} & ~pending;
    assign rsp_valid={2{active}} & pending;
    assign wr_ready=active;
    genvar bank,port,slot;
    generate for(slot=0;slot<16;slot=slot+1) begin : length_pack
        assign slot_lengths[slot*8 +: 8]=lengths[slot];
    end
    for(bank=0;bank<32;bank=bank+1) begin : banks
        reg [26:0] ram[0:63];
        for(port=0;port<2;port=port+1) begin : reads
            reg [26:0] data;
            wire [3:0] selected=rd_slot[port*4 +: 4];
            wire [1:0] block_idx=rd_block[port*2 +: 2];
            assign rsp_data[(port*32+bank)*27 +: 27]=data;
            always @(posedge clk) begin
                if(!active) data<=0;
                else if(take[port]) data<=slot_valid[selected] && int'(block_idx)*32+bank<int'(lengths[selected]) ? ram[{selected,block_idx}] : 27'b0;
            end
        end
        always @(posedge clk) begin
            if(wr_valid&&wr_ready&&wr_mask[bank]) ram[{wr_slot,wr_block}]<=wr_data[bank*27 +: 27];
        end
    end endgenerate
    integer p,l,s;
    always @(posedge clk) begin
        if(!active) begin
            pending<=0; rsp_mask<=0; rsp_fault<=0; slot_valid<=0;
            for(s=0;s<16;s=s+1) lengths[s]<=0;
        end else begin
            pending<=pending & ~rsp_ready;
            for(p=0;p<2;p=p+1) if(take[p]) begin
                pending[p]<=1'b1;
                rsp_fault[p*4 +: 4]<=slot_valid[rd_slot[p*4 +: 4]] ? 4'b0 : 4'd2;
                for(l=0;l<32;l=l+1) rsp_mask[p*32+l]<=slot_valid[rd_slot[p*4 +: 4]] && int'(rd_block[p*2 +: 2])*32+l<int'(lengths[rd_slot[p*4 +: 4]]);
            end
            if(invalidate) slot_valid[invalidate_slot]<=1'b0;
            if(publish) begin slot_valid[publish_slot]<=1'b1; lengths[publish_slot]<=publish_length; end
        end
    end
endmodule
