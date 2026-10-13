set lib_dir "$env(ROOT_DIR)/libs"
read_db "$lib_dir/saed32rvt_tt1p05v25c.db"

# Reference: Original RTL
read_sverilog -r "$env(ROOT_DIR)/rtl/top.sv"
set_top r:/WORK/top

# Implementation: Synthesized Netlist
read_verilog -i "$env(ROOT_DIR)/build/syn/top_syn.v"
set_top i:/WORK/top

# Match and verify
match
verify

report_failing_points
exit

