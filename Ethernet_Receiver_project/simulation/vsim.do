# ModelSim do file for Ethernet_Receiver
vlib work
vlog ../code/*.v
vsim -c work.tb_ethernet_receiver -do "run -all; quit"
