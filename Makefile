CC ?= clang
CFLAGS ?= -O2 -Wall -Wextra
OBJCFLAGS ?= -O2 -Wall -Wextra -fobjc-arc
LDFLAGS ?= -framework IOKit -framework CoreFoundation -framework IOUSBHost -framework Foundation

C_SRC = main.c keyrox_hid.c keyrox_proto.c
OBJC_SRC = keyrox_reset.m
OBJ = $(C_SRC:.c=.o) $(OBJC_SRC:.m=.o)
TARGET = keyrox-ctl

INSTALL_DIR ?= $(HOME)/.local/bin
AGY_BIN_DIR ?= $(HOME)/.gemini/antigravity/bin

all: $(TARGET) daemon

daemon:
	$(MAKE) -C daemon

gui:
	$(MAKE) -C gui

test:
	@mkdir -p tests
	$(CC) $(CFLAGS) -I. tests/test_proto.c keyrox_proto.c -o tests/test_proto
	@./tests/test_proto
	$(CC) $(OBJCFLAGS) -I. tests/test_watchdog.m keyrox_reset.m keyrox_hid.c keyrox_proto.c $(LDFLAGS) -framework AppKit -framework CoreGraphics -o tests/test_watchdog
	@./tests/test_watchdog

$(TARGET): $(OBJ)
	$(CC) $(OBJ) $(LDFLAGS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.m
	$(CC) $(OBJCFLAGS) -c $< -o $@

universal:
	$(CC) -arch arm64 -arch x86_64 $(CFLAGS) $(OBJCFLAGS) $(LDFLAGS) $(C_SRC) $(OBJC_SRC) -o $(TARGET)
	$(MAKE) -C daemon universal

clean:
	rm -f $(OBJ) $(TARGET) tests/test_proto tests/test_watchdog
	$(MAKE) -C daemon clean
	$(MAKE) -C gui clean

install: $(TARGET)
	$(MAKE) -C daemon universal
	mkdir -p $(INSTALL_DIR)
	cp $(TARGET) $(INSTALL_DIR)/$(TARGET)
	chmod +x $(INSTALL_DIR)/$(TARGET)
	cp daemon/keyrox-watchdog $(INSTALL_DIR)/keyrox-watchdog
	chmod +x $(INSTALL_DIR)/keyrox-watchdog
	@if [ -d "$(AGY_BIN_DIR)" ]; then cp $(TARGET) $(AGY_BIN_DIR)/$(TARGET) && chmod +x $(AGY_BIN_DIR)/$(TARGET); cp daemon/keyrox-watchdog $(AGY_BIN_DIR)/keyrox-watchdog && chmod +x $(AGY_BIN_DIR)/keyrox-watchdog; fi
	@echo "Installed $(TARGET) and keyrox-watchdog to $(INSTALL_DIR)"

.PHONY: all clean install universal daemon gui test
