import Foundation
import SwiftUI
import Combine

// MARK: - Native C Bindings via @_silgen_name
@_silgen_name("keyrox_open")
func c_keyrox_open() -> OpaquePointer?

@_silgen_name("keyrox_close")
func c_keyrox_close(_ dev: OpaquePointer?)

@_silgen_name("keyrox_set_mode")
func c_keyrox_set_mode(_ dev: OpaquePointer?, _ mode: UInt32, _ dir: UInt32) -> Int32

@_silgen_name("keyrox_set_brightness")
func c_keyrox_set_brightness(_ dev: OpaquePointer?, _ level: UInt8) -> Int32

@_silgen_name("keyrox_set_speed")
func c_keyrox_set_speed(_ dev: OpaquePointer?, _ speed: UInt8) -> Int32

@_silgen_name("keyrox_set_color")
func c_keyrox_set_color(_ dev: OpaquePointer?, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int32

@_silgen_name("keyrox_set_key_color")
func c_keyrox_set_key_color(_ dev: OpaquePointer?, _ keyIndex: UInt8, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int32

@_silgen_name("keyrox_set_profile")
func c_keyrox_set_profile(_ dev: OpaquePointer?, _ profile: UInt8) -> Int32

@_silgen_name("keyrox_save_settings")
func c_keyrox_save_settings(_ dev: OpaquePointer?) -> Int32

@_silgen_name("keyrox_get_status")
func c_keyrox_get_status(_ dev: OpaquePointer?, _ outMode: UnsafeMutablePointer<UInt32>?, _ outBright: UnsafeMutablePointer<UInt8>?, _ outSpeed: UnsafeMutablePointer<UInt8>?, _ outProfile: UnsafeMutablePointer<UInt8>?, _ fwVersion: UnsafeMutablePointer<CChar>?, _ fwVerLen: Int) -> Int32

@_silgen_name("keyrox_set_key_remap")
func c_keyrox_set_key_remap(_ dev: OpaquePointer?, _ keyIndex: UInt8, _ targetCode: UInt16) -> Int32

@_silgen_name("keyrox_reset_remap")
func c_keyrox_reset_remap(_ dev: OpaquePointer?) -> Int32

@_silgen_name("keyrox_reset_macro")
func c_keyrox_reset_macro(_ dev: OpaquePointer?) -> Int32

// MARK: - Device Manager
public class KeyroxDeviceManager: ObservableObject {
    public static let shared = KeyroxDeviceManager()
    
    // Published State
    @Published public var isConnected: Bool = false
    @Published public var currentProfile: Int = 0 // 0..3
    @Published public var currentMode: LightingMode = .wave
    @Published public var currentDirection: EffectDirection = .left
    @Published public var currentBrightness: Int = 4 // 0..4
    @Published public var currentSpeed: Int = 2      // 0..4
    @Published public var customSlot: Int = 1        // 1..5
    @Published public var fgColor: Color = Color.red
    @Published public var bgColor: Color = Color.blue
    @Published public var firmwareVersion: String = "GK8911M-DP-PID2511-104K_V0045"
    @Published public var selectedKeyIds: Set<Int> = []
    @Published public var keyColors: [Int: Color] = [:]
    @Published public var statusMessage: String = "Готов к работе"
    @Published public var isSaving: Bool = false
    
    private var dev: OpaquePointer? = nil
    private let hidQueue = DispatchQueue(label: "org.redsquare.keyrox.swift.hid", qos: .userInitiated)
    private var timer: Timer? = nil
    
    private init() {
        startPolling()
    }
    
    deinit {
        timer?.invalidate()
        if let d = dev {
            c_keyrox_close(d)
        }
    }
    
    // MARK: - Lifecycle & Polling
    
    public func startPolling() {
        checkStatus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }
    
    public func checkStatus() {
        hidQueue.async {
            if self.dev == nil {
                self.dev = c_keyrox_open()
            }
            guard let d = self.dev else {
                DispatchQueue.main.async {
                    if self.isConnected {
                        self.isConnected = false
                    }
                }
                return
            }
            
            var mode: UInt32 = 0
            var bright: UInt8 = 0
            var speed: UInt8 = 0
            var profile: UInt8 = 0
            var fwBuf = [CChar](repeating: 0, count: 64)
            
            let ret = c_keyrox_get_status(d, &mode, &bright, &speed, &profile, &fwBuf, fwBuf.count)
            DispatchQueue.main.async {
                if ret == 0 {
                    self.isConnected = true
                    let fw = String(cString: fwBuf)
                    if !fw.isEmpty {
                        self.firmwareVersion = fw
                    }
                    if let m = LightingMode(rawValue: Int(mode)) {
                        self.currentMode = m
                    }
                    self.currentBrightness = Int(bright)
                    self.currentSpeed = Int(speed)
                    self.currentProfile = Int(profile)
                } else {
                    c_keyrox_close(d)
                    self.dev = nil
                    self.isConnected = false
                }
            }
        }
    }
    
    private func ensureDev() -> OpaquePointer? {
        if dev == nil {
            dev = c_keyrox_open()
        }
        return dev
    }
    
    // MARK: - Lighting Commands
    
    public func setMode(_ mode: LightingMode, direction: EffectDirection = .left) {
        self.currentMode = mode
        self.currentDirection = direction
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_mode(d, UInt32(mode.rawValue), UInt32(direction.rawValue))
        }
    }
    
    public func setBrightness(_ val: Int) {
        self.currentBrightness = max(0, min(4, val))
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_brightness(d, UInt8(self.currentBrightness))
        }
    }
    
    public func setSpeed(_ val: Int) {
        self.currentSpeed = max(0, min(4, val))
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_speed(d, UInt8(self.currentSpeed))
        }
    }
    
    public func setProfile(_ p: Int) {
        self.currentProfile = max(0, min(3, p))
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_profile(d, UInt8(self.currentProfile))
        }
    }
    
    public func setCustomSlot(_ slot: Int) {
        self.customSlot = max(1, min(5, slot))
        setMode(.custom, direction: .left)
    }
    
    // MARK: - Color Commands
    
    public func applyColorToAll(color: Color) {
        let (r, g, b) = colorToRGB(color)
        for k in KeyroxLayout.keys {
            keyColors[k.id] = color
        }
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_color(d, r, g, b)
        }
    }
    
    public func applyColorToSelected(color: Color) {
        let (r, g, b) = colorToRGB(color)
        let keys = Array(selectedKeyIds)
        for kId in keys {
            keyColors[kId] = color
        }
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            for kId in keys {
                _ = c_keyrox_set_key_color(d, UInt8(kId), r, g, b)
                usleep(1500)
            }
        }
    }
    
    public func setKeyColor(keyId: Int, color: Color) {
        keyColors[keyId] = color
        let (r, g, b) = colorToRGB(color)
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_key_color(d, UInt8(keyId), r, g, b)
        }
    }
    
    public func clearCustomColors() {
        keyColors.removeAll()
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_color(d, 0, 0, 0)
        }
    }
    
    // MARK: - Key Remapping Commands
    
    public func remapKey(keyId: Int, targetCode: Int) {
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_key_remap(d, UInt8(keyId), UInt16(targetCode))
            DispatchQueue.main.async {
                self.statusMessage = "Клавиша #\(keyId) переназначена на код 0x\(String(format: "%04X", targetCode))"
            }
        }
    }
    
    public func resetRemap() {
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_reset_remap(d)
            DispatchQueue.main.async {
                self.statusMessage = "Назначения клавиш сброшены к стандартным"
            }
        }
    }
    
    public func resetMacro() {
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_reset_macro(d)
            DispatchQueue.main.async {
                self.statusMessage = "Макросы клавиатуры очищены"
            }
        }
    }
    
    // MARK: - Flash & Settings
    
    public func saveToFlash() {
        isSaving = true
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_save_settings(d)
            DispatchQueue.main.async {
                self.isSaving = false
                self.statusMessage = "Настройки успешно сохранены во Flash-память"
            }
        }
    }
    
    public func turnOff() {
        setMode(.off)
    }
    
    public func turnOn() {
        setMode(.wave, direction: .left)
        setBrightness(4)
    }
    
    public func restoreFactoryDefaults() {
        hidQueue.async {
            guard let d = self.ensureDev() else { return }
            _ = c_keyrox_set_profile(d, 0)
            _ = c_keyrox_set_mode(d, 1, 0)
            _ = c_keyrox_set_brightness(d, 4)
            _ = c_keyrox_set_speed(d, 2)
            _ = c_keyrox_reset_remap(d)
            _ = c_keyrox_reset_macro(d)
            _ = c_keyrox_save_settings(d)
            DispatchQueue.main.async {
                self.currentProfile = 0
                self.currentMode = .wave
                self.currentBrightness = 4
                self.currentSpeed = 2
                self.keyColors.removeAll()
                self.statusMessage = "Клавиатура сброшена до заводских настроек"
            }
        }
    }
    
    // MARK: - Helpers
    
    private func colorToRGB(_ color: Color) -> (UInt8, UInt8, UInt8) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        let r = UInt8(max(0, min(255, nsColor.redComponent * 255.0)))
        let g = UInt8(max(0, min(255, nsColor.greenComponent * 255.0)))
        let b = UInt8(max(0, min(255, nsColor.blueComponent * 255.0)))
        return (r, g, b)
    }
}
