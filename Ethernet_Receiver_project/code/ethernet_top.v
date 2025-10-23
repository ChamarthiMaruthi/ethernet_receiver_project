/*
 ethernet_top.v
 Top-level module that instantiates frame_detector, data_capture, fifo, crc_stub
*/
module ethernet_top(
    input clk,
    input rst,
    input [7:0] rx_byte,
    input rx_byte_valid,
    output fifo_full,
    output fifo_empty,
    output [7:0] fifo_data_out,
    input fifo_rd_en,
    output crc_ok_led,
	 output frame_complete
);
    wire frame_valid;       // Pulsed by frame_detector when SFD is seen
    wire capturing_from_fd; // Original capturing signal from frame_detector
    reg  capturing;         // Delayed capturing signal for data_capture
    wire fifo_wr_en;
    wire [7:0] fifo_wr_data;
    //wire frame_complete;  // Pulsed by data_capture when frame (payload+CRC) is fully received
    wire [31:0] last_four;
	 
	 reg [7:0] rx_byte_s;       // Synchronized rx_byte for internal use
    reg rx_byte_valid_s;      // Synchronized rx_byte_valid for internal use


    // Pipeline rx_byte and rx_byte_valid one clock cycle from input.
    // This ensures sub-modules (frame_detector, data_capture) see stable inputs.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_byte_s <= 8'h00;
            rx_byte_valid_s <= 1'b0;
        end else begin
            rx_byte_s <= rx_byte;
            rx_byte_valid_s <= rx_byte_valid;
        end
    end

    frame_detector u_frame_detector (
        .clk(clk),
        .rst(rst),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid),
        .frame_end(frame_complete), // Connect frame_complete from data_capture
        .frame_valid(frame_valid),
        .capturing(capturing_from_fd) // Connect to original output
    );

    // Delay 'capturing_from_fd' by one clock cycle to get 'capturing'.
    // This ensures 'capturing' goes high *after* the SFD, aligned with the first payload byte.
    always @(posedge clk or posedge rst) begin
        if (rst) capturing <= 1'b0;
        else     capturing <= capturing_from_fd;
    end

    data_capture u_data_capture (
        .clk(clk),
        .rst(rst),
        .rx_byte(rx_byte_s),
        .rx_byte_valid(rx_byte_valid_s),
        .capturing(capturing),       // Use the delayed 'capturing'
        .frame_valid(frame_valid), // Pass frame_valid (needed for DC_IDLE reset check)
        .fifo_wr_en(fifo_wr_en),
        .fifo_wr_data(fifo_wr_data),
        .frame_complete(frame_complete),
        .captured_crc_input(last_four)
    );

    fifo_buffer #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) u_fifo (
        .clk(clk),
        .rst(rst),
        .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en),
        .data_in(fifo_wr_data),
        .data_out(fifo_data_out),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    crc_stub u_crc (
        .clk(clk),
        .rst(rst),
        .last_four_bytes(last_four),
		  .FRAME_COMPLETE(frame_complete),
        .crc_ok(crc_ok_led)
    );
endmodule