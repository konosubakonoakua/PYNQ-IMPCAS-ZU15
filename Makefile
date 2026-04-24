# Copyright (C) 2022 Xilinx, Inc
# Copyright (c) 2022-2025, Advanced Micro Devices, Inc.

# SPDX-License-Identifier: BSD-3-Clause

# Prebuilt file versions
PYNQ_ROOTFS_VERSION ?= 3.1.0
PYNQ_SDIST_VERSION ?= 3.1.2

# PYNQ build configuration
PYNQ_PSWD ?= imp
# Optional proxy to bake into build/runtime (empty = disabled)
PYNQ_PROXY_URL ?=

# Prebuilt file URLs
PYNQ_ROOTFS_URL ?= https://download.amd.com/opendownload/pynq/jammy.aarch64.$(PYNQ_ROOTFS_VERSION).tar.gz
PYNQ_SDIST_URL ?= https://download.amd.com/opendownload/pynq/pynq-$(PYNQ_SDIST_VERSION).tar.gz

# SD Card configuration
SDCARD_DEVICE ?= /dev/sdb
IMAGE_FILE ?= ${ROOT_PATH}/pynq/sdbuild/output/${BOARD_NAME}-*.img

ROOT_PATH := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))

BOARD_NAME ?= Pynq-IMPCAS-ZU15

PREBUILT_IMAGE := ${ROOT_PATH}/pynq/sdbuild/prebuilt/pynq_rootfs.aarch64.tar.gz
PREBUILT_SDIST := ${ROOT_PATH}/pynq/sdbuild/prebuilt/pynq_sdist.tar.gz
BASE_XSA_FILE := ${ROOT_PATH}/${BOARD_NAME}/base/base.xsa
BASE_OVERLAY_DIR := ${ROOT_PATH}/${BOARD_NAME}/base
BASE_OVERLAY_MAKE := ${BASE_OVERLAY_DIR}/Makefile

# Default target
.DEFAULT_GOAL := help

# Define colors for better output
ifneq (,$(findstring xterm,${TERM}))
	BLACK        := $(shell tput -Txterm setaf 0)
	RED          := $(shell tput -Txterm setaf 1)
	GREEN        := $(shell tput -Txterm setaf 2)
	YELLOW       := $(shell tput -Txterm setaf 3)
	LIGHTPURPLE  := $(shell tput -Txterm setaf 4)
	PURPLE       := $(shell tput -Txterm setaf 5)
	BLUE         := $(shell tput -Txterm setaf 6)
	WHITE        := $(shell tput -Txterm setaf 7)
	RESET        := $(shell tput -Txterm sgr0)
	BOLD         := $(shell tput bold)
else
	BLACK        := ""
	RED          := ""
	GREEN        := ""
	YELLOW       := ""
	LIGHTPURPLE  := ""
	PURPLE       := ""
	BLUE         := ""
	WHITE        := ""
	RESET        := ""
	BOLD         := ""
endif

##@ Build Targets

all: gitsubmodule base image ## Build complete project (default: all)
	@echo "$(GREEN)Build completed for ${BOARD_NAME}$(RESET)"

image: base gitsubmodule ${PREBUILT_SDIST} ${PREBUILT_IMAGE} ## Build SD card image
	cd ${ROOT_PATH}/pynq/sdbuild/ && \
	PYNQ_PROXY_URL="$(PYNQ_PROXY_URL)" \
	make BOARDDIR=${ROOT_PATH}/ BOARDS=${BOARD_NAME} PYNQ_PSWD=${PYNQ_PSWD}

boot_files: base gitsubmodule ${PREBUILT_SDIST} ${PREBUILT_IMAGE} ## Generate only boot files (BOOT.BIN, image.ub)
	cd ${ROOT_PATH}/pynq/sdbuild/ && \
	PYNQ_PROXY_URL="$(PYNQ_PROXY_URL)" \
	make boot_files BOARDDIR=${ROOT_PATH}/ BOARDS=${BOARD_NAME} PYNQ_PSWD=${PYNQ_PSWD}

