# Ethernet Receiver Project

## Project Overview
This project implements a simple Ethernet frame receiver in Verilog that:
- Detects Ethernet frames (preamble + SFD)
- Captures payload data (64 bytes)
- Stores payload in a FIFO buffer
- Validates CRC checksum (stub implementation)

## Project Structure

```
Ethernet_Receiver_project/
├── code/
│   ├── data_capture.v       # Captures payload and CRC bytes
│   ├── frame_detector.v     # Detects preamble and SFD
│   ├── fifo_buffer.v        # FIFO buffer for payload storage
│   ├── crc_stub.v           # CRC validation (stub)
│   └── ethernet_top.v       # Top-level module
├── test/
│   ├── tb.v                 # Testbench
│   └── data.txt             # Test data file
└── README.md
```

## Module Descriptions

### 1. frame_detector.v
- Detects 7 bytes of preamble (0x55)
- Detects Start Frame Delimiter (SFD = 0xD5)
- Asserts `capturing` signal during payload reception
- FSM-based implementation

### 2. data_capture.v
- Captures payload bytes (0-63)
- Writes payload to FIFO
- Captures last 4 CRC bytes
- Signals frame completion

### 3. fifo_buffer.v
- Synchronous FIFO
- Parameterized depth (256 entries default)
- Read/write pointers
- Full/empty flags

### 4. crc_stub.v
- Stub CRC checker
- Expects CRC = 0xA5A5A5A5 for validation
- Can be replaced with real CRC-32 implementation

### 5. ethernet_top.v
- Integrates all modules
- Synchronizes input signals
- Delays capturing signal by 1 cycle for alignment

## Design Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Testbench   │────>│Frame Detector│────>│Data Capture  │
│              │     │  (Preamble/  │     │  (Payload +  │
│              │     │     SFD)     │     │     CRC)     │
└──────────────┘     └──────────────┘     └──────────────┘
                            │                     │
                            │                     v
                            │              ┌──────────────┐
                            │              │ FIFO Buffer  │
                            │              └──────────────┘
                            │                     │
                            v                     v
                     ┌──────────────┐     ┌──────────────┐
                     │  CRC Stub    │<────┤ Verification │
                     └──────────────┘     └──────────────┘
```

## Major Issues Encountered and Solutions

### Issue #1: Off-by-One Error in FIFO Data
**Problem:**
- FIFO was returning data shifted by one byte
- Expected byte 0x01 at index 1, but got 0x00
- All 64 bytes were off by one position

**Root Cause:**
The `data_capture` module was using **non-blocking assignments (`<=`)** for output signals in the sequential always block:

```verilog
// WRONG APPROACH
always @(posedge clk) begin
    if (capturing && rx_byte_valid) begin
        fifo_wr_data <= rx_byte;  // Non-blocking - updates at END of clock cycle
        // $display shows OLD value here!
    end
end
```

**Why it failed:**
- Non-blocking assignments (`<=`) schedule updates that happen at the end of the time step
- When `$display` executed, it showed the OLD value
- FIFO received data one cycle late

**Solution:**
Separated logic into two always blocks following the UART design pattern:

1. **Sequential block** - Updates internal registers/counters only
2. **Combinational block** - Generates outputs immediately with blocking assignments

```verilog
// CORRECT APPROACH
// Sequential block - updates counters
always @(posedge clk or posedge rst) begin
    if (rst) begin
        total_frame_byte_count <= 16'd0;
        last_four <= 32'd0;
    end else if (capturing && rx_byte_valid) begin
        // Only update internal state
        total_frame_byte_count <= total_frame_byte_count + 1;
        if (total_frame_byte_count >= PAYLOAD_LEN) begin
            last_four <= {last_four[23:0], rx_byte};
        end
    end
end

// Combinational block - immediate outputs
always @(*) begin
    fifo_wr_en = 1'b0;
    fifo_wr_data = 8'd0;
    
    if (capturing && rx_byte_valid && total_frame_byte_count < PAYLOAD_LEN) begin
        fifo_wr_en = 1'b1;
        fifo_wr_data = rx_byte;  // Blocking assignment - IMMEDIATE!
    end
end
```

**Key Learning:**
- Use **blocking assignments (`=`)** in combinational blocks for immediate response
- Use **non-blocking assignments (`<=`)** in sequential blocks for registers
- Each signal should be driven from only ONE always block

---

### Issue #2: FIFO Read Timing - Registered Output Latency
**Problem:**
After fixing Issue #1, data_capture was working perfectly, but testbench still showed mismatches:
```
ERROR: FIFO mismatch at index 1 : expected 01, got 00
ERROR: FIFO mismatch at index 2 : expected 02, got 01
```

**Root Cause:**
The FIFO uses registered output with non-blocking assignment:

```verilog
// fifo_buffer.v
always @(posedge clk) begin
    if (rd_en && !empty) begin
        data_out <= mem[rd_ptr];  // Non-blocking - 1 cycle latency!
        rd_ptr <= rd_ptr + 1;
    end
