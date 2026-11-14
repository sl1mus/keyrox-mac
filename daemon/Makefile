CC = clang
CFLAGS = -O2 -Wall -Wextra -fobjc-arc
FRAMEWORKS = -framework Foundation -framework AppKit -framework IOKit -framework IOUSBHost -framework CoreFoundation

ARCH_FLAGS ?=

SRCS = keyrox-watchdog.m ../keyrox_reset.m ../keyrox_hid.c ../keyrox_proto.c
TARGET = keyrox-watchdog

all: $(TARGET)

universal:
	$(MAKE) clean
	$(MAKE) ARCH_FLAGS="-arch arm64 -arch x86_64"

$(TARGET): $(SRCS)
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -I.. $(FRAMEWORKS) $(SRCS) -o $(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all clean universal
