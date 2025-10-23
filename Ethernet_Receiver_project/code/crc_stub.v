/*
 crc_stub.v
 Minimal CRC checker stub: compares received last-4-bytes against a known mock CRC value.
*/
module crc_stub(
    input clk,
    input rst,
    input [31:0] last_four_bytes,
	 input FRAME_COMPLETE,
    output reg crc_ok
);
    // For a stub we expect last_four_bytes == 32'hA5A5A5A5 as 'good' CRC
    localparam EXPECTED_CRC = 32'hA5A5A5A5;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            crc_ok <= 1'b0;
        end else begin
			if(FRAME_COMPLETE) begin
            if (last_four_bytes == EXPECTED_CRC) crc_ok <= 1'b1;
            else crc_ok <= 1'b0;
				//$display("time:%t,crc_ok:%b",$time,crc_ok);
			end
        end
    end
endmodule
