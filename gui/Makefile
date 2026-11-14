CC = clang
CFLAGS = -O2 -Wall -Wextra -std=c99 -fobjc-arc
OBJCFLAGS = -O2 -Wall -Wextra -fobjc-arc
FRAMEWORKS = -framework Cocoa -framework WebKit -framework IOKit -framework CoreFoundation -framework UniformTypeIdentifiers -framework IOUSBHost

APP_NAME = Keyrox
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources

C_SRCS = ../keyrox_hid.c ../keyrox_proto.c
OBJC_SRCS = src/main.m src/AppDelegate.m ../keyrox_reset.m

ARCH_FLAGS ?=

all: $(APP_BUNDLE)

universal:
	$(MAKE) clean
	$(MAKE) ARCH_FLAGS="-arch arm64 -arch x86_64"

$(APP_BUNDLE): $(C_SRCS) $(OBJC_SRCS) Info.plist
	@echo "===> Creating App Bundle structure..."
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)/ui/assets
	@echo "===> Compiling Mach-O executable..."
	$(CC) $(ARCH_FLAGS) $(OBJCFLAGS) -I.. $(FRAMEWORKS) $(C_SRCS) $(OBJC_SRCS) -o $(MACOS_DIR)/$(APP_NAME)
	@echo "===> Compiling Watchdog daemon..."
	$(CC) $(ARCH_FLAGS) $(OBJCFLAGS) -I.. $(FRAMEWORKS) ../daemon/keyrox-watchdog.m ../keyrox_reset.m $(C_SRCS) -o $(MACOS_DIR)/keyrox-watchdog
	@echo "===> Copying Info.plist and Icons..."
	@cp Info.plist $(CONTENTS)/Info.plist
	@cp assets/Keyrox.icns $(RESOURCES_DIR)/Keyrox.icns
	@cp ../daemon/io.github.sl1mus.keyrox-watchdog.plist $(RESOURCES_DIR)/
	@echo "===> Copying WebKit UI resources..."
	@cp ui/index.html $(RESOURCES_DIR)/ui/
	@cp ui/style.css $(RESOURCES_DIR)/ui/
	@cp ui/app.js $(RESOURCES_DIR)/ui/
	@cp ui/keys.js $(RESOURCES_DIR)/ui/
	@cp -R assets/* $(RESOURCES_DIR)/ui/assets/
	@echo "===> Signing Bundle (ad-hoc)..."
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "===> Successfully built $(APP_BUNDLE)!"

package: universal
	@echo "===> Packaging DMG..."
	@mkdir -p $(BUILD_DIR)/dist
	@rm -f $(BUILD_DIR)/dist/$(APP_NAME)-macOS.dmg
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP_BUNDLE)" -ov -format UDZO "$(BUILD_DIR)/dist/$(APP_NAME)-macOS.dmg"
	@echo "===> DMG created at $(BUILD_DIR)/dist/$(APP_NAME)-macOS.dmg"

install: $(APP_BUNDLE)
	@echo "===> Installing to /Applications..."
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "===> Installed to /Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR)

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)

.PHONY: all clean install run universal package
