#
# Copyright (C) 2014-2017 The Android-x86 Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
ifeq ($(PC_BUILD),true)

ifneq ($(TARGET_NO_KERNEL),true)
ifeq ($(TARGET_PREBUILT_KERNEL),)

KERNEL_DIR ?= kernel/pc_common

ifneq ($(filter x86%,$(TARGET_ARCH)),)
TARGET_KERNEL_ARCH ?= $(TARGET_ARCH)
KERNEL_TARGET := bzImage
TARGET_KERNEL_CONFIG ?= android-$(TARGET_KERNEL_ARCH)_defconfig
KERNEL_CONFIG_DIR := arch/x86/configs
endif
ifeq ($(TARGET_ARCH),arm)
KERNEL_TARGET := zImage
TARGET_KERNEL_CONFIG ?= goldfish_defconfig
KERNEL_CONFIG_DIR := arch/arm/configs
endif

ifeq ($(TARGET_KERNEL_ARCH),x86_64)
CROSS_COMPILE ?= $(abspath prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.11-4.6/bin)/x86_64-linux-
else
CROSS_COMPILE ?= $(abspath $(TARGET_TOOLS_PREFIX))
endif
KBUILD_OUTPUT := $(abspath $(TARGET_OUT_INTERMEDIATES)/kernel)
mk_kernel := + $(hide) $(MAKE) -C $(KERNEL_DIR) O=$(KBUILD_OUTPUT) ARCH=$(TARGET_ARCH) CROSS_COMPILE="$(abspath $(CC_WRAPPER)) $(CROSS_COMPILE)" $(if $(SHOW_COMMANDS),V=1)

KERNEL_CONFIG_FILE := $(if $(wildcard $(TARGET_KERNEL_CONFIG)),$(TARGET_KERNEL_CONFIG),$(KERNEL_DIR)/$(KERNEL_CONFIG_DIR)/$(TARGET_KERNEL_CONFIG))

MOD_ENABLED := $(shell grep ^CONFIG_MODULES=y $(KERNEL_CONFIG_FILE))
FIRMWARE_ENABLED := $(shell grep ^CONFIG_FIRMWARE_IN_KERNEL=y $(KERNEL_CONFIG_FILE))

