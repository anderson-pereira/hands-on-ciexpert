# upf_check.tcl - Script Fusion Compiler (fc_shell) para validacao e relatorios UPF
# Baseado no fluxo de referencia lab4_reporting (bibliotecas centralizadas no Makefile)

set DESIGN_NAME    "top"
set DESIGN_LIBRARY "${DESIGN_NAME}.dlib"

set lib_dir "$env(ROOT_DIR)/libs"
set TECH_FILE [expr {[info exists env(LIB_TF)] ? $env(LIB_TF) : "$lib_dir/saed32nm_1p9m.tf"}]
set REFERENCE_LIBRARY [expr {[info exists env(LIB_NDM)] ? $env(LIB_NDM) : [list \
    "$lib_dir/saed32rvt_base_frame_timing.ndm" \
    "$lib_dir/saed32rvt_pg_frame_timing.ndm" \
    "$lib_dir/saed32rvt_dlvl_frame_timing.ndm" \
    "$lib_dir/saed32rvt_ulvl_frame_timing.ndm" \
]}]

# 1. Criacao da Design Library NDM (SAED 32nm)
file delete -force $DESIGN_LIBRARY
create_lib -technology $TECH_FILE -ref_libs $REFERENCE_LIBRARY $DESIGN_LIBRARY

# 2. Leitura do RTL sintetizavel em ordem de dependencia (packages -> interfaces -> modulos)
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

elaborate $DESIGN_NAME
set_top_module $DESIGN_NAME

# 3. Carregamento e commit do UPF (metodologia lab4_reporting)
load_upf "$env(ROOT_DIR)/upf/top.upf"
commit_upf

# 4. Verificacao Multi-Voltage / UPF e geracao de relatorios
check_mv_design > "$env(ROOT_DIR)/upf/upf_check_mv.rpt"

redirect -file "$env(ROOT_DIR)/upf/upf_report.rpt" {
    report_power_domains
    report_supply_sets
    report_pst
    report_mv_cells
}

exit