bsp: base gitsubmodule ${PREBUILT_SDIST} ${PREBUILT_IMAGE} ## Generate Petalinux BSP package
	cd ${ROOT_PATH}/pynq/sdbuild/ && \
	PYNQ_PROXY_URL="$(PYNQ_PROXY_URL)" \
	make bsp BOARDDIR=${ROOT_PATH}/ BOARDS=${BOARD_NAME} PYNQ_PSWD=${PYNQ_PSWD}

sysroot: gitsubmodule ${PREBUILT_SDIST} ${PREBUILT_IMAGE} ## Generate SDK sysroot for cross-compilation
	cd ${ROOT_PATH}/pynq/sdbuild/ && \
	PYNQ_PROXY_URL="$(PYNQ_PROXY_URL)" \
	make sysroot BOARDDIR=${ROOT_PATH}/ BOARDS=${BOARD_NAME} PYNQ_PSWD=${PYNQ_PSWD}

clean: unsetgitproxy ## Remove all build artifacts
	cd ${ROOT_PATH}/pynq/sdbuild/ && make clean
	@echo "$(GREEN)All build artifacts cleaned$(RESET)"

clean_bsp: unsetgitproxy ## Remove bsp artifacts
	cd ${ROOT_PATH}/pynq/sdbuild/build/ && rm -rf $(BOARD_NAME)
	@echo "$(GREEN)BSP artifacts cleaned$(RESET)"

base: ${BOARD_FILES} base_overlay ## Verify and build base hardware design
	@echo "$(GREEN)XSA file verification passed for ${BOARD_NAME}$(RESET)"

base_overlay: check-xsa ## Build overlay artifacts (bit/hwh) from XSA
	@if [ ! -f "$(BASE_OVERLAY_MAKE)" ]; then \
		echo "$(RED)Error: Overlay Makefile not found: $(BASE_OVERLAY_MAKE)$(RESET)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Building overlay in $(BASE_OVERLAY_DIR) ...$(RESET)"
	$(MAKE) -C $(BASE_OVERLAY_DIR) clean all
	@echo "$(GREEN)Overlay build done: $$(ls -1 $(BASE_OVERLAY_DIR)/*.bit 2>/dev/null || true)$(RESET)"

check-xsa: ## Verify XSA file existence
	@if [ ! -f "$(BASE_XSA_FILE)" ]; then \
		echo "$(RED)Error: XSA file does not exist: $(BASE_XSA_FILE)$(RESET)"; \
		echo "The XSA file should exist by default for board ${BOARD_NAME}. Please check:"; \
		echo "1. If the hardware project has been built successfully"; \
		echo "2. If the BOARD_NAME variable is set correctly"; \
		echo "3. If the Vivado project has been exported properly"; \
		exit 1; \
	fi
	@echo "$(GREEN)XSA file exists for ${BOARD_NAME}: $(BASE_XSA_FILE)$(RESET)"

##@ SD Card Operations

sdcard: sdcard-confirm ## Burn image to SD card with safety confirmation (default: /dev/sdb)

sdcard-confirm: check-image check-sdcard ## Burn image to SD card with interactive confirmation
	@echo "$(RED)===============================================$(RESET)"
	@echo "$(RED)          ⚠️  DANGEROUS OPERATION ⚠️          $(RESET)"
	@echo "$(RED)===============================================$(RESET)"
	@echo "$(BOLD)This operation will COMPLETELY ERASE:$(RESET)"
	@echo "  Target device: $(SDCARD_DEVICE)"
	@echo "  Device info: $$(lsblk -nd -o SIZE,MODEL $(SDCARD_DEVICE) 2>/dev/null || echo 'Unknown device')"
	@echo "  Image file: $$(ls $(IMAGE_FILE))"
	@echo ""
	@echo "$(RED)All existing data on $(SDCARD_DEVICE) will be PERMANENTLY DESTROYED!$(RESET)"
	@echo ""
	@echo "To proceed, type the full path of the SD card device: $(SDCARD_DEVICE)"
	@echo "To abort, press Ctrl+C or enter anything else."
	@echo ""
	@printf "$(YELLOW)Confirm device path: $(RESET)"
	@read user_input; \
	if [ "$$user_input" = "$(SDCARD_DEVICE)" ]; then \
		echo "$(YELLOW)Final confirmation: Type 'Y' to start burning: $(RESET)"; \
		read final_confirm; \
		if [ "$$final_confirm" = "Y" ]; then \
			echo "$(BLUE)Starting SD card burn operation...$(RESET)"; \
			$(MAKE) sdcard-burn; \
		else \
			echo "$(GREEN)Operation aborted by user.$(RESET)"; \
		fi; \
	else \
		echo "$(GREEN)Operation aborted. Device path mismatch.$(RESET)"; \
	fi

sdcard-burn: ## Actually burn image to SD card (internal use only)
	$(eval ACTUAL_IMAGE := $(lastword $(sort $(wildcard $(IMAGE_FILE)))))
	@if [ -z "$(ACTUAL_IMAGE)" ]; then \
		echo "$(RED)Error: No image file found matching $(IMAGE_FILE)$(RESET)"; exit 1; \
	fi; \
	echo "$(BLUE)[1/3] Checking for mounted partitions on $(SDCARD_DEVICE)...$(RESET)"; \
	MOUNTPOINTS=$$(lsblk -ln -o MOUNTPOINT $(SDCARD_DEVICE) | grep -v "^$$"); \
	if [ -n "$$MOUNTPOINTS" ]; then \
		echo "$(YELLOW)Device is mounted on: $$MOUNTPOINTS. Unmounting...$(RESET)"; \
		sudo umount $(SDCARD_DEVICE)* 2>/dev/null || true; \
		sudo umount -l $(SDCARD_DEVICE) 2>/dev/null || true; \
	else \
		echo "$(GREEN)Device is not mounted. Safe to proceed.$(RESET)"; \
	fi; \
	echo "$(BLUE)[2/3] Burning image: $(ACTUAL_IMAGE)$(RESET)"; \
	sudo dd if=$(ACTUAL_IMAGE) of=$(SDCARD_DEVICE) bs=8M status=progress oflag=dsync; \
	echo "$(BLUE)[3/3] Flushing ...$(RESET)"; \
	sync; \
	echo "$(YELLOW)------------------------------------------------$(RESET)"; \
	echo "$(GREEN)Burning process completed successfully!$(RESET)"; \
	read -p "Eject SD card now? (y/N): " user_choice; \
	if [ "$$user_choice" = "y" ] || [ "$$user_choice" = "Y" ]; then \
		echo "$(BLUE)Ejecting $(SDCARD_DEVICE)...$(RESET)"; \
		sudo eject $(SDCARD_DEVICE) 2>/dev/null || (sync && echo "$(GREEN)Cache synced. Safe to remove.$(RESET)"); \
		echo "$(GREEN)Device ejected.$(RESET)"; \
	else \
		echo "$(BLUE)Remember to eject the device before physical removal.$(RESET)"; \
	fi

sdcard-list: ## List available block devices for SD card selection
	@echo "$(BLUE)Available block devices:$(RESET)"
	@which lsblk >/dev/null 2>&1 && lsblk || (echo "Using fdisk:" && sudo fdisk -l)

sdcard-format: ## Format SD card with FAT32 filesystem
	@echo "$(YELLOW)Formatting $(SDCARD_DEVICE) as FAT32$(RESET)"
	@echo "$(YELLOW)WARNING: This will erase all data on $(SDCARD_DEVICE)$(RESET)"
	@echo "$(YELLOW)Press Ctrl+C within 3 seconds to abort...$(RESET)"
	@sleep 3
	sudo umount $(SDCARD_DEVICE)* 2>/dev/null || true
	sudo mkfs.vfat -F 32 -n BOOT $(SDCARD_DEVICE)1
	@echo "$(GREEN)SD card formatting completed!$(RESET)"

sdcard-safe: check-sdcard sdcard-confirm ## Safe SD card burn with double confirmation

check-sdcard: ## Check if SD card is properly detected
	@if [ ! -b "$(SDCARD_DEVICE)" ]; then \
		echo "$(RED)Error: SD card device $(SDCARD_DEVICE) not found$(RESET)"; \
		echo "$(BLUE)Available devices:$(RESET)"; \
		which lsblk > /dev/null 2>&1 && lsblk || fdisk -l; \
		exit 1; \
	fi
	@echo "$(GREEN)SD card detected at $(SDCARD_DEVICE)$(RESET)"
	@which lsblk > /dev/null 2>&1 && lsblk $(SDCARD_DEVICE) || true

check-image: ## Check if the image file exists
	@if [ ! -f "$(IMAGE_FILE)" ]; then \
		IMAGE_PATH=$$(ls $(IMAGE_FILE) 2>/dev/null | head -1); \
		if [ -z "$$IMAGE_PATH" ]; then \
			echo "$(RED)Error: No image file found for ${BOARD_NAME}$(RESET)"; \
			echo "Please run 'make image' first to build the image"; \
			echo "Expected pattern: $(IMAGE_FILE)"; \
			exit 1; \
		fi; \
		IMAGE_FILE="$$IMAGE_PATH"; \
	fi
	@echo "$(GREEN)✓ Image file found: $$(ls $(IMAGE_FILE))$(RESET)"

##@ Utility Targets

gitsubmodule: setgitproxy ## Initialize and update Git submodules
	@echo "$(BLUE)Updating submodules$(RESET)"
	git submodule init && git submodule update

setgitproxy: ## Set proxy for Git (user & root)
	@echo "$(BLUE)Setting git proxy$(RESET)"
	@if [ -n "$$SUDO_USER" ]; then \
		sudo -u $$SUDO_USER git config --global http.proxy "$(PYNQ_PROXY_URL)"; \
		sudo -u $$SUDO_USER git config --global https.proxy "$(PYNQ_PROXY_URL)"; \
	else \
		git config --global http.proxy "$(PYNQ_PROXY_URL)"; \
		git config --global https.proxy "$(PYNQ_PROXY_URL)"; \
	fi
	sudo -u root git config --global http.proxy "$(PYNQ_PROXY_URL)";
	sudo -u root git config --global https.proxy "$(PYNQ_PROXY_URL)";

unsetgitproxy: ## Unset proxy for Git (user & root)
	@echo "$(BLUE)Unsetting git proxy$(RESET)"
	sudo -u root git config --global --unset http.proxy || true;
	sudo -u root git config --global --unset https.proxy || true;
	@if [ -n "$$SUDO_USER" ]; then \
		sudo -u $$SUDO_USER git config --global --unset http.proxy || true; \
		sudo -u $$SUDO_USER git config --global --unset https.proxy || true; \
	else \
		git config --global --unset http.proxy || true; \
		git config --global --unset https.proxy || true; \
	fi

cleanbuild: unsetgitproxy ## Clean build artifacts
	sudo make -C pynq/sdbuild/ clean
	@echo "$(GREEN)Build artifacts cleaned$(RESET)"