# I understand Android build system discourage to use submake,
# but I don't want to write a complex Android.mk to build kernel.
# This is the simplest way I can think.
KERNEL_DOTCONFIG_FILE := $(KBUILD_OUTPUT)/.config
KERNEL_ARCH_CHANGED := $(if $(filter 0,$(shell grep -s ^$(if $(filter x86,$(TARGET_KERNEL_ARCH)),\#.)CONFIG_64BIT $(KERNEL_DOTCONFIG_FILE) | wc -l)),FORCE)
$(KERNEL_DOTCONFIG_FILE): $(KERNEL_CONFIG_FILE) $(wildcard $(TARGET_KERNEL_DIFFCONFIG)) $(KERNEL_ARCH_CHANGED)
	$(hide) mkdir -p $(@D) && cat $(wildcard $^) > $@
	$(mk_kernel) oldnoconfig

# bison is needed to build kernel and external modules from source
BISON := $(HOST_OUT_EXECUTABLES)/bison$(HOST_EXECUTABLE_SUFFIX)

BUILT_KERNEL_TARGET := $(KBUILD_OUTPUT)/arch/$(TARGET_ARCH)/boot/$(KERNEL_TARGET)
$(INSTALLED_KERNEL_TARGET): $(KERNEL_DOTCONFIG_FILE) | $(ACP) $(BISON)
	$(mk_kernel) $(KERNEL_TARGET) $(if $(MOD_ENABLED),modules)
	$(hide) $(ACP) -fp $(BUILT_KERNEL_TARGET) $@
	$(if $(FIRMWARE_ENABLED),$(mk_kernel) INSTALL_MOD_PATH=$(abspath $(TARGET_OUT)) firmware_install)

ifneq ($(MOD_ENABLED),)
KERNEL_MODULES_DEP := $(firstword $(wildcard $(TARGET_OUT)/lib/modules/*/modules.dep))
KERNEL_MODULES_DEP := $(if $(KERNEL_MODULES_DEP),$(KERNEL_MODULES_DEP),$(TARGET_OUT)/lib/modules)

ALL_EXTRA_MODULES := $(patsubst %,$(TARGET_OUT_INTERMEDIATES)/kmodule/%,$(TARGET_EXTRA_KERNEL_MODULES))
$(ALL_EXTRA_MODULES): $(TARGET_OUT_INTERMEDIATES)/kmodule/%: $(INSTALLED_KERNEL_TARGET)
	@echo Building additional kernel module $*
	$(hide) mkdir -p $(@D) && $(ACP) -fr $(EXTRA_KERNEL_MODULE_PATH_$*) $(@D)
	$(mk_kernel) M=$(abspath $@) modules

$(KERNEL_MODULES_DEP): $(INSTALLED_KERNEL_TARGET) $(ALL_EXTRA_MODULES)
	$(hide) rm -rf $(TARGET_OUT)/lib/modules
	$(mk_kernel) INSTALL_MOD_PATH=$(abspath $(TARGET_OUT)) modules_install
	+ $(hide) for kmod in $(TARGET_EXTRA_KERNEL_MODULES) ; do \
		echo Installing additional kernel module $${kmod} ; \
		$(subst +,,$(subst $(hide),,$(mk_kernel))) INSTALL_MOD_PATH=$(abspath $(TARGET_OUT)) M=$(abspath $(TARGET_OUT_INTERMEDIATES))/kmodule/$${kmod} modules_install ; \
	done
	$(hide) rm -f $(TARGET_OUT)/lib/modules/*/{build,source}
endif

$(BUILT_SYSTEMIMAGE): $(KERNEL_MODULES_DEP)

# rules to get source of Broadcom 802.11a/b/g/n hybrid device driver
# based on broadcomsetup.sh of Kyle Evans
WL_PATH := $(KERNEL_DIR)/drivers/net/wireless/broadcom/wl
ifeq ($(wildcard $(WL_PATH)/build.mk),)
WL_PATH := $(KERNEL_DIR)/drivers/net/wireless/wl
endif
-include $(WL_PATH)/build.mk

installclean: FILES += $(KBUILD_OUTPUT) $(INSTALLED_KERNEL_TARGET)

TARGET_PREBUILT_KERNEL := $(INSTALLED_KERNEL_TARGET)

.PHONY: kernel $(if $(KERNEL_ARCH_CHANGED),$(KERNEL_HEADERS_COMMON)/linux/binder.h)
kernel: $(TARGET_PREBUILT_KERNEL)

else

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_KERNEL) | $(ACP)
	$(copy-file-to-new-target)
ifdef TARGET_PREBUILT_MODULES
	mkdir -p $(TARGET_OUT)/lib
	$(hide) cp -r $(TARGET_PREBUILT_MODULES) $(TARGET_OUT)/lib
endif

endif # TARGET_PREBUILT_KERNEL
endif # KBUILD_OUTPUT

else

# Copyright (C) 2012 The CyanogenMod Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Android makefile to build kernel as a part of Android Build
#
# Configuration
# =============
#
# These config vars are usually set in BoardConfig.mk:
#
#   TARGET_KERNEL_SOURCE               = Kernel source dir, optional, defaults
#                                        to kernel/$(TARGET_DEVICE_DIR)
#   TARGET_KERNEL_CONFIG               = Kernel defconfig
#   TARGET_KERNEL_VARIANT_CONFIG       = Variant defconfig, optional
#   TARGET_KERNEL_SELINUX_CONFIG       = SELinux defconfig, optional
#   TARGET_KERNEL_ADDITIONAL_CONFIG    = Additional defconfig, optional
#   TARGET_KERNEL_ARCH                 = Kernel Arch
#   TARGET_KERNEL_HEADER_ARCH          = Optional Arch for kernel headers if
#                                          different from TARGET_KERNEL_ARCH
#   TARGET_USES_UNCOMPRESSED_KERNEL    = 'true' if Kernel is uncompressed,
#                                          optional, defaults to false
#   TARGET_KERNEL_CROSS_COMPILE_PREFIX = Compiler prefix (e.g. arm-eabi-)
#                                          defaults to arm-linux-androideabi- for arm
#                                                      aarch64-linux-android- for arm64
#                                                      x86_64-linux-android- for x86
#
#   BOARD_KERNEL_IMAGE_NAME            = Built image name, optional,
#                                          defaults to Image.gz on arm64
#                                          defaults to Image if TARGET_USES_UNCOMPRESSED_KERNEL
#                                          defaults to zImage otherwise
#
#   KERNEL_TOOLCHAIN_PREFIX            = Overrides TARGET_KERNEL_CROSS_COMPILE_PREFIX,
#                                          Set this var in shell to override
#                                          toolchain specified in BoardConfig.mk
#   KERNEL_TOOLCHAIN                   = Path to toolchain, if unset, assumes
#                                          TARGET_KERNEL_CROSS_COMPILE_PREFIX
#                                          is in PATH
#   USE_CCACHE                         = Enable ccache (global Android flag)
#
#   NEED_KERNEL_MODULE_ROOT            = Optional, if true, install kernel
#                                          modules in root instead of system


TARGET_AUTO_KDIR := $(shell echo $(TARGET_DEVICE_DIR) | sed -e 's/^device/kernel/g')

## Externally influenced variables
# kernel location - optional, defaults to kernel/<vendor>/<device>
TARGET_KERNEL_SOURCE ?= $(TARGET_AUTO_KDIR)
KERNEL_SRC := $(TARGET_KERNEL_SOURCE)
# kernel configuration - mandatory
KERNEL_DEFCONFIG := $(TARGET_KERNEL_CONFIG)
VARIANT_DEFCONFIG := $(TARGET_KERNEL_VARIANT_CONFIG)
SELINUX_DEFCONFIG := $(TARGET_KERNEL_SELINUX_CONFIG)

## Internal variables
KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
KERNEL_CONFIG := $(KERNEL_OUT)/.config
KERNEL_OUT_STAMP := $(KERNEL_OUT)/.mkdir_stamp

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := $(TARGET_ARCH)
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

ifeq ($(KERNEL_ARCH),x86_64)
KERNEL_DEFCONFIG_ARCH := x86
else
KERNEL_DEFCONFIG_ARCH := $(KERNEL_ARCH)
endif
KERNEL_DEFCONFIG_SRC := $(KERNEL_SRC)/arch/$(KERNEL_DEFCONFIG_ARCH)/configs/$(KERNEL_DEFCONFIG)

TARGET_KERNEL_HEADER_ARCH := $(strip $(TARGET_KERNEL_HEADER_ARCH))
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
KERNEL_HEADER_ARCH := $(KERNEL_ARCH)
else
KERNEL_HEADER_ARCH := $(TARGET_KERNEL_HEADER_ARCH)
endif

KERNEL_HEADER_DEFCONFIG := $(strip $(KERNEL_HEADER_DEFCONFIG))
ifeq ($(KERNEL_HEADER_DEFCONFIG),)
KERNEL_HEADER_DEFCONFIG := $(KERNEL_DEFCONFIG)
endif


ifneq ($(BOARD_KERNEL_IMAGE_NAME),)
  TARGET_PREBUILT_INT_KERNEL_TYPE := $(BOARD_KERNEL_IMAGE_NAME)
else
  ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
    TARGET_PREBUILT_INT_KERNEL_TYPE := Image
  else
    ifeq ($(KERNEL_ARCH),arm64)
      TARGET_PREBUILT_INT_KERNEL_TYPE := Image.gz
    else
      TARGET_PREBUILT_INT_KERNEL_TYPE := zImage
    endif
  endif
endif

TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(TARGET_PREBUILT_INT_KERNEL_TYPE)

# Clear this first to prevent accidental poisoning from env
MAKE_FLAGS :=

ifeq ($(KERNEL_ARCH),arm64)
  # Avoid "unsupported RELA relocation: 311" errors (R_AARCH64_ADR_GOT_PAGE)
  MAKE_FLAGS += CFLAGS_MODULE="-fno-pic"
  ifeq ($(TARGET_ARCH),arm)
    KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
  endif
endif

ifneq ($(TARGET_KERNEL_ADDITIONAL_CONFIG),)
KERNEL_ADDITIONAL_CONFIG := $(TARGET_KERNEL_ADDITIONAL_CONFIG)
KERNEL_ADDITIONAL_CONFIG_SRC := $(KERNEL_SRC)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_ADDITIONAL_CONFIG)
    ifeq ("$(wildcard $(KERNEL_ADDITIONAL_CONFIG_SRC))","")
        $(warning TARGET_KERNEL_ADDITIONAL_CONFIG '$(TARGET_KERNEL_ADDITIONAL_CONFIG)' doesn't exist)
        KERNEL_ADDITIONAL_CONFIG_SRC := /dev/null
    endif
else
    KERNEL_ADDITIONAL_CONFIG_SRC := /dev/null
endif

## Do be discontinued in a future version. Notify builder about target
## kernel format requirement
ifeq ($(BOARD_KERNEL_IMAGE_NAME),)
ifeq ($(BOARD_USES_UBOOT),true)
        $(error "Please set BOARD_KERNEL_IMAGE_NAME to uImage")
else ifeq ($(BOARD_USES_UNCOMPRESSED_BOOT),true)
        $(error "Please set BOARD_KERNEL_IMAGE_NAME to Image")
endif
endif

ifeq "$(wildcard $(KERNEL_SRC) )" ""
    ifneq ($(TARGET_PREBUILT_KERNEL),)
        HAS_PREBUILT_KERNEL := true
        NEEDS_KERNEL_COPY := true
    else
        $(foreach cf,$(PRODUCT_COPY_FILES), \
            $(eval _src := $(call word-colon,1,$(cf))) \
            $(eval _dest := $(call word-colon,2,$(cf))) \
            $(ifeq kernel,$(_dest), \
                $(eval HAS_PREBUILT_KERNEL := true)))
    endif

    ifneq ($(HAS_PREBUILT_KERNEL),)
        $(warning ***************************************************************)
        $(warning * Using prebuilt kernel binary instead of source              *)
        $(warning * THIS IS DEPRECATED, AND WILL BE DISCONTINUED                *)
        $(warning * Please configure your device to download the kernel         *)
        $(warning * source repository to $(KERNEL_SRC))
        $(warning * See http://wiki.cyanogenmod.org/w/Doc:_integrated_kernel_building)
        $(warning * for more information                                        *)
        $(warning ***************************************************************)
        FULL_KERNEL_BUILD := false
        KERNEL_BIN := $(TARGET_PREBUILT_KERNEL)
    else
        $(warning ***************************************************************)
        $(warning *                                                             *)
        $(warning * No kernel source found, and no fallback prebuilt defined.   *)
        $(warning * Please make sure your device is properly configured to      *)
        $(warning * download the kernel repository to $(KERNEL_SRC))
        $(warning * and add the TARGET_KERNEL_CONFIG variable to BoardConfig.mk *)
        $(warning *                                                             *)
        $(warning * As an alternative, define the TARGET_PREBUILT_KERNEL        *)
        $(warning * variable with the path to the prebuilt binary kernel image  *)
        $(warning * in your BoardConfig.mk file                                 *)
        $(warning *                                                             *)
        $(warning ***************************************************************)
        $(error "NO KERNEL")
    endif
else
    NEEDS_KERNEL_COPY := true
    ifeq ($(TARGET_KERNEL_CONFIG),)
        $(warning **********************************************************)
        $(warning * Kernel source found, but no configuration was defined  *)
        $(warning * Please add the TARGET_KERNEL_CONFIG variable to your   *)
        $(warning * BoardConfig.mk file                                    *)
        $(warning **********************************************************)
        # $(error "NO KERNEL CONFIG")
    else
        #$(info Kernel source found, building it)
        FULL_KERNEL_BUILD := true
        KERNEL_BIN := $(TARGET_PREBUILT_INT_KERNEL)
    endif
endif

ifeq ($(FULL_KERNEL_BUILD),true)

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_HEADERS_INSTALL_STAMP := $(KERNEL_OUT)/.headers_install_stamp

ifeq ($(NEED_KERNEL_MODULE_ROOT),true)
KERNEL_MODULES_INSTALL := root
KERNEL_MODULES_OUT := $(TARGET_ROOT_OUT)/lib/modules
else
KERNEL_MODULES_INSTALL := system
KERNEL_MODULES_OUT := $(TARGET_OUT)/lib/modules
endif

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
ifneq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
KERNEL_TOOLCHAIN_PREFIX ?= $(TARGET_KERNEL_CROSS_COMPILE_PREFIX)
else ifeq ($(TARGET_ARCH),arm64)
KERNEL_TOOLCHAIN_PREFIX ?= aarch64-linux-android-
else ifeq ($(TARGET_ARCH),arm)
KERNEL_TOOLCHAIN_PREFIX ?= arm-linux-androideabi-
else ifeq ($(TARGET_ARCH),x86)
KERNEL_TOOLCHAIN_PREFIX ?= x86_64-linux-android-
endif

ifeq ($(KERNEL_TOOLCHAIN),)
KERNEL_TOOLCHAIN_PATH := $(KERNEL_TOOLCHAIN_PREFIX)
else
ifneq ($(KERNEL_TOOLCHAIN_PREFIX),)
KERNEL_TOOLCHAIN_PATH := $(KERNEL_TOOLCHAIN)/$(KERNEL_TOOLCHAIN_PREFIX)
endif
endif

ifneq ($(USE_CCACHE),)
    ccache := $(ANDROID_BUILD_TOP)/prebuilts/misc/$(HOST_PREBUILT_TAG)/ccache/ccache
    # Check that the executable is here.
    ccache := $(strip $(wildcard $(ccache)))
endif

KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(ccache) $(KERNEL_TOOLCHAIN_PATH)"
ccache =

define mv-modules
    mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.order`;\
    if [ "$$mdpath" != "" ];then\
        mpath=`dirname $$mdpath`;\
        ko=`find $$mpath/kernel -type f -name *.ko`;\
        for i in $$ko; do $(KERNEL_TOOLCHAIN_PATH)strip --strip-unneeded $$i;\
        mv $$i $(KERNEL_MODULES_OUT)/; done;\
    fi
endef

define clean-module-folder
    mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.order`;\
    if [ "$$mdpath" != "" ];then\
        mpath=`dirname $$mdpath`; rm -rf $$mpath;\
    fi
endef

ifeq ($(HOST_OS),darwin)
  MAKE_FLAGS += C_INCLUDE_PATH=$(ANDROID_BUILD_TOP)/external/elfutils/libelf/
endif

ifeq ($(TARGET_KERNEL_MODULES),)
    TARGET_KERNEL_MODULES := no-external-modules
endif

$(KERNEL_OUT_STAMP):
	$(hide) mkdir -p $(KERNEL_OUT)
	$(hide) rm -rf $(KERNEL_MODULES_OUT)
	$(hide) mkdir -p $(KERNEL_MODULES_OUT)
	$(hide) touch $@

KERNEL_ADDITIONAL_CONFIG_OUT := $(KERNEL_OUT)/.additional_config

.PHONY: force_additional_config
$(KERNEL_ADDITIONAL_CONFIG_OUT): force_additional_config
	$(hide) cmp -s $(KERNEL_ADDITIONAL_CONFIG_SRC) $@ || cp $(KERNEL_ADDITIONAL_CONFIG_SRC) $@;

$(KERNEL_CONFIG): $(KERNEL_OUT_STAMP) $(KERNEL_DEFCONFIG_SRC) $(KERNEL_ADDITIONAL_CONFIG_OUT)
	@echo -e ${CL_GRN}"Building Kernel Config"${CL_RST}
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) VARIANT_DEFCONFIG=$(VARIANT_DEFCONFIG) SELINUX_DEFCONFIG=$(SELINUX_DEFCONFIG) $(KERNEL_DEFCONFIG)
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) oldconfig; fi
	$(hide) if [ ! -z "$(KERNEL_ADDITIONAL_CONFIG)" ]; then \
			echo "Using additional config '$(KERNEL_ADDITIONAL_CONFIG)'"; \
			$(KERNEL_SRC)/scripts/kconfig/merge_config.sh -m -O $(KERNEL_OUT) $(KERNEL_OUT)/.config $(KERNEL_SRC)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_ADDITIONAL_CONFIG); \
			$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) KCONFIG_ALLCONFIG=$(KERNEL_OUT)/.config alldefconfig; fi

TARGET_KERNEL_BINARIES: $(KERNEL_OUT_STAMP) $(KERNEL_CONFIG) $(KERNEL_HEADERS_INSTALL_STAMP)
	@echo -e ${CL_GRN}"Building Kernel"${CL_RST}
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(TARGET_PREBUILT_INT_KERNEL_TYPE)
	$(hide) if grep -q 'CONFIG_OF=y' $(KERNEL_CONFIG) ; \
			then \
				echo -e ${CL_GRN}"Building DTBs"${CL_RST} ; \
				$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) dtbs ; \
			else \
				echo "DTBs not enabled" ; \
			fi ;
	$(hide) if grep -q 'CONFIG_MODULES=y' $(KERNEL_CONFIG) ; \
			then \
				echo -e ${CL_GRN}"Building Kernel Modules"${CL_RST} ; \
				$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) modules && \
				$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) INSTALL_MOD_PATH=../../$(KERNEL_MODULES_INSTALL) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) modules_install && \
				$(mv-modules) && \
				$(clean-module-folder) ; \
			else \
				echo "Kernel Modules not enabled" ; \
			fi ;


