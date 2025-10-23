/*
 frame_detector.v
 Detect 7 bytes of 0x55 followed by SFD 0xD5
 Interface: serial byte in (8-bit parallel bytes presented with valid strobe)
*/
module frame_detector #(
    parameter DATA_WIDTH = 8
)(
    input clk,
    input rst,
    input [DATA_WIDTH-1:0] rx_byte,
    input rx_byte_valid,
    input frame_end,      // NEW: Signal from data_capture to indicate frame end
    output reg frame_valid,      // asserted for one cycle when frame detected (SFD seen)
    output reg capturing         // high while payload reception expected
);

    // states
    parameter IDLE = 3'd0;
    parameter PREAMBLE = 3'd1;
    parameter SFD = 3'd2;
    parameter CAPTURE = 3'd3;
    parameter DONE = 3'd4;

    reg [2:0] state;
    reg [2:0] preamble_count;

    always @(posedge clk or posedge rst) begin
	 //$display("Time:%t, In the frame_detecter block",$time);
        if (rst) begin
				//$display("Time:%t, Entered rst in frame_detector",$time);
            state <= IDLE;
            preamble_count <= 3'd0;
            frame_valid <= 1'b0;
            capturing <= 1'b0;
        end else begin
            frame_valid <= 1'b0; // default for pulse output
            case (state)
                IDLE: begin
						  //$display("Time:%t, Entered IDLE in frame_detector",$time);
                    capturing <= 1'b0; // Ensure capturing is low in IDLE
                    preamble_count <= 3'd0;
                    if (rx_byte_valid && rx_byte == 8'h55) begin
                        preamble_count <= 3'd1;
                        state <= PREAMBLE;
                    end
                end
                PREAMBLE: begin
						  //$display("Time:%t, Entered PREAMBLE in frame_detector",$time);
                    if (rx_byte_valid) begin
                        if (rx_byte == 8'h55) begin
                            if (preamble_count == 3'd6) begin // Seen 7x 0x55
                                state <= SFD;
                            end else begin
                                preamble_count <= preamble_count + 3'd1;
                                // Stay in PREAMBLE
                            end
                        end else begin
                            // False alarm, restart search. If current byte is 0x55, it could be a new preamble start.
                            if (rx_byte == 8'h55) begin
                                preamble_count <= 3'd1;
                                state <= PREAMBLE;
                            end else begin
                                preamble_count <= 3'd0;
                                state <= IDLE;
                            end
                        end
                    end
                end
                SFD: begin
						  //$display("Time:%t, Entered SFD in frame_detector",$time);
                    if (rx_byte_valid) begin
                        if (rx_byte == 8'hD5) begin
                            // Start of frame detected
                            frame_valid <= 1'b1; // Pulse for one cycle
                            capturing <= 1'b1;   // Assert capturing for subsequent payload (this signal will be delayed in top)
                            state <= CAPTURE;
                        end else begin
                            // not SFD, restart search
                            preamble_count <= 3'd0;
                            state <= IDLE;
                        end
                    end
                end
                CAPTURE: begin
						  //$display("Time:%t, Entered CAPTURE in frame_detector",$time);
                    capturing <= 1'b1; // Keep high during capture phase
                    if (frame_end) begin // Transition to DONE when data_capture signals frame_end
								$display("Frame_detector,Time:%t,frame_end:%b. Entering DONE state.",$time,frame_end);
                        state <= DONE;
                    end
                end
                DONE: begin
						  //$display("Time:%t, Entered DONE in frame_detector",$time);
                    capturing <= 1'b0; // De-assert capturing
                    state <= IDLE;     // Return to IDLE
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule