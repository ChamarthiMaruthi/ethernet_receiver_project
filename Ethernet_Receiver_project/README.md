# Ethernet Receiver on FPGA (Simulation-first)

## Overview
Minimal Ethernet Frame Receiver implemented in Verilog. Designed to detect Ethernet preamble (7 bytes of 0x55) + SFD (0xD5), capture a payload, perform a CRC stub check, and write payload bytes into a FIFO buffer. Project structure and coding conventions mirror the UART_buffer project layout.

## Project layout
```
Ethernet_Receiver/
├── code/           # Verilog sources
├── test/           # Testbenches
├── simulation/     # ModelSim do-files and logs
├── reports/        # Placeholder for Quartus reports
├── results/        # Waveforms / outputs
└── README.md
```

## Tools
- Verilog (IEEE 1364) — plain Verilog (no SystemVerilog)
- ModelSim (for simulation)
- Intel Quartus Prime (project files provided as placeholders)

## Modules
- frame_detector.v: detect preamble and SFD
- data_capture.v: capture payload bytes and drive FIFO write
- fifo_buffer.v: simple synchronous single-clock FIFO
- crc_stub.v: compare final 4 bytes against a mock CRC value
- ethernet_top.v: top-level integration

## Testbench
`tb_ethernet_receiver.v` is a behavioral testbench that feeds preambles and frames.

## Author
Maruthi Chamarthi (NIT Durgapur)