$(TARGET_KERNEL_MODULES): TARGET_KERNEL_BINARIES

$(TARGET_PREBUILT_INT_KERNEL): $(TARGET_KERNEL_MODULES)
	$(mv-modules)
	$(clean-module-folder)

$(KERNEL_HEADERS_INSTALL_STAMP): $(KERNEL_OUT_STAMP) $(KERNEL_CONFIG)
	@echo -e ${CL_GRN}"Building Kernel Headers"${CL_RST}
	$(hide) if [ ! -z "$(KERNEL_HEADER_DEFCONFIG)" ]; then \
			rm -f ../$(KERNEL_CONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_HEADER_ARCH) $(KERNEL_CROSS_COMPILE) VARIANT_DEFCONFIG=$(VARIANT_DEFCONFIG) SELINUX_DEFCONFIG=$(SELINUX_DEFCONFIG) $(KERNEL_HEADER_DEFCONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_HEADER_ARCH) $(KERNEL_CROSS_COMPILE) headers_install; fi
	$(hide) if [ "$(KERNEL_HEADER_DEFCONFIG)" != "$(KERNEL_DEFCONFIG)" ]; then \
			echo "Used a different defconfig for header generation"; \
			rm -f ../$(KERNEL_CONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) VARIANT_DEFCONFIG=$(VARIANT_DEFCONFIG) SELINUX_DEFCONFIG=$(SELINUX_DEFCONFIG) $(KERNEL_DEFCONFIG); fi
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) oldconfig; fi
	$(hide) if [ ! -z "$(KERNEL_ADDITIONAL_CONFIG)" ]; then \
			echo "Using additional config '$(KERNEL_ADDITIONAL_CONFIG)'"; \
			$(KERNEL_SRC)/scripts/kconfig/merge_config.sh -m -O $(KERNEL_OUT) $(KERNEL_OUT)/.config $(KERNEL_SRC)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_ADDITIONAL_CONFIG); \
			$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) KCONFIG_ALLCONFIG=$(KERNEL_OUT)/.config alldefconfig; fi
	$(hide) touch $@