status: ## Show build status and file information
	@echo "$(BLUE)=== Build Status for ${BOARD_NAME} ===$(RESET)"
	@echo "Root path: ${ROOT_PATH}"
	@echo "Board name: ${BOARD_NAME}"
	@echo "PYNQ password: ${PYNQ_PSWD}"
	@echo ""
	@echo "$(BOLD)Key files:$(RESET)"
	@if [ -f "$(BASE_XSA_FILE)" ]; then \
		echo "$(GREEN)✓ XSA file: $(BASE_XSA_FILE)$(RESET)"; \
	else \
		echo "$(RED)✗ XSA file: $(BASE_XSA_FILE) (MISSING)$(RESET)"; \
	fi
	@if [ -f "$(PREBUILT_IMAGE)" ]; then \
		echo "$(GREEN)✓ RootFS: $(PREBUILT_IMAGE)$(RESET)"; \
	else \
		echo "$(YELLOW)✗ RootFS: $(PREBUILT_IMAGE) (Not downloaded)$(RESET)"; \
	fi
	@if [ -f "$(PREBUILT_SDIST)" ]; then \
		echo "$(GREEN)✓ SDist: $(PREBUILT_SDIST)$(RESET)"; \
	else \
		echo "$(YELLOW)✗ SDist: $(PREBUILT_SDIST) (Not downloaded)$(RESET)"; \
	fi
	@echo ""
	@echo "$(BOLD)Available images:$(RESET)"
	@ls ${ROOT_PATH}/pynq/sdbuild/output/*.img 2>/dev/null || echo "$(YELLOW)No built images found$(RESET)"

##@ Prebuilt Downloads

${PREBUILT_IMAGE}: ## Download prebuilt root filesystem
	wget $(PYNQ_ROOTFS_URL) -O $@
	@echo "$(GREEN)Downloaded $@ (version $(PYNQ_ROOTFS_VERSION))$(RESET)"

${PREBUILT_SDIST}: ## Download PYNQ SDist package
	wget $(PYNQ_SDIST_URL) -O $@
	@echo "$(GREEN)Downloaded $@ (version $(PYNQ_SDIST_VERSION))$(RESET)"

##@ Help System

help: ## Show this help message
	@echo '$(BOLD)PYNQ Build System$(RESET)'
	@echo ''
	@echo '$(BOLD)Usage:$(RESET)'
	@echo '  make $(BLUE)<target>$(RESET) [$(YELLOW)VARIABLE=value$(RESET)...]'
	@echo ''
	@echo '$(BOLD)Available Targets:$(RESET)'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(BLUE)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort
	@echo ''
	@echo '$(BOLD)Configuration Variables:$(RESET)'
	@echo '  $(YELLOW)BOARD_NAME$(RESET)            Board to build for (default: $(BOARD_NAME))'
	@echo '  $(YELLOW)PYNQ_ROOTFS_VERSION$(RESET)   RootFS version (default: $(PYNQ_ROOTFS_VERSION))'
	@echo '  $(YELLOW)PYNQ_SDIST_VERSION$(RESET)    SDist version (default: $(PYNQ_SDIST_VERSION))'
	@echo '  $(YELLOW)PYNQ_PSWD$(RESET)             PYNQ password (default: $(PYNQ_PSWD))'
	@echo '  $(YELLOW)PYNQ_PROXY_URL$(RESET)        PYNQ proxy url (default: empty)'
	@echo '  $(YELLOW)SDCARD_DEVICE$(RESET)         SD card device (default: $(SDCARD_DEVICE))'
	@echo '  $(YELLOW)IMAGE_FILE$(RESET)            Image file path (default: auto-detected)'
	@echo ''
	@echo '$(BOLD)Common Examples:$(RESET)'
	@echo '  $(BLUE)make$(RESET)                                Show this help message'
	@echo '  $(BLUE)make all$(RESET)                            Build complete project'
	@echo '  $(BLUE)make image$(RESET)                          Build SD card image only'
	@echo '  $(BLUE)make boot_files$(RESET)                     Generate boot files only'
	@echo '  $(BLUE)make bsp$(RESET)                            Generate Petalinux BSP'
	@echo '  $(BLUE)make sysroot$(RESET)                        Generate SDK sysroot'
	@echo '  $(BLUE)make sdcard$(RESET)                         Burn image to SD card'
	@echo '  $(BLUE)make sdcard SDCARD_DEVICE=/dev/sdc$(RESET)  Burn to specific device'
	@echo '  $(BLUE)make status$(RESET)                         Show build status'
	@echo '  $(BLUE)make clean$(RESET)                          Clean all artifacts'
	@echo ''

# Add aliases for download targets
download-rootfs: ${PREBUILT_IMAGE} ## Alias for downloading rootfs
download-sdist: ${PREBUILT_SDIST}  ## Alias for downloading sdist

.PHONY: all image boot_files bsp sysroot clean clean_bsp base check-xsa
.PHONY: sdcard sdcard-confirm sdcard-burn sdcard-list sdcard-format sdcard-safe check-sdcard check-image
.PHONY: gitsubmodule cleanbuild status help download-rootfs download-sdist