end
```

The testbench was checking data too early:

```verilog
// WRONG TIMING
while (!fifo_empty) begin
    fifo_rd_en = 1'b1;
    @(posedge clk);        // Wait 1 cycle
    fifo_rd_en = 1'b0;
    // Check here - TOO EARLY! Data not ready yet!
    if (fifo_data_out !== expected_payload[read_index]) 
        $display("ERROR...");
end
```

**Timing Analysis:**
```
Clock N:   rd_en=1 → FIFO schedules data_out <= mem[0]
Clock N+1: rd_en=0 → Testbench checks (but data_out still has OLD value!)
Clock N+2: data_out NOW has new value (too late!)
```

**Solution:**
Wait TWO clock cycles - one for FIFO to process, one for data to become visible:

```verilog
// CORRECT TIMING
for (i = 0; i < payload_len; i = i + 1) begin
    fifo_rd_en = 1'b1;
    @(posedge clk);        // Wait 1: FIFO processes read request
    fifo_rd_en = 1'b0;
    @(posedge clk);        // Wait 2: Data becomes visible!
    
    // NOW check - data is ready!
    if (fifo_data_out !== expected_payload[i]) begin
        $display("ERROR: FIFO mismatch at index %0d", i);
    end
end
```

**Key Learning:**
- Registered outputs (using `<=`) have **1-cycle latency**
- Testbenches must account for this delay
- Wait pattern: Assert signal → Wait for processing → Wait for output → Check

---

## Design Patterns Used

### 1. UART-Style FSM Pattern
Inspired by UART_TX and UART_RX modules:
- **Separate sequential and combinational logic**
- Sequential: State transitions, counter updates
- Combinational: Output generation based on current state

### 2. Edge Detection Pattern
```verilog
reg prev_capturing;
always @(posedge clk) begin
    prev_capturing <= capturing;
    
    if (capturing && !prev_capturing) begin
        // Rising edge detected - reset counters
        total_frame_byte_count <= 16'd0;
    end
end
```

### 3. Pipelined Read Pattern
For reading from registered outputs with proper timing.

---

## Test Results

### Final Test Output:
```
TB: Loaded 76 bytes from data.txt
TB: Payload_start=8 payload_len=64
TB: Starting FIFO read with pipelined approach...
Time: 7015000, PASS: FIFO[0] = 00
Time: 7035000, PASS: FIFO[1] = 01
...
Time: 8275000, PASS: FIFO[63] = 3f
========================================
Time: 8275000. TB: FIFO read complete. bytes read = 64, errors = 0
TB: CRC OK LED = 1 ✓
========================================
         ✓✓✓ TEST PASSED ✓✓✓
========================================
```

**Statistics:**
- Frame size: 76 bytes (7 preamble + 1 SFD + 64 payload + 4 CRC)
- Payload bytes: 64 (0x00 to 0x3F)
- CRC: 0xA5A5A5A5 (validated)
- FIFO errors: 0
- Test result: **PASSED**

---

## How to Run

### Simulation (ModelSim/QuestaSim):
```bash
# Compile
vlog Ethernet_Receiver_project/code/*.v
vlog Ethernet_Receiver_project/test/tb.v

# Simulate
vsim -c tb -do "run -all"
```

### Synthesis (Quartus):
1. Create new project
2. Add all files from `code/` directory
3. Set `ethernet_top` as top-level entity
4. Compile design

---

## Key Takeaways

1. **Blocking vs Non-Blocking:**
   - `=` (blocking) in combinational blocks → immediate
   - `<=` (non-blocking) in sequential blocks → delayed by 1 cycle

2. **Separation of Concerns:**
   - Each signal driven from ONE always block only
   - Sequential updates state, Combinational generates outputs

3. **Timing is Critical:**
   - Account for registered output latencies
   - Test with proper clock cycle delays

4. **Debug Strategy:**
   - Use `$display` to trace signals
   - Understand when signals update (blocking vs non-blocking)
   - Check timing diagrams

---

## Future Enhancements

- [ ] Implement real CRC-32 calculation
- [ ] Support variable payload sizes
- [ ] Add error detection (bad CRC, malformed frames)
- [ ] Support different Ethernet frame types
- [ ] Add MAC address filtering
- [ ] Performance optimization

---

## Author
**Chamarthi Maruthi**

## Date
October 24, 2025

## Acknowledgments
Special thanks to GitHub Copilot for debugging assistance and explaining Verilog timing concepts.

---

## License
MIT License - Feel free to use and modify for educational purposes.