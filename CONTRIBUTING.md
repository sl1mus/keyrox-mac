# Contributing to Keyrox Control for macOS ⌨️

Thank you for your interest in contributing to **keyrox-mac**! We welcome community contributions, hardware test reports, bug fixes, and feature additions.

---

## 🛠️ Development Environment

### Prerequisites
- macOS 12 Monterey or newer
- Xcode Command Line Tools (`xcode-select --install`)
- `clang`, `make`, `codesign`, `hdiutil`

### Building from Source

```bash
# Build CLI utility (Universal Binary: x86_64 + arm64)
make universal

# Build macOS GUI App (.app bundle)
make -C gui universal

# Build release DMG package
make -C gui package
```

---

## 🧪 Testing Other Keyboard Models

While this project was developed and verified on the **Red Square Keyrox TKL** (GK8911M microcontroller, USB VID `0x1A2C`, PID `0x2511`), many related keyboards from Red Square and other OEM brands use similar EVision / Juchen microcontrollers:
- Red Square Keyrox Classic
- Red Square Keyrox 60%
- Red Square Redeemer / Redeemer v2

### How to Collect Diagnostic Info:
1. Connect your keyboard.
2. Run USB device inspection:
   ```bash
   system_profiler SPUSBDataType | grep -A 10 "1a2c"
   ```
3. Test communication with the CLI:
   ```bash
   ./keyrox-ctl status
   ```
4. If your keyboard has a different Product ID (PID) or report layout, open an Issue or submit a Pull Request with your device's descriptors.

---

## 📐 Architecture Guidelines

1. **Lightweight & Native:** 
   - Core protocol code is written in clean **C99** (`keyrox_proto.c`, `keyrox_hid.c`).
   - The GUI uses **native Cocoa / AppKit and WebKit** (~2.8 MB bundle, zero Electron / Node.js runtime).
   - Keep binary dependencies to zero.
2. **Safety First:**
   - Always validate checksums before sending reports (`keyrox_calc_checksum`).
   - Hardware bus resets (`keyrox_reset.m`) should only be triggered on demand or upon system display wake events.

---

## 📬 Submitting a Pull Request

1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-cool-feature
   ```
2. Test your changes locally (`make universal` and `make -C gui universal`).
3. Commit with descriptive messages (e.g. `feat: add support for PID 0x2512`).
4. Push to your fork and submit a Pull Request.
