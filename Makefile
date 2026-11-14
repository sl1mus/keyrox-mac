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

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(OBJ) $(LDFLAGS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.m
	$(CC) $(OBJCFLAGS) -c $< -o $@

universal:
	$(CC) -arch arm64 -arch x86_64 $(CFLAGS) $(OBJCFLAGS) $(LDFLAGS) $(C_SRC) $(OBJC_SRC) -o $(TARGET)

clean:
	rm -f $(OBJ) $(TARGET)

install: $(TARGET)
	mkdir -p $(INSTALL_DIR)
	cp $(TARGET) $(INSTALL_DIR)/$(TARGET)
	chmod +x $(INSTALL_DIR)/$(TARGET)
	@if [ -d "$(AGY_BIN_DIR)" ]; then cp $(TARGET) $(AGY_BIN_DIR)/$(TARGET) && chmod +x $(AGY_BIN_DIR)/$(TARGET); fi
	@echo "Installed $(TARGET) to $(INSTALL_DIR)"

.PHONY: all clean install universal
