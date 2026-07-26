#======================================================================
# UART UVM Verification - dual-simulator build
#----------------------------------------------------------------------
#   Verilator (open source)      : default flow, no licence needed
#     make sva                   - build assertion regression
#     make sva_regress           - 4 baud rates, assertions + coverage
#     make cov_report            - annotate cover-property hits
#     make uvm_vl                - full UVM regression on Verilator
#                                  (requires UVM_HOME and Verilator >= 5.050)
#
#   Questa / ModelSim            : reference flow
#     make q_compile / q_run / q_gui / q_regression
#
#   make clean
#======================================================================

ROOT_DIR  = ..
RTL_DIR   = $(ROOT_DIR)/rtl
TB_DIR    = $(ROOT_DIR)/tb
UVM_DIR   = $(TB_DIR)/uvm
TOP_DIR   = $(TB_DIR)/top
SVA_DIR   = $(TB_DIR)/sva

#----------------------------------------------------------------------
# SOURCES
#----------------------------------------------------------------------
RTL_SRC   = $(RTL_DIR)/uart_tx.v \
            $(RTL_DIR)/uart_rx.v \
            $(RTL_DIR)/uart_top.sv

SVA_SRC   = $(SVA_DIR)/uart_sva_checker.sv \
            $(SVA_DIR)/uart_sva_bind.sv

SMOKE_SRC = $(SVA_DIR)/uart_sva_smoke_tb.sv

# Interface -> package -> top.  Order matters.
UVM_TB_SRC = $(TOP_DIR)/uart_if.sv \
             $(UVM_DIR)/uart_pkg.sv \
             $(TOP_DIR)/tb_top.sv

# Baud divisors for a 100 MHz clock
BAUDS = 10417 5208 1736 868
BAUD_NAME_10417 = 9600
BAUD_NAME_5208  = 19200
BAUD_NAME_1736  = 57600
BAUD_NAME_868   = 115200

#======================================================================
# VERILATOR FLOW
#======================================================================
VERILATOR ?= verilator

# --timing        : the testbench uses delays and event controls
# --assert        : elaborate the SVA in uart_sva_checker.sv
# --coverage      : collect cover-property hits into coverage.dat
# -Wno-INITIALDLY : the RTL is third-party nandland source; NBAs reached
#                   from an initial block are demoted to blocking, which
#                   is why the stimulus drives off the clock edge (#1)
VL_COMMON = --binary --timing --assert \
            --timescale 1ns/1ps \
            -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME \
            -Wno-MULTITOP -Wno-INITIALDLY

# ---- assertion regression (no UVM library required) ------------------
sva:
	$(VERILATOR) $(VL_COMMON) --top-module uart_sva_smoke_tb \
	    -GCLKS_PER_BIT=868 -o smoke \
	    $(RTL_SRC) $(SVA_SRC) $(SMOKE_SRC)

# Rebuilds per baud rate because CLKS_PER_BIT is elaboration-time.
sva_regress: clean_vl
	@for b in $(BAUDS); do \
	  echo "=== CLKS_PER_BIT=$$b ==="; \
	  $(VERILATOR) $(VL_COMMON) --top-module uart_sva_smoke_tb \
	      -GCLKS_PER_BIT=$$b -o smoke_$$b \
	      $(RTL_SRC) $(SVA_SRC) $(SMOKE_SRC) > /dev/null 2>&1 || exit 1; \
	  ./obj_dir/smoke_$$b | tee vl_$$b.log; \
	  mv coverage.dat cov_$$b.dat 2>/dev/null || true; \
	done
	@echo "-----------------------------------------------------"
	@grep -h "RESULT" vl_*.log
	@echo "-----------------------------------------------------"

cov_report:
	verilator_coverage --annotate cov_annotated $(wildcard cov_*.dat) coverage.dat
	@echo "Annotated cover-property hits written to cov_annotated/"

# ---- full UVM regression on Verilator --------------------------------
# Needs Verilator >= 5.050.  Earlier 5.0xx releases hit a scheduler
# convergence issue on virtual-interface writes from class tasks.
# Set UVM_HOME to an Accellera uvm-core checkout.
UVM_HOME ?= /opt/uvm-core
BAUD ?= 868

uvm_vl:
	@test -d $(UVM_HOME)/src || \
	  (echo "ERROR: set UVM_HOME to an Accellera uvm-core checkout"; exit 1)
	$(VERILATOR) $(VL_COMMON) -Wno-fatal --error-limit 500 \
	    +incdir+$(UVM_HOME)/src +incdir+$(UVM_DIR) \
	    $(UVM_HOME)/src/uvm_pkg.sv +define+UVM_NO_DPI \
	    --top-module tb_top -GCLKS_PER_BIT=$(BAUD) -o uvm_sim \
	    $(RTL_SRC) $(SVA_SRC) $(UVM_TB_SRC)
	./obj_dir/uvm_sim +UVM_TESTNAME=uart_test | tee vl_uvm.log

#======================================================================
# QUESTA / MODELSIM FLOW
#======================================================================
VLOG_FLAGS = -sv +incdir+$(UVM_DIR) +incdir+$(RTL_DIR) \
             -timescale 1ns/1ps -suppress 2181 -work work
VSIM_FLAGS = -voptargs=+acc -c -assertdebug -do "run -all; exit"

q_lib:
	vlib work

q_compile: q_lib
	vlog $(VLOG_FLAGS) $(RTL_SRC) $(SVA_SRC) $(UVM_TB_SRC)

q_run:
	vsim $(VSIM_FLAGS) work.tb_top -GCLKS_PER_BIT=868 -l run.log

q_gui:
	vsim -voptargs=+acc work.tb_top -GCLKS_PER_BIT=868

q_test_9600:
	vsim $(VSIM_FLAGS) work.tb_top -GCLKS_PER_BIT=10417 -l log_9600.log
q_test_19200:
	vsim $(VSIM_FLAGS) work.tb_top -GCLKS_PER_BIT=5208  -l log_19200.log
q_test_57600:
	vsim $(VSIM_FLAGS) work.tb_top -GCLKS_PER_BIT=1736  -l log_57600.log
q_test_115200:
	vsim $(VSIM_FLAGS) work.tb_top -GCLKS_PER_BIT=868   -l log_115200.log

q_regression: clean q_compile q_test_115200 q_test_57600 q_test_19200 q_test_9600
	@echo "---------------------------------------------------"
	@grep -c "PASS" log_*.log
	@grep "UVM_ERROR :" log_*.log
	@echo "---------------------------------------------------"

#======================================================================
clean_vl:
	rm -rf obj_dir cov_annotated coverage.dat cov_*.dat vl_*.log

clean: clean_vl
	rm -rf work transcript vsim.wlf log_*.log run.log

.PHONY: sva sva_regress cov_report uvm_vl q_lib q_compile q_run q_gui \
        q_regression clean clean_vl
