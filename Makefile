BUILD_DIR ?= build
THREADS ?= $(shell nproc)

CMAKE_FLAGS ?=
ifdef HYPRLAND_TAG
    CMAKE_FLAGS += -DHYPRLAND_TAG=$(HYPRLAND_TAG)
endif

PACKAGES = hyprutils hyprwire hyprwayland-scanner hyprlang aquamarine hyprgraphics hyprcursor hyprland

.PHONY: all clean help $(PACKAGES)

all: $(BUILD_DIR)/CMakeCache.txt
	cmake --build $(BUILD_DIR) -j $(THREADS)

$(BUILD_DIR)/CMakeCache.txt:
	cmake -B $(BUILD_DIR) -G Ninja $(CMAKE_FLAGS)

$(PACKAGES): $(BUILD_DIR)/CMakeCache.txt
	cmake --build $(BUILD_DIR) --target $@ -j $(THREADS)

clean:
	rm -rf $(BUILD_DIR)
	rm -rf v[0-9]*

help:
	@echo "Available targets:"
	@echo "  all                   - Build the entire stack"
	@echo "  clean                 - Remove build directory and tag install folders"
	@echo "  <package_name>        - Build a specific package (e.g., make aquamarine)"
	@echo ""
	@echo "Options:"
	@echo "  HYPRLAND_TAG=<tag>    - Build a specific Hyprland tag (e.g., make HYPRLAND_TAG=v0.42.0)"
