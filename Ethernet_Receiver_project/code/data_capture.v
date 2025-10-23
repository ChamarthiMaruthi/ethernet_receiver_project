/*
 data_capture.v
 Captures bytes when frame_detector asserts capturing.
 Writes *payload* bytes into fifo (write enable).
 Also captures last 4 bytes to pass to crc_stub.
*/

module data_capture #(
    parameter DATA_WIDTH = 8,
    parameter PAYLOAD_LEN = 64  // Total number of payload bytes (matching testbench's PAYLOAD_SIZE)
)(
    input clk,
    input rst,
    input [DATA_WIDTH-1:0] rx_byte,
    input rx_byte_valid,
    input capturing,                 // from ethernet_top (DELAYED by 1 cycle relative to frame_detector's output)
    input frame_valid,               // Still needed for debugging, but not for FSM transitions
    output reg fifo_wr_en,
    output reg [DATA_WIDTH-1:0] fifo_wr_data,
    output reg frame_complete,       // one-cycle strobe when frame ended (for CRC check, and frame_detector)
    output reg [31:0] captured_crc_input // last 4 bytes captured (simple concatenation)
);

    //---------------------------------------
    // Internal Registers and Parameters
    //---------------------------------------
    reg [15:0] total_frame_byte_count = 0;   // Counts all bytes AFTER SFD (payload + CRC)
    reg [15:0] count=0;
    reg [31:0] last_four = 0;
    reg dc_state;                            // FSM current state (only two states)
    integer dut_valid_count = 0;

    // FSM States
    parameter DC_IDLE      = 1'b0;  // Waits for delayed 'capturing' signal to go high
    parameter DC_CAPTURING = 1'b1;  // Capturing payload and CRC bytes

    // Total frame bytes expected = payload + 4 CRC bytes
    localparam TOTAL_FRAME_BYTES_EXPECTED = PAYLOAD_LEN + 4;

    //---------------------------------------
    // Main Sequential Block
    //---------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all internal registers
            dc_state <= DC_IDLE;
            fifo_wr_en <= 1'b0;
            fifo_wr_data <= {DATA_WIDTH{1'b0}};
            total_frame_byte_count <= 16'd0;
            frame_complete <= 1'b0;
            last_four <= 32'd0;
        end 
        else begin
            // Default values every cycle
            fifo_wr_en <= 1'b0;
            frame_complete <= 1'b0;

            //---------------------------------------
            // Capture bytes when valid and capturing
            //---------------------------------------
            if (capturing && rx_byte_valid) begin
					 //total_frame_byte_count <= total_frame_byte_count + 1;
                $monitor("Time:%t, Entered DC_capturing.rx_byte:%h, count:%d",
                          $time, rx_byte, total_frame_byte_count);
                //total_frame_byte_count <= total_frame_byte_count + 1;
                // Write payload bytes to FIFO
                if (total_frame_byte_count < PAYLOAD_LEN) begin
                    fifo_wr_en <= 1'b1;
                    fifo_wr_data <= rx_byte;
                    $strobe("Time:%t,total_frame_byte_count:%d,fifo_wr_data:%h,rx_byte:%h. The count is matching.",
                            $time, total_frame_byte_count, fifo_wr_data, rx_byte);
                end

                // Capture last four bytes (for CRC)
                if (total_frame_byte_count == PAYLOAD_LEN || total_frame_byte_count > PAYLOAD_LEN) begin
                    $display("Time:%t, Entered the 2nd if block", $time);
                    last_four <= {last_four[23:0], rx_byte};
                    captured_crc_input <= last_four;
                    $strobe("Time:%t,captured_crc_input:%h,total_frame_byte_count:%d,total_frame_bytes_expected:%d. The count is matching.",
                            $time, captured_crc_input, total_frame_byte_count, TOTAL_FRAME_BYTES_EXPECTED - 1);
                end
					 
					 total_frame_byte_count <= total_frame_byte_count + 1;
					 
                if (total_frame_byte_count == TOTAL_FRAME_BYTES_EXPECTED-1) begin
                    frame_complete <= 1'b1;
                    $display("time:%t,Enterd the last if block. frame_complete:%b,captured_crc_input:%h",
                             $time, frame_complete, captured_crc_input);
                end
                else begin
                    $display("Time:%t, Didn't complete the count.", $time);
                end
            end
        end
    end
	 
	 always @(posedge clk) begin
		  if (rx_byte_valid) begin
			count <= count + 1;
			$display("Time:%t,count:%d",$time,count);
		  end
	 end
	 
    //---------------------------------------
    // Debug Print for CRC Capture
    //---------------------------------------
    always @(posedge clk) begin
        if (frame_complete == 1'b1) begin
            $display("time:%t,captured_crc_input:%h", $time, captured_crc_input);
        end
    end

endmodule
