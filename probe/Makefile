BUILD_DIR=build
SOURCE_DIR=.
include $(N64_INST)/include/n64.mk

N64_ROM_TITLE="FT64 r2i SD Probe"
N64_ROM_REGIONFREE=true
N64_ROM_CONTROLLER1=n64

all: ft64-sd-probe.z64

$(BUILD_DIR)/ft64-sd-probe.elf: $(BUILD_DIR)/sd_probe.o

clean:
	rm -rf $(BUILD_DIR) ft64-sd-probe.z64

-include $(wildcard $(BUILD_DIR)/*.d)

.PHONY: all clean
