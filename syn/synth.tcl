set lib_dir "$env(ROOT_DIR)/libs"
set search_path [list $lib_dir "$env(ROOT_DIR)/rtl" "$env(ROOT_DIR)/rtl/minisoc_spi" "$env(ROOT_DIR)/rtl/minisoc_aes"]
set target_library "saed32rvt_tt1p05v25c.db"
set link_library "* $target_library"

# Read synthesizable RTL in dependency order (packages -> interfaces -> modules)
# Note: minisoc_mem (SRAM macro model) and minisoc_pll (PLL mock) are kept separate as macros/blackboxes.
set pkg_files   [concat [glob -nocomplain "$env(ROOT_DIR)/rtl/*_pkg.sv"] [glob -nocomplain "$env(ROOT_DIR)/rtl/minisoc_spi/*_pkg.sv"] [glob -nocomplain "$env(ROOT_DIR)/rtl/minisoc_aes/*_pkg.sv"]]
set if_files    [concat [glob -nocomplain "$env(ROOT_DIR)/rtl/*_if.sv"]  [glob -nocomplain "$env(ROOT_DIR)/rtl/minisoc_spi/*_if.sv"]  [glob -nocomplain "$env(ROOT_DIR)/rtl/minisoc_aes/*_if.sv"]]
set all_files   [concat [glob -nocomplain "$env(ROOT_DIR)/rtl/*.sv"]     [glob -nocomplain "$env(ROOT_DIR)/rtl/minisoc_spi/*.sv"]     [glob -nocomplain "$env(ROOT_DIR)/rtl/minisoc_aes/*.sv"]]
set other_files [list]
foreach f $all_files {
    if {[lsearch -exact $pkg_files $f] < 0 && [lsearch -exact $if_files $f] < 0} {
        lappend other_files $f
    }
}
if {[llength $pkg_files] > 0}   { analyze -format sverilog $pkg_files }
if {[llength $if_files]  > 0}   { analyze -format sverilog $if_files }
if {[llength $other_files] > 0} { analyze -format sverilog $other_files }

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
