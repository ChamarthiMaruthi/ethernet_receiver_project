`timescale 1ns/1ps

// tb_ethernet_bitwise.v
// Old-style Verilog testbench:
// - reads bytes (hex per line) from test/data.txt
// - serializes bits (MSB-first) and reconstructs bytes internally
// - presents rx_byte + rx_byte_valid to ethernet_top (DUT)
// - verifies FIFO contents against expected payload (skips preamble/sfd/CRC)
// - uses old-Style Verilog (no SystemVerilog features)

module tb;

    // Clock / reset
    reg clk;
    reg rst;

    // DUT interface (match your ethernet_top)
    reg [7:0] tb_rx_byte;
    reg tb_rx_byte_valid;

    wire fifo_full;
    wire fifo_empty;
    wire [7:0] fifo_data_out;
    reg fifo_rd_en;

    wire crc_ok_led;
    wire frame_complete;

    // Instantiate DUT
    ethernet_top dut (
        .clk(clk),
        .rst(rst),
        .rx_byte(tb_rx_byte),
        .rx_byte_valid(tb_rx_byte_valid),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .fifo_data_out(fifo_data_out),
        .fifo_rd_en(fifo_rd_en),
        .crc_ok_led(crc_ok_led),
        .frame_complete(frame_complete)
    );

    // Clock: 100 MHz (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset sequence
    initial begin
        rst = 1;
        tb_rx_byte = 8'h00;
        tb_rx_byte_valid = 1'b0;
        fifo_rd_en = 1'b0;
        #100;
        rst = 0;
    end

    // -------------------------------------------------------------------------
    // File reading: read bytes (hex) from data file into a memory
    // file format: one hex byte per line, e.g.:
    // 55
    // 55
    // 55
    // D5
    // 00
    // ...
    // A5
    // -------------------------------------------------------------------------
    integer fd;
    integer status;
    integer frame_bytes;
    integer i;
    reg [7:0] frame_mem [0:2047]; // up to 2048 bytes
    initial begin
        frame_bytes = 0;
        // update path if you run vsim from different folder:
        fd = $fopen("data.txt", "r"); // assuming run from simulation/
        if (fd == 0) begin
            $display("ERROR: cannot open ..data.txt - check working directory or path");
            $finish;
        end
        // Read hex bytes until EOF
        while (!$feof(fd)) begin
            status = $fscanf(fd, "%h\n", frame_mem[frame_bytes]);
            if (status == 1) begin
                frame_bytes = frame_bytes + 1;
                if (frame_bytes >= 2048) begin
                    $display("ERROR: frame too large (>2048)");
                    $fclose(fd);
                    $finish;
                end
            end else begin
                // try to consume residual line
                // read as string (fgets) and ignore
                // but keep it simple
            end
        end
        $fclose(fd);
        $display("TB: Loaded %0d bytes from data.txt", frame_bytes);
    end

    // -------------------------------------------------------------------------
    // Prepare expected payload array by skipping preamble and SFD and last 4 CRC bytes
    // We'll assume preamble = 7 x 0x55, SFD = 0xD5, CRC = last 4 bytes.
    // If the file uses different framing, update these offsets accordingly.
    // -------------------------------------------------------------------------
    integer payload_start;
    integer payload_len;
    reg [7:0] expected_payload [0:1535]; // large enough
    initial begin
        // wait until frame_mem loaded
        wait(frame_bytes > 0);
        // find preamble + SFD sequence (robust search)
        payload_start = -1;
        for (i = 0; i <= frame_bytes - 8; i = i + 1) begin
            if (frame_mem[i] == 8'h55 &&
                frame_mem[i+1] == 8'h55 &&
                frame_mem[i+2] == 8'h55 &&
                frame_mem[i+3] == 8'h55 &&
                frame_mem[i+4] == 8'h55 &&
                frame_mem[i+5] == 8'h55 &&
                frame_mem[i+6] == 8'h55 &&
                frame_mem[i+7] == 8'hD5 ) begin
                payload_start = i + 8; // first payload byte index
                //disable for; // break out early (Verilog-2001: disable label, here just trick)
            end
        end
        if (payload_start < 0) begin
            $display("WARNING: Did not find 7x55 + D5 preamble in data.txt; assuming payload starts at index 8");
            payload_start = 8;
        end

        // payload length = total bytes - payload_start - 4 (CRC)
        if (frame_bytes - payload_start - 4 < 0) begin
            payload_len = 0;
        end else begin
            payload_len = frame_bytes - payload_start - 4;
        end

        for (i = 0; i < payload_len; i = i + 1) begin
            expected_payload[i] = frame_mem[payload_start + i];
        end
        $display("TB: Payload_start=%0d payload_len=%0d", payload_start, payload_len);
    end

    // -------------------------------------------------------------------------
    // Serial-bit generator: take each byte from frame_mem and send it bit-by-bit.
    // We'll send bits MSB-first. After 8 bits collected, the testbench packs them
    // into a byte and asserts rx_byte_valid for one clock cycle.
    // -------------------------------------------------------------------------
    reg [7:0] bit_shift_reg;
    integer byte_idx;
    integer bit_idx;
    integer sent_bytes;
    reg [7:0] this_byte;
    reg this_bit;
    initial begin
        // wait until reset deasserted and file loaded
        wait(rst == 0);
        wait(frame_bytes > 0);

        // small delay to let DUT settle
        //#100;

        tb_rx_byte = 8'h00;
        tb_rx_byte_valid = 1'b0;
        bit_shift_reg = 8'h00;
        sent_bytes = 0;

        for (byte_idx = 0; byte_idx < frame_bytes; byte_idx = byte_idx + 1) begin
            this_byte = frame_mem[byte_idx];
            if (byte_idx == 8) @(posedge clk);
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                this_bit = (this_byte >> bit_idx) & 1'b1;
                bit_shift_reg = {bit_shift_reg[6:0], this_bit};
                @(posedge clk);
            end
            tb_rx_byte_valid = 1'b1;
            tb_rx_byte = bit_shift_reg;
            $display("TB:time:%t,tb_rx_byte:%b,tb_rx_byte_valid:%b",$time,tb_rx_byte,tb_rx_byte_valid);
            @(posedge clk); // hold for one epoch
            tb_rx_byte_valid = 1'b0;
            tb_rx_byte = 8'h00;
            sent_bytes = sent_bytes + 1;
        end
        $display("Time:%t. TB: Sent %0d bytes (bitwise) to DUT",$time, sent_bytes);
    end

    // -------------------------------------------------------------------------
    // Verification: after sending frame, read FIFO and compare with expected payload
    // -------------------------------------------------------------------------
    integer read_index;
    integer fifo_errors;
    reg [31:0] wait_cycles;
    initial begin
        fifo_errors = 0;
    	// Wait for at least one frame to complete (this ensures CRC bytes also arrived)
    	$display("TB: Waiting for DUT to finish capturing entire frame...");
    	@(posedge frame_complete);
    	$display("TB: Frame complete detected at time %t.", $time);
    	wait(!fifo_empty);
    	read_index = 0;
        while (!fifo_empty) begin
            // assert read enable for one cycle to get data_out
            fifo_rd_en = 1'b1;
            @(posedge clk);
            fifo_rd_en = 1'b0;
            // data should appear on fifo_data_out
            // compare with expected
            if (read_index < 0 || read_index >= 1536) begin
                $display("WARNING: read_index out of range %0d", read_index);
            end else begin
                if (fifo_data_out !== expected_payload[read_index]) begin
                    $display("Time:%t,ERROR: FIFO mismatch at index %0d : expected %02h, got %02h",$time, read_index, expected_payload[read_index], fifo_data_out);
                    fifo_errors = fifo_errors + 1;
                end
            end
            read_index = read_index + 1;
            // small delay between reads
            repeat (2) @(posedge clk);
        end

        $display("Time:%t. TB: FIFO read complete. bytes read = %0d, errors = %0d",$time, read_index, fifo_errors);

        // Check CRC LED (since we use a stub that expects 0xA5A5A5A5, signal should be set)
        if (crc_ok_led !== 1'b1) begin
            $display("ERROR: CRC check failed: crc_ok_led = %b (expected 1)", crc_ok_led);
        end else begin
            $display("TB: CRC OK LED = %b", crc_ok_led);
        end

        if (fifo_errors == 0 && crc_ok_led == 1'b1) begin
            $display("TB: TEST PASSED");
        end else begin
            $display("TB: TEST FAILED (fifo_errors=%0d, crc_ok=%b)", fifo_errors, crc_ok_led);
        end

        $finish;
    end
    
    /*integer tb_valid_count = 0;
always @(posedge clk) begin
  if (tb_rx_byte_valid) begin
    tb_valid_count = tb_valid_count + 1;
    $display("TB_VALID #%0d at %t -> byte=%02h (idx=%0d)", tb_valid_count, $time, tb_rx_byte, byte_idx);
  end
end*/


endmodule