# provide this rule because there are dependencies on this throughout the repo
$(KERNEL_HEADERS_INSTALL): $(KERNEL_HEADERS_INSTALL_STAMP)

kerneltags: $(KERNEL_OUT_STAMP) $(KERNEL_CONFIG)
	$(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) tags

kernelconfig:  KERNELCONFIG_MODE := menuconfig
kernelxconfig: KERNELCONFIG_MODE := xconfig
kernelxconfig kernelconfig: $(KERNEL_OUT_STAMP)
	$(MAKE) $(MAKE_FLAGS) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNEL_DEFCONFIG)
	env KCONFIG_NOTIMESTAMP=true \
		 $(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) $(KERNELCONFIG_MODE)
	env KCONFIG_NOTIMESTAMP=true \
		 $(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) savedefconfig
	cp $(KERNEL_OUT)/defconfig $(KERNEL_DEFCONFIG_SRC)

alldefconfig: $(KERNEL_OUT_STAMP)
	env KCONFIG_NOTIMESTAMP=true \
		 $(MAKE) -C $(KERNEL_SRC) O=$(KERNEL_OUT) ARCH=$(KERNEL_ARCH) $(KERNEL_CROSS_COMPILE) alldefconfig

endif # FULL_KERNEL_BUILD

## Install it

ifeq ($(NEEDS_KERNEL_COPY),true)
file := $(INSTALLED_KERNEL_TARGET)
ALL_PREBUILT += $(file)
$(file) : $(KERNEL_BIN) | $(ACP)
	$(transform-prebuilt-to-target)

ALL_PREBUILT += $(INSTALLED_KERNEL_TARGET)
endif

.PHONY: kernel
kernel: $(INSTALLED_KERNEL_TARGET)


endif
