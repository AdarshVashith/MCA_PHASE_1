# Project 9 simulation Makefile (Icarus Verilog + GTKWave). Run from sim/:
#   make asm        assemble programs/*.s -> programs/*.hex (+ assembler self-test)
#   make unit       unit testbenches (decoder, instr_mem, data_mem, harvard_mem)
#   make harvard    every program on harvard_top
#   make vn         every program on vn_top (shared-memory baseline)
#   make compare    every program on both, prints the comparison table
#   make all        asm + unit + harvard + vn + compare + hier, logs in ../results/logs/
#   make hier       Phase II: every program on the memory hierarchy (tb_hier, one config:
#                   LATENCY=4, 8+8 split lines vs 16 unified lines); override L=, LINES=, WBUF=
#   make sweep      Phase II: full parameter sweep -> ../results/hier/sweep.csv,
#                   cross-checked against the ISS cache model (tools/sweep.py)
#   make iss        golden-model run of every program (tools/iss.py)
#   make waves      open the Harvard-vs-baseline waveform (PROG=memcopy) in GTKWave,
#                   or in Surfer if GTKWave is not installed (Homebrew no longer ships GTKWave for macOS)
#   make figure     regenerate the report's waveform figure from the memcopy simulation
#   make figure-hier  regenerate the Phase II (modified Harvard) waveform figure
#   make clean

IVERILOG := iverilog -g2005 -Wall -I ../tb
VVP      := vvp -n
PYTHON   := python3
BUILD    := build
LOGS     := ../results/logs

PROGRAMS := basic array_sum memcopy count_loop isa_test bubble_sort func_call transpose
PROG     ?= memcopy

MEM_RTL  := ../rtl/mem/instr_mem.v ../rtl/mem/data_mem.v ../rtl/mem/addr_decoder.v \
            ../rtl/mem/rw_ctrl.v ../rtl/mem/harvard_mem.v
CORE_RTL := ../rtl/core/regfile.v ../rtl/core/alu.v ../rtl/core/imm_gen.v \
            ../rtl/core/control.v ../rtl/core/pc_reg.v ../rtl/core/cpu_core.v
PERF_RTL := ../rtl/common/perf_counters.v
VN_RTL   := ../rtl/baseline/shared_mem.v ../rtl/baseline/cpu_core_vn.v ../rtl/baseline/vn_top.v \
            ../rtl/mem/addr_decoder.v ../rtl/core/regfile.v ../rtl/core/alu.v \
            ../rtl/core/imm_gen.v ../rtl/core/control.v
H_RTL    := $(MEM_RTL) $(CORE_RTL) $(PERF_RTL) ../rtl/harvard_top.v
ALL_RTL  := $(sort $(H_RTL) $(VN_RTL))
CACHE_RTL:= ../rtl/hier/main_mem.v ../rtl/hier/cache.v
HIER_RTL := $(CACHE_RTL) ../rtl/hier/mem_arbiter.v ../rtl/hier/mh_top.v ../rtl/hier/vnc_top.v \
            ../rtl/common/event_counter.v
SYS_RTL  := $(sort $(ALL_RTL) $(HIER_RTL))

# Phase II configuration for 'make hier' (the sweep varies these itself)
L        ?= 4
LINES    ?= 8
WBUF     ?= 1

# -P parameters for a system testbench, used inside a "for p in ..." shell loop:
#   $(call params,tb_name)  ->  -Ptb_name.PROG_NAME="basic" -Ptb_name.PROG_FILE=... etc.
# Escaped quotes so the shell still expands ${p}; braces so ${p}_data is not read as $p_data.
params = -P$(1).PROG_NAME=\"$${p}\" -P$(1).PROG_FILE=\"../programs/$${p}.hex\" \
         -P$(1).DATA_FILE=\"../programs/$${p}_data.hex\"

.PHONY: all asm unit harvard vn compare hier sweep iss waves figure figure-hier clean dirs

all: asm unit harvard vn compare hier

dirs:
	@mkdir -p $(BUILD) $(LOGS)

asm: dirs
	$(PYTHON) ../tools/asm.py --selftest | tee $(LOGS)/asm_selftest.log
	@for p in $(PROGRAMS); do \
	  $(PYTHON) ../tools/asm.py ../programs/$$p.s -o ../programs/$$p.hex || exit 1; \
	  echo "assembled $$p.s -> $$p.hex"; done

