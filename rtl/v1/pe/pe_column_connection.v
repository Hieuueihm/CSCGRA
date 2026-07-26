module pe_column_connection #(
    parameter integer DATA_W = 24,
    parameter integer IDX_W  = 10
)(
    input  wire [DATA_W-1:0] west_to_east_data_i,
    input  wire [IDX_W-1:0]  west_to_east_idx_i,
    input  wire [DATA_W-1:0] east_to_west_data_i,
    input  wire [IDX_W-1:0]  east_to_west_idx_i,
    output wire [DATA_W-1:0] west_to_east_data_o,
    output wire [IDX_W-1:0]  west_to_east_idx_o,
    output wire [DATA_W-1:0] east_to_west_data_o,
    output wire [IDX_W-1:0]  east_to_west_idx_o
);
    assign west_to_east_data_o = west_to_east_data_i;
    assign west_to_east_idx_o  = west_to_east_idx_i;
    assign east_to_west_data_o = east_to_west_data_i;
    assign east_to_west_idx_o  = east_to_west_idx_i;
endmodule
