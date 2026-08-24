BUILD_DIR ?= build
INSTALL_DIR ?= install
REPO_JSON = $(BUILD_DIR)/stack/meta/repo_list.json

ifeq (,$(wildcard $(REPO_JSON)))
$(shell cmake -S . -B $(BUILD_DIR) -DFETCH_REPOS_ONLY=ON >/dev/null 2>&1)
endif

ifneq (,$(wildcard $(REPO_JSON)))
PACKAGES := $(shell jq -r '.[] | select(.name | startswith(".") | not) | select(.archived | not) | .name' $(REPO_JSON) 2>/dev/null)
endif

.PHONY: all configure build clean purge rebuild list help $(PACKAGES)

all: build

configure:
	cmake -B $(BUILD_DIR) -S . -DSTACK_PREFIX=$(INSTALL_DIR) $(CMAKE_FLAGS)

build:
	@if [ ! -d "$(BUILD_DIR)" ]; then $(MAKE) configure; fi
	cmake --build $(BUILD_DIR)

$(PACKAGES):
	@if [ ! -d "$(BUILD_DIR)" ]; then $(MAKE) configure; fi
	cmake -B $(BUILD_DIR) -S . -DSTACK_ROOT_PACKAGE=$@ $(if $($@),-D$(shell echo $@ | tr '[:lower:]' '[:upper:]' | tr '-' '_')=$($@),) -DSTACK_PREFIX=$(INSTALL_DIR) $(CMAKE_FLAGS)
	cmake --build $(BUILD_DIR) --target $@

clean:
	@if [ -d "$(BUILD_DIR)" ]; then cmake --build $(BUILD_DIR) --target clean; fi

purge:
	rm -rf $(BUILD_DIR)
	rm -rf $(INSTALL_DIR)
	rm -rf .cache/

list:
	@echo "Package repos:"
	@for c in $(PACKAGES); do echo "  $$c"; done

help:
	@echo "Available targets and usage:"
	@echo "  make                                   - Build hyprland stack by default"
	@echo "  make list                              - List all available packages"
	@echo "  make hyprpicker                        - Configure and build hyprpicker with its own deps"
	@echo "  make hyprpicker=1234                   - Checkout PR 1234 for hyprpicker and build stack"
	@echo "  make configure [CMAKE_FLAGS='...']     - Reconfigure with specific flags"
	@echo "  make clean                             - Clean build"
	@echo "  make purge                             - Clean build, install, and cache dirs"
	@echo "  make rebuild                           - Purge, configure, and build from scratch"

rebuild: purge configure build
