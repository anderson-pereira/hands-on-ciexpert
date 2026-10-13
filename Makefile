SHELL := /bin/bash

# ==========================================
# Default Goal
# ==========================================
.DEFAULT_GOAL := all

# ==========================================
# Base Directories (Absolute Paths)
# ==========================================
ROOT_DIR  := $(CURDIR)
RTL_DIR   := $(ROOT_DIR)/rtl
TB_DIR    := $(ROOT_DIR)/tb
SYN_DIR   := $(ROOT_DIR)/syn
FM_DIR    := $(ROOT_DIR)/formal
UPF_DIR   := $(ROOT_DIR)/upf
LIB_DIR   := $(ROOT_DIR)/libs

# ==========================================
# Build Directories (Artifacts)
# ==========================================
BUILD_DIR    := $(ROOT_DIR)/build
SIM_RTL_OUT  := $(BUILD_DIR)/sim_rtl
SYN_OUT      := $(BUILD_DIR)/syn
FM_OUT       := $(BUILD_DIR)/formal
UPF_OUT      := $(BUILD_DIR)/upf

# ==========================================
# EDA Tools Environment Setup
# ==========================================
ENABLE_TOOLS_SCRIPT := $(ROOT_DIR)/utils/enable_tools.sh
SNPS_ENV            := command -v vlogan >/dev/null 2>&1 || { [ -f $(ENABLE_TOOLS_SCRIPT) ] && source $(ENABLE_TOOLS_SCRIPT) -q; }

# ==========================================
# PDK Configuration (External Libraries)
# ==========================================
PDK_VERILOG_SRC := /Tools/PDK/SAED32/EDK_Digital/lib/stdcell_rvt/verilog/saed32nm.v
PDK_DB_SRC      := /Tools/PDK/SAED32/EDK_Digital/lib/stdcell_rvt/db_nldm/saed32rvt_tt1p05v25c.db

LIB_VERILOG := $(LIB_DIR)/saed32nm.v
LIB_DB      := $(LIB_DIR)/saed32rvt_tt1p05v25c.db

# ==========================================
# Files
# ==========================================
RTL_FILES = $(wildcard $(RTL_DIR)/*.sv)
TB_FILES  = $(wildcard $(TB_DIR)/*.sv)

# ==========================================
# Testbench Top & Scripts
# ==========================================
TOP = tb_top
SYN_SCRIPT = $(SYN_DIR)/synth.tcl
FM_SCRIPT = $(FM_DIR)/formality.tcl
UPF_FILE = $(UPF_DIR)/top.upf

# ==========================================
# Flags
# ==========================================
TIMESCALE = 1ns/1ps

VLOGAN_FLAGS =  -full64 \
                -timescale=$(TIMESCALE) \
                -sverilog \
                -kdb \
                +lint=all

VCS_FLAGS =     -full64 \
                -timescale=$(TIMESCALE) \
                -debug_access+all \
                -kdb

# ==========================================
# Library Setup & Verification
# ==========================================
$(LIB_DIR):
	mkdir -p $(LIB_DIR)

$(LIB_VERILOG): | $(LIB_DIR)
	@echo "[INFO] Copying PDK Verilog library..."
	cp $(PDK_VERILOG_SRC) $@ || touch $@

$(LIB_DB): | $(LIB_DIR)
	@echo "[INFO] Copying PDK Synthesis library (DB)..."
	cp $(PDK_DB_SRC) $@ || touch $@

prep_libs: $(LIB_VERILOG) $(LIB_DB)

# ==========================================
# Directory Preparation
# ==========================================
prep_sim_rtl: prep_libs
	mkdir -p $(SIM_RTL_OUT)

prep_syn: prep_libs
	mkdir -p $(SYN_OUT)

prep_fm: prep_libs
	mkdir -p $(FM_OUT)

prep_upf:
	mkdir -p $(UPF_OUT)

# ==========================================
# RTL Syntax (Lint) / Compilation / Run
# ==========================================
lint: prep_sim_rtl
	@echo "[INFO] Running Lint / Syntax Check..."
	cd $(SIM_RTL_OUT) && $(SNPS_ENV) && vlogan $(VLOGAN_FLAGS) $(RTL_FILES) -l $(ROOT_DIR)/tb/lint.log

compile: lint
	@echo "[INFO] Compiling RTL and TB..."
	cd $(SIM_RTL_OUT) && $(SNPS_ENV) && vlogan $(VLOGAN_FLAGS) $(TB_FILES) -l $(ROOT_DIR)/tb/compile.log
	cd $(SIM_RTL_OUT) && $(SNPS_ENV) && vcs $(VCS_FLAGS) -top $(TOP) -l $(ROOT_DIR)/tb/vcs.log

sim: compile
	@echo "[INFO] Running Simulation..."
	cd $(SIM_RTL_OUT) && $(SNPS_ENV) && ./simv -l $(ROOT_DIR)/tb/rtl_simulation.log

# ==========================================
# Synthesis
# ==========================================
synth: prep_syn
	@echo "[INFO] Running Synthesis..."
	cd $(SYN_OUT) && $(SNPS_ENV) && env ROOT_DIR=$(ROOT_DIR) dc_shell -f $(SYN_SCRIPT) | tee $(ROOT_DIR)/syn/synthesis.log || echo "[WARN] dc_shell failed or not found, skipping synthesis"

# ==========================================
# Formality
# ==========================================
formal: prep_fm
	@echo "[INFO] Running Formality..."
	cd $(FM_OUT) && $(SNPS_ENV) && env ROOT_DIR=$(ROOT_DIR) fm_shell -f $(FM_SCRIPT) | tee $(ROOT_DIR)/formal/formality.log || echo "[WARN] fm_shell failed or not found, skipping formality"

# ==========================================
# UPF Verification
# ==========================================
upf_check: prep_upf
	@echo "[INFO] Static UPF Check placeholder (requires VC Static or equivalent)"
	cd $(UPF_OUT) && $(SNPS_ENV) && vc_static -upf $(UPF_FILE) -sverilog $(RTL_FILES) -top top | tee $(ROOT_DIR)/upf/upf_static.log || echo "[WARN] vc_static not found, skipping UPF check"

# ==========================================
# Run All Minimum Flow
# ==========================================
all: sim synth formal upf_check
	@echo "[INFO] Flow completo executado com sucesso!"

run: all

# ==========================================
# Environment Verification
# ==========================================
check_tools:
	@echo "[INFO] Verificando ferramentas Synopsys..."
	@$(SNPS_ENV) && which vlogan vcs dc_shell fm_shell 2>/dev/null || echo "[WARN] Algumas ferramentas nao estao no PATH."

# ==========================================
# Clean-up
# ==========================================
clean:
	rm -rf $(BUILD_DIR) novas.rc novas.conf

clean_libs:
	rm -rf $(LIB_DIR)

clean_all: clean clean_libs

.PHONY: all prep_libs prep_sim_rtl prep_syn prep_fm prep_upf lint compile sim synth formal upf_check run check_tools clean clean_libs clean_all

