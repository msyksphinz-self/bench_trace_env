# SPEC CPU2006 Benchmark Makefile
# This Makefile allows parallel execution of benchmarks using QEMU
# without relying on SPEC's runspec command.

# Configuration
SPEC_ROOT := $(CURDIR)/spec2006_installed
ISO_FILE := $(abspath ../SPECCPU_2006_v1.1.iso)
CDROM_DIR := $(abspath ../spec2006_cdrom)
QEMU := $(abspath ../qemu-9.2.4/build)/qemu-riscv64
QEMU_BUILD_DIR := $(abspath ../qemu-9.2.4/build)
RISCV_SYSROOT := /riscv-linux/sysroot # inside docker container
QEMU_FLAGS := -L $(RISCV_SYSROOT)
BBV_PLUGIN := $(QEMU_BUILD_DIR)/contrib/plugins/libbbv.so
SPECINVOKE := $(SPEC_ROOT)/bin/specinvoke
RESULT_DIR := results
BBV_DIR := bbv_results
SIMPOINT_DIR := simpoint_results
SIFT_DIR := sift_results
SIMULATION_DIR := sniper_results
SIMPOINT_INTERVAL := 100000000
SIMPOINT := $(abspath ../SimPoint/bin/simpoint)
SIMPOINT_K := 30

PATH := $(QEMU_BUILD_DIR):$(PATH)
export PATH

# Sniper configuration for SIFT generation and simulation
# SNIPER_ROOT := $(abspath /home/kimura/work/sniper/prave_date2026/sniper)
SNIPER_ROOT := /home/kimura/work/riscv/sniper/snipersim
SNIPER_CONFIG_DIR := $(SNIPER_ROOT)/config
QEMU_FRONTEND_PLUGIN := $(SNIPER_ROOT)/frontend/qemu-frontend/libqemu-frontend.so
PIN_HOME := $(SNIPER_ROOT)/pin_kit
SNIPER_PYTHON_LIB := $(SNIPER_ROOT)/python_kit/intel64/lib
SNIPER_PIN_RUNTIME := $(PIN_HOME)/intel64/runtime
SNIPER_PIN_CPPLIB := $(PIN_HOME)/intel64/runtime/cpplibs
SNIPER_PIN_XED_LIB := $(PIN_HOME)/extras/xed-intel64/lib
SNIPER_PIN_RT_PINCRT := $(PIN_HOME)/intel64/runtime/pincrt
SNIPER_PIN_LIB_EXT := $(PIN_HOME)/intel64/lib-ext
SNIPER_CXX_LIB_PATH := $(strip $(shell ldd $(SNIPER_ROOT)/lib/sniper 2>/dev/null | awk '/libstdc\+\+\.so\.6/ {print $$3}' | grep '^/' | sed 's/\\/[^\\/]*$$//' | head -n1))
SNIPER_CXX_LIB_PATH := $(if $(SNIPER_CXX_LIB_PATH),$(SNIPER_CXX_LIB_PATH),/lib/x86_64-linux-gnu)
SNIPER_SIM_LD_PATH := $(SNIPER_PYTHON_LIB):$(SNIPER_CXX_LIB_PATH):$(SNIPER_PIN_CPPLIB):$(SNIPER_PIN_RUNTIME):$(SNIPER_PIN_RT_PINCRT):$(SNIPER_PIN_LIB_EXT):$(SNIPER_PIN_XED_LIB)
QEMU_CPU_OPTIONS := rv64,zba=true,zbb=true,v=true,vlen=1024,vext_spec=v1.0,rvv_ta_all_1s=true,rvv_ma_all_1s=true

# Benchmark list
bench_lists += 400.perlbench
bench_lists += 401.bzip2
bench_lists += 403.gcc
bench_lists += 429.mcf
bench_lists += 445.gobmk
bench_lists += 456.hmmer
bench_lists += 458.sjeng
bench_lists += 462.libquantum
bench_lists += 464.h264ref
bench_lists += 471.omnetpp
bench_lists += 473.astar
bench_lists += 483.xalancbmk

