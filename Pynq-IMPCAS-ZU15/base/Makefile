# Copyright (C) 2022 Xilinx, Inc
# SPDX-License-Identifier: BSD-3-Clause

overlay_name := base
design_name := base

XSA_FILE := $(overlay_name).xsa
BIT_FILE := $(overlay_name).bit
HWH_FILE := $(overlay_name).hwh

all: copy_xsa bitstream
	@echo
	@if [ -f "$(BIT_FILE)" ] && [ -f "$(HWH_FILE)" ]; then \
		tput setaf 2 ; echo "Built $(overlay_name) successfully! (Both .bit and .hwh found)"; tput sgr0; \
	elif [ -f "$(BIT_FILE)" ]; then \
		tput setaf 3 ; echo "Built $(BIT_FILE) but $(HWH_FILE) not found!"; tput sgr0; \
	else \
		tput setaf 1 ; echo "Error: $(BIT_FILE) not built!"; tput sgr0; \
	fi
	@echo

copy_xsa: $(XSA_FILE)
	mkdir -p ../petalinux_bsp/hardware_project/
	cp -f $(XSA_FILE) ../petalinux_bsp/hardware_project/

$(BIT_FILE): $(XSA_FILE)
	@echo "Extracting bitstream from $(XSA_FILE)..."
	@if unzip -q -o $(XSA_FILE) "*.bit" "*.hwh"; then \
		if [ -f "$(design_name).bit" ]; then \
			mv "$(design_name).bit" "$(BIT_FILE)"; \
			echo "Using $(design_name).bit as source for $(BIT_FILE)"; \
		elif [ -f "$(design_name)_wrapper.bit" ]; then \
			mv "$(design_name)_wrapper.bit" "$(BIT_FILE)"; \
			echo "Using $(design_name)_wrapper.bit as source for $(BIT_FILE)"; \
		else \
			echo "Error: No .bit file found in $(XSA_FILE)!"; \
			echo "Extracted files:"; \
			ls -1; \
			exit 1; \
		fi; \
		echo "Bitstream file generated: $(BIT_FILE)"; \
	else \
		echo "Error: Failed to unzip $(XSA_FILE)"; \
		exit 1; \
	fi

xsa: copy_xsa $(BIT_FILE)

bitstream: $(BIT_FILE)

clean:
	rm -f $(BIT_FILE) $(HWH_FILE)
	rm -rf *.bda *.c *.h *.html *.json *.xml psu_init.tcl
	rm -f ../petalinux_bsp/hardware_project/*.xsa

distclean: clean
	rm -f $(XSA_FILE)

.PHONY: all xsa bitstream copy_xsa clean distclean
