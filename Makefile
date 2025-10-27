SRC_DIR := lib_c
BUILD_DIR := priv
ERL_INCLUDE_PATH := $(HOME)/.elixir-install/installs/otp/28.1/usr/include

# NIF library target
NIF_SO := $(BUILD_DIR)/libvirt_nif.so
NIF_SRC := $(SRC_DIR)/libvirt_nif.c

CC := gcc
CFLAGS := -Wall -Wextra -O2 -fPIC $(shell pkg-config --cflags libvirt) -I${ERL_INCLUDE_PATH}
LDFLAGS := -shared $(shell pkg-config --libs libvirt)

# Detect OS for NIF linking
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    LDFLAGS += -dynamiclib -undefined dynamic_lookup
endif

all: $(NIF_SO)

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(NIF_SO): $(NIF_SRC) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "✅ Built NIF library: $@"

clean:
	rm -f $(NIF_SO)
	@echo "🧹 Cleaned build artifacts."

.PHONY: all clean