# Generate run targets
ALL_BENCH_TARGETS := $(addprefix all_,$(bench_lists))
RUN_BENCH_TARGETS := $(addprefix run_,$(bench_lists))
RUN_BBV_TARGETS := $(addprefix run_bbv_,$(bench_lists))
RUN_SIMPOINT_TARGETS := $(addprefix run_simpoint_,$(bench_lists))
RUN_SIFT_TARGETS := $(addprefix run_sift_,$(bench_lists))
RUN_SNIPER_TARGETS := $(addprefix run_sniper_,$(bench_lists))
ESTIMATE_IPC_TARGETS := $(addprefix estimate_ipc_,$(bench_lists))
BUILD_BENCH_TARGETS := $(addprefix build_,$(bench_lists))

# Default target
.DEFAULT_GOAL := help

help:
	@echo "SPEC CPU2006 Benchmark Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  extract_iso    - Mount and extract SPEC CPU2006 ISO to spec2006_cdrom"
	@echo "  prepare        - Install SPEC CPU2006"
	@echo "  build          - build SPEC CPU2006 and build benchmarks"
	@echo "  run            - Run all benchmarks (sequential)"
	@echo "  run_bbv        - Run all benchmarks with BBV collection (sequential)"
	@echo "  run_simpoint   - Run SimPoint analysis on all BBV results"
	@echo "  run_sift       - Generate SIFT traces based on SimPoint results"
	@echo "  run_sniper     - Run Sniper simulations using SIFT traces"
	@echo "  estimate_ipc   - Estimate overall IPC using SimPoint weights"
	@echo "  report         - Show summary of benchmark results"
	@echo "  clean          - Clean build and result directories"
	@echo "  clean-results  - Clean only result directories"
	@echo "  clean-bbv      - Clean only BBV results"
	@echo "  clean-simpoint - Clean only SimPoint results"
	@echo "  clean-sift     - Clean only SIFT results"
	@echo "  clean-simulation - Clean only simulation results"
	@echo ""
	@echo "Individual benchmark targets:"
	@echo "  run_<benchmark>         - Run a specific benchmark with all inputs"
	@echo "  run_bbv_<benchmark>     - Run a specific benchmark with BBV collection"
	@echo "  run_simpoint_<benchmark>- Run SimPoint analysis for a specific benchmark"
	@echo "  run_sift_<benchmark>    - Generate SIFT traces for a specific benchmark"
	@echo "  run_sniper_<benchmark>  - Run Sniper simulation for a specific benchmark"
	@echo "  estimate_ipc_<benchmark>- Estimate overall IPC for a specific benchmark"
	@echo ""
	@echo "Output directories:"
	@echo "  results/<benchmark>/        - Output files for each subcommand"
	@echo "  bbv_results/<benchmark>/    - BBV output files"
	@echo "  simpoint_results/<benchmark>/ - SimPoint output files (simpoints, weights)"
	@echo "  sift_results/<benchmark>/   - SIFT trace files"
	@echo "  sniper_results/<benchmark>/ - Sniper simulation results"
	@echo ""
	@echo "Available benchmarks:"
	@for bench in $(bench_lists); do echo "  - $$bench"; done
	@echo ""
	@echo "Examples:"
	@echo "  make run_429.mcf                       # Run 429.mcf"
	@echo "  make run_bbv_429.mcf                   # Run 429.mcf with BBV"
	@echo "  make run_simpoint_429.mcf              # Run SimPoint on 429.mcf BBV results"
	@echo "  make run_sift_429.mcf                  # Generate SIFT traces for 429.mcf"
	@echo "  make run_sniper_429.mcf                # Run Sniper simulation for 429.mcf"
	@echo "  make estimate_ipc_429.mcf              # Estimate overall IPC for 429.mcf"
	@echo "  make -j4 run_429.mcf run_401.bzip2     # Run 2 benchmarks in parallel"
	@echo "  make -j4 run_bbv_429.mcf run_bbv_401.bzip2   # Run 2 with BBV in parallel"
	@echo "  make -j4 run_simpoint_429.mcf run_simpoint_401.bzip2  # Run SimPoint in parallel"
	@echo "  make -j4 run_sniper_429.mcf run_sniper_401.bzip2      # Run Sniper simulations in parallel"

# Extract ISO file to spec2006_cdrom directory
extract_iso: .extract_iso
.extract_iso:
	@echo "=== Extracting SPEC CPU2006 ISO ==="
	@if [ ! -f "$(ISO_FILE)" ]; then \
		echo "Error: ISO file not found: $(ISO_FILE)"; \
		exit 1; \
	fi; \
	if [ -d "$(CDROM_DIR)" ]; then \
		echo "Directory $(CDROM_DIR) already exists. Skipping extraction."; \
	else \
		mkdir -p $(CDROM_DIR); \
		mount_point=$$(mktemp -d); \
		echo "Mounting $(ISO_FILE) to $$mount_point..."; \
		sudo mount -o loop,ro $(ISO_FILE) $$mount_point || exit 1; \
		echo "Copying files from ISO to $(CDROM_DIR)..."; \
		cp -r $$mount_point/* $(CDROM_DIR)/ || { sudo umount $$mount_point; rmdir $$mount_point; exit 1; }; \
		echo "Unmounting ISO..."; \
		sudo umount $$mount_point; \
		rmdir $$mount_point; \
		echo "=== ISO extraction completed ==="; \
	fi
	touch $@

# Prepare SPEC2006 installation
prepare: extract_iso .prepare_spec2006
.prepare_spec2006:
	cd $(CDROM_DIR) && ./install.sh -f -d $(PWD)/spec2006_installed
	touch $@

$(ALL_BENCH_TARGETS): benchmark=$(subst all_,,$@)
$(ALL_BENCH_TARGETS):
	$(MAKE) build_$(benchmark)
	$(MAKE) run_$(benchmark)

# Build all benchmarks
build: prepare .build_benchmarks
.build_benchmarks:
	@echo "Building all benchmarks..."
	$(MAKE) $(addprefix build_,$(bench_lists))
	touch $@

$(BUILD_BENCH_TARGETS): benchmark=$(subst build_,,$@)
$(BUILD_BENCH_TARGETS):
	@echo "Building $(benchmark)..."
	./scripts/build_benchmark.sh $(benchmark) || exit 1

# Run all benchmarks
run: $(RUN_BENCH_TARGETS)

$(RUN_BENCH_TARGETS): benchmark=$(subst run_,,$@)
$(RUN_BENCH_TARGETS):
	./scripts/run_benchmark.sh $(benchmark) $(SPEC_ROOT) $(SPECINVOKE) $(RESULT_DIR)

# Run all benchmarks with BBV collection
run_bbv: $(RUN_BBV_TARGETS)

$(RUN_BBV_TARGETS): benchmark=$(subst run_bbv_,,$@)
$(RUN_BBV_TARGETS):
	./scripts/run_bbv_benchmark.sh $(benchmark) $(SPEC_ROOT) $(SPECINVOKE) $(RESULT_DIR) $(BBV_DIR) $(QEMU) $(BBV_PLUGIN) $(SIMPOINT_INTERVAL)

# Run SimPoint analysis on all benchmarks
run_simpoint: $(RUN_SIMPOINT_TARGETS)

$(RUN_SIMPOINT_TARGETS): benchmark=$(subst run_simpoint_,,$@)
$(RUN_SIMPOINT_TARGETS): bbv_output_dir=$(BBV_DIR)/$(benchmark)
$(RUN_SIMPOINT_TARGETS): simpoint_output_dir=$(SIMPOINT_DIR)/$(benchmark)
$(RUN_SIMPOINT_TARGETS):
	@echo "=== Running SimPoint analysis for $(benchmark) ==="
	@mkdir -p $(simpoint_output_dir)
	@if [ ! -d "$(bbv_output_dir)" ]; then \
		echo "Error: BBV directory $(bbv_output_dir) not found. Please run 'make run_bbv_$(benchmark)' first."; \
		exit 1; \
	fi; \
	bbv_files=$$(ls $(bbv_output_dir)/bbv_*.out.*.bb 2>/dev/null); \
	if [ -z "$$bbv_files" ]; then \
		echo "Error: No BBV files found in $(bbv_output_dir). Please run 'make run_bbv_$(benchmark)' first."; \
		exit 1; \
	fi; \
	echo "$$bbv_files" | \
	parallel --line-buffer -j $$(nproc) \
	'bbv_file={}; \
	base_name=$$(basename $$bbv_file .bb); \
	simpoint_out="$(simpoint_output_dir)/$${base_name}.simpoints"; \
	weights_out="$(simpoint_output_dir)/$${base_name}.weights"; \
	echo "[$(benchmark)] Processing $$bbv_file..."; \
	$(SIMPOINT) -loadFVFile $$bbv_file -saveSimpoints $$simpoint_out -saveSimpointWeights $$weights_out -maxK $(SIMPOINT_K) > /dev/null 2>&1; \
	if [ -f "$$simpoint_out" ]; then \
		echo "[$(benchmark)] SimPoint completed: $$simpoint_out (weights: $$weights_out)"; \
	else \
		echo "[$(benchmark)] SimPoint failed for $$bbv_file"; \
	fi'; \
	echo "=== Completed SimPoint analysis for $(benchmark) ==="

# Generate SIFT traces based on SimPoint results
run_sift: $(RUN_SIFT_TARGETS)

$(RUN_SIFT_TARGETS): benchmark=$(subst run_sift_,,$@)
$(RUN_SIFT_TARGETS):
	@SPEC_ROOT=$(SPEC_ROOT) \
	SPECINVOKE=$(SPECINVOKE) \
	SIMPOINT_DIR=$(SIMPOINT_DIR) \
	SIFT_DIR=$(SIFT_DIR) \
	SNIPER_ROOT=$(SNIPER_ROOT) \
	PIN_HOME=$(PIN_HOME) \
	SNIPER_SIM_LD_PATH=$(SNIPER_SIM_LD_PATH) \
	QEMU=$(QEMU) \
	QEMU_FLAGS="$(QEMU_FLAGS)" \
	QEMU_CPU_OPTIONS="$(QEMU_CPU_OPTIONS)" \
	QEMU_FRONTEND_PLUGIN=$(QEMU_FRONTEND_PLUGIN) \
	./scripts/run_sift_benchmark.sh $(benchmark) $(SIMPOINT_INTERVAL)

# Run Sniper simulations using SIFT traces
run_sniper: $(RUN_SNIPER_TARGETS)

$(RUN_SNIPER_TARGETS): benchmark=$(subst run_sniper_,,$@)
$(RUN_SNIPER_TARGETS):
	@SNIPER_ROOT=$(SNIPER_ROOT) \
	SIFT_DIR=$(SIFT_DIR) \
	SIMULATION_DIR=$(SIMULATION_DIR) \
	CONFIG_DIR=$(SNIPER_CONFIG_DIR) \
	SIMPOINT_INTERVAL=$(SIMPOINT_INTERVAL) \
	./scripts/run_sniper_all_benchmark.sh $(benchmark)

# Estimate overall IPC using SimPoint weights
estimate_ipc: $(ESTIMATE_IPC_TARGETS)

$(ESTIMATE_IPC_TARGETS): benchmark=$(subst estimate_ipc_,,$@)
$(ESTIMATE_IPC_TARGETS):
	@SIMPOINT_DIR=$(SIMPOINT_DIR) \
	SIMULATION_DIR=$(SIMULATION_DIR) \
	./scripts/estimate_ipc.sh $(benchmark)

# Clean targets
clean: clean-results
	rm -rf .extract_iso .prepare_spec2006 .build_benchmarks
	rm -rf $(SPEC_ROOT)

clean-iso:
	rm -rf .extract_iso $(CDROM_DIR)

clean-results:
	rm -rf $(RESULT_DIR)

clean-bbv:
	rm -rf $(BBV_DIR)

clean-simpoint:
	rm -rf $(SIMPOINT_DIR)

clean-sift:
	rm -rf $(SIFT_DIR)

clean-simulation:
	rm -rf $(SIMULATION_DIR)

.PHONY: help extract_iso prepare build run run_bbv run_simpoint run_sift run_sniper estimate_ipc clean clean-results clean-bbv clean-simpoint clean-sift clean-simulation clean-iso $(RUN_BENCH_TARGETS) $(RUN_BBV_TARGETS) $(RUN_SIMPOINT_TARGETS) $(RUN_SIFT_TARGETS) $(RUN_SNIPER_TARGETS) $(ESTIMATE_IPC_TARGETS)