unit: dirs
	@rm -f $(LOGS)/unit.log
	@for t in tb_addr_decoder:../rtl/mem/addr_decoder.v \
	          tb_instr_mem:../rtl/mem/instr_mem.v \
	          tb_data_mem:../rtl/mem/data_mem.v \
	          tb_harvard_mem:"$(MEM_RTL)" \
	          tb_cache:"$(CACHE_RTL)"; do \
	  tb=$${t%%:*}; src=$${t#*:}; \
	  $(IVERILOG) -s $$tb -o $(BUILD)/$$tb.vvp ../tb/$$tb.v $$src || exit 1; \
	  $(VVP) $(BUILD)/$$tb.vvp | grep -v "VCD info" | tee -a $(LOGS)/unit.log; \
	done
	@! grep -q FAIL $(LOGS)/unit.log

harvard: dirs
	@rm -f $(LOGS)/harvard.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_harvard_top $(call params,tb_harvard_top) \
	    -o $(BUILD)/tb_harvard_top_$$p.vvp ../tb/tb_harvard_top.v $(H_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_harvard_top_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/harvard.log; \
	done
	@! grep -q FAIL $(LOGS)/harvard.log

vn: dirs
	@rm -f $(LOGS)/vn.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_vn_top $(call params,tb_vn_top) \
	    -o $(BUILD)/tb_vn_top_$$p.vvp ../tb/tb_vn_top.v $(VN_RTL) $(PERF_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_vn_top_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/vn.log; \
	done
	@! grep -q FAIL $(LOGS)/vn.log

compare: dirs
	@rm -f $(LOGS)/compare.log
	@echo "| Program    | Instr | LW/SW % | Harvard cycles | Harvard CPI | Baseline cycles | Baseline CPI | Speed-up | Simultaneous cycles |" | tee -a $(LOGS)/compare.log
	@echo "|---|---|---|---|---|---|---|---|---|" | tee -a $(LOGS)/compare.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_compare $(call params,tb_compare) \
	    -o $(BUILD)/tb_compare_$$p.vvp ../tb/tb_compare.v $(ALL_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_compare_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/compare.log; \
	done
	@! grep -q FAIL $(LOGS)/compare.log

hier: dirs
	@: > $(LOGS)/hier.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_hier $(call params,tb_hier) -Ptb_hier.LATENCY=$(L) -Ptb_hier.LINES=$(LINES) \
	    -Ptb_hier.WBUF=$(WBUF) -o $(BUILD)/tb_hier_$$p.vvp ../tb/tb_hier.v $(SYS_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_hier_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/hier.log; \
	done
	@! grep -q FAIL $(LOGS)/hier.log

sweep: dirs
	$(PYTHON) ../tools/sweep.py --rtl "$(SYS_RTL)" | tee $(LOGS)/sweep.log

iss:
	@for p in $(PROGRAMS); do echo "== $$p"; \
	  $(PYTHON) ../tools/iss.py ../programs/$$p.hex ../programs/$${p}_data.hex; done

waves: dirs
	@test -f $(BUILD)/tb_compare_$(PROG).vcd || $(MAKE) compare
	@if command -v gtkwave >/dev/null; then \
	  gtkwave $(BUILD)/tb_compare_$(PROG).vcd waves.gtkw & \
	elif command -v surfer >/dev/null; then \
	  surfer $(BUILD)/tb_compare_$(PROG).vcd -c waves.sucl & \
	else echo "install GTKWave or Surfer (brew install surfer) to view waveforms"; fi

figure: dirs
	@test -f $(BUILD)/tb_compare_memcopy.vcd || $(MAKE) compare
	$(PYTHON) ../tools/vcd2tikz.py $(BUILD)/tb_compare_memcopy.vcd -o ../report/figures/wave.tex --cycles 12

# Phase II waveform: memcopy on the modified-Harvard system (L=4, 8+8 lines)
figure-hier: dirs
	@p=memcopy; $(IVERILOG) -s tb_hier $(call params,tb_hier) -Ptb_hier.LATENCY=4 -Ptb_hier.LINES=8 \
	    -Ptb_hier.DUMP=1 -o $(BUILD)/tb_hier_memcopy_dump.vvp ../tb/tb_hier.v $(SYS_RTL)
	@$(VVP) $(BUILD)/tb_hier_memcopy_dump.vvp | grep -E "PASS|FAIL"
	$(PYTHON) ../tools/vcd2tikz_hier.py $(BUILD)/tb_hier_memcopy.vcd -o ../report/figures/wave_hier.tex \
	    --first 8 --cycles 18

clean:
	rm -rf $(BUILD)
