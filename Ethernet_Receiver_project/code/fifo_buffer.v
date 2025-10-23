/*
 fifo_buffer.v
 Simple synchronous single-clock FIFO, parameterized depth and width.
*/
module fifo_buffer #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8  // depth = 2^ADDR_WIDTH
)(
    input clk,
    input rst,
    input wr_en,
    input rd_en,
    input [DATA_WIDTH-1:0] data_in,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg full,
    output reg empty
);

    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] used; // count elements

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            used <= 0;
            full <= 1'b0;
            empty <= 1'b1;
            data_out <= {DATA_WIDTH{1'b0}};
            for (i=0;i<DEPTH;i=i+1) mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            // write
            if (wr_en && !full) begin
                mem[wr_ptr] <= data_in;
                wr_ptr <= wr_ptr + 1;
                used <= used + 1;
            end
            // read
            if (rd_en && !empty) begin
                data_out <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                used <= used - 1;
            end
            // flags
            full <= (used == DEPTH);
            empty <= (used == 0);
        end
    end
endmodule
