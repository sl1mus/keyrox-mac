CC ?= clang
CFLAGS ?= -O2 -Wall -Wextra -std=c99
LDFLAGS ?= -framework IOKit -framework CoreFoundation

SRC = main.c keyrox_hid.c keyrox_proto.c
OBJ = $(SRC:.c=.o)
TARGET = keyrox-ctl

INSTALL_DIR ?= /Users/kistenev/.local/bin
AGY_BIN_DIR ?= /Users/kistenev/.gemini/antigravity/bin

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(OBJ) $(LDFLAGS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) $(TARGET)

install: $(TARGET)
	mkdir -p $(INSTALL_DIR) $(AGY_BIN_DIR)
	cp $(TARGET) $(INSTALL_DIR)/$(TARGET)
	cp $(TARGET) $(AGY_BIN_DIR)/$(TARGET)
	chmod +x $(INSTALL_DIR)/$(TARGET) $(AGY_BIN_DIR)/$(TARGET)
	@echo "Installed $(TARGET) to $(INSTALL_DIR) and $(AGY_BIN_DIR)"

.PHONY: all clean install
