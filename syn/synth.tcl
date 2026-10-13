set lib_dir "$env(ROOT_DIR)/libs"
set search_path [list $lib_dir "$env(ROOT_DIR)/rtl"]
set target_library "saed32rvt_tt1p05v25c.db"
set link_library "* $target_library"

# Read the RTL
analyze -format sverilog [glob "$env(ROOT_DIR)/rtl/*.sv"]
elaborate top
current_design top
link

# Compile and synthesize
check_design
compile

# Write outputs
write -format verilog -hierarchy -output "top_syn.v"
write -format ddc -hierarchy -output "top.ddc"
report_area > "$env(ROOT_DIR)/syn/synth_area.rpt"
report_timing > "$env(ROOT_DIR)/syn/synth_timing.rpt"
report_power > "$env(ROOT_DIR)/syn/synth_power.rpt"

quit
