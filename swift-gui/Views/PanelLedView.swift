import SwiftUI

public struct PanelLedView: View {
    @ObservedObject var manager = KeyroxDeviceManager.shared
    
    // Quick Color Swatches
    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan,
        .blue, .purple, Color(red: 1.0, green: 0.0, blue: 0.8), .white, .black
    ]
    
    public init() {}
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Card: Modes, Direction, Sliders
            VStack(alignment: .leading, spacing: 10) {
                Text("ЭФФЕКТЫ ПОДСВЕТКИ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                // Mode Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Режим свечения:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { manager.currentMode },
                        set: { newMode in
                            manager.setMode(newMode, direction: manager.currentDirection)
                        }
                    )) {
                        ForEach(LightingMode.allCases) { m in
                            Text(m.titleRu).tag(m)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Direction Picker (if mode supports direction)
                if manager.currentMode.supportsDirection {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Направление эффекта:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: Binding(
                            get: { manager.currentDirection },
                            set: { newDir in
                                manager.setMode(manager.currentMode, direction: newDir)
                            }
                        )) {
                            ForEach(EffectDirection.allCases) { d in
                                Text(d.titleRu).tag(d)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                // Custom Slot Picker (if Custom mode)
                if manager.currentMode == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Слот кастомизации (Custom Slot):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: Binding(
                            get: { manager.customSlot },
                            set: { manager.setCustomSlot($0) }
                        )) {
                            ForEach(1...5, id: \.self) { slot in
                                Text("Custom \(slot)").tag(slot)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                // Brightness Slider (0..4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Яркость (Brightness):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(manager.currentBrightness) / 4")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(manager.currentBrightness) },
                            set: { manager.setBrightness(Int($0)) }
                        ),
                        in: 0...4,
                        step: 1
                    )
                    .accentColor(.orange)
                }
                
                // Speed Slider (0..4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Скорость (Speed):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(manager.currentSpeed) / 4")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(manager.currentSpeed) },
                            set: { manager.setSpeed(Int($0)) }
                        ),
                        in: 0...4,
                        step: 1
                    )
                    .accentColor(.orange)
                }
                
                Spacer(minLength: 0)
                
                // Power Quick Buttons
                HStack(spacing: 8) {
                    Button("Выключить LED") {
                        manager.turnOff()
                    }
                    .buttonStyle(DangerButtonStyle())
                    
                    Button("Включить Wave") {
                        manager.turnOn()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
            
            // Right Card: Palette & Colors
            VStack(alignment: .leading, spacing: 10) {
                Text("ПАЛИТРА И ЦВЕТА")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                // Color Pickers (Foreground & Background)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Цвет эффекта (FG):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        ColorPicker("", selection: $manager.fgColor)
                            .labelsHidden()
                            .frame(height: 24)
                    }
                    
                    if manager.currentMode.supportsTwoColors {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Цвет фона (BG):")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            ColorPicker("", selection: $manager.bgColor)
                                .labelsHidden()
                                .frame(height: 24)
                        }
                    }
                }
                
                // Preset Color Swatches
                VStack(alignment: .leading, spacing: 4) {
                    Text("Быстрые оттенки:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        ForEach(presetColors, id: \.self) { c in
                            Circle()
                                .fill(c)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                .shadow(color: c.opacity(0.5), radius: 3)
                                .onTapGesture {
                                    manager.fgColor = c
                                }
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                // Action Buttons
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Залить всю клавиатуру") {
                            manager.applyColorToAll(color: manager.fgColor)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        
                        Button("Залить выбранные клавиши") {
                            manager.applyColorToSelected(color: manager.fgColor)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Button(manager.isSaving ? "Сохранение..." : "Сохранить в память (Flash)") {
                        manager.saveToFlash()
                    }
                    .buttonStyle(SuccessButtonStyle())
                }
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}

// MARK: - Reusable Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color.orange, Color.orange.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            .foregroundColor(.black)
            .cornerRadius(5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.16))
            .foregroundColor(.white)
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            .foregroundColor(.black)
            .cornerRadius(5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.2))
            .foregroundColor(.red)
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.4), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
