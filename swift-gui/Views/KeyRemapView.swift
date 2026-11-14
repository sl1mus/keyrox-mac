import SwiftUI

public struct KeyRemapView: View {
    @ObservedObject var manager = KeyroxDeviceManager.shared
    
    @State private var remapCategory: Int = 0 // 0: Single, 1: Media, 2: Shortcuts, 3: Macro, 4: Disable
    @State private var selectedTargetVK: Int = 65 // 'A'
    @State private var selectedMediaAction: MediaKeyAction = .mute
    @State private var selectedShortcut: ShortcutAction = .copy
    @State private var macroRepeatCount: Int = 1
    @State private var macroDelayMs: Int = 50
    @State private var macroDelayType: Int = 0 // 0: Fixed, 1: Real, 2: None
    
    // Available single keys
    struct SingleKeyOption: Identifiable, Hashable {
        let name: String
        let vk: Int
        var id: Int { vk }
    }
    
    private let commonSingleKeys: [SingleKeyOption] = [
        SingleKeyOption(name: "A", vk: 65), SingleKeyOption(name: "B", vk: 66), SingleKeyOption(name: "C", vk: 67), SingleKeyOption(name: "D", vk: 68),
        SingleKeyOption(name: "E", vk: 69), SingleKeyOption(name: "F", vk: 70), SingleKeyOption(name: "G", vk: 71), SingleKeyOption(name: "H", vk: 72),
        SingleKeyOption(name: "I", vk: 73), SingleKeyOption(name: "J", vk: 74), SingleKeyOption(name: "K", vk: 75), SingleKeyOption(name: "L", vk: 76),
        SingleKeyOption(name: "M", vk: 77), SingleKeyOption(name: "N", vk: 78), SingleKeyOption(name: "O", vk: 79), SingleKeyOption(name: "P", vk: 80),
        SingleKeyOption(name: "Q", vk: 81), SingleKeyOption(name: "R", vk: 82), SingleKeyOption(name: "S", vk: 83), SingleKeyOption(name: "T", vk: 84),
        SingleKeyOption(name: "U", vk: 85), SingleKeyOption(name: "V", vk: 86), SingleKeyOption(name: "W", vk: 87), SingleKeyOption(name: "X", vk: 88),
        SingleKeyOption(name: "Y", vk: 89), SingleKeyOption(name: "Z", vk: 90),
        SingleKeyOption(name: "0", vk: 48), SingleKeyOption(name: "1", vk: 49), SingleKeyOption(name: "2", vk: 50), SingleKeyOption(name: "3", vk: 51),
        SingleKeyOption(name: "4", vk: 52), SingleKeyOption(name: "5", vk: 53), SingleKeyOption(name: "6", vk: 54), SingleKeyOption(name: "7", vk: 55),
        SingleKeyOption(name: "8", vk: 56), SingleKeyOption(name: "9", vk: 57),
        SingleKeyOption(name: "F1", vk: 112), SingleKeyOption(name: "F2", vk: 113), SingleKeyOption(name: "F3", vk: 114), SingleKeyOption(name: "F4", vk: 115),
        SingleKeyOption(name: "F5", vk: 116), SingleKeyOption(name: "F6", vk: 117), SingleKeyOption(name: "F7", vk: 118), SingleKeyOption(name: "F8", vk: 119),
        SingleKeyOption(name: "F9", vk: 120), SingleKeyOption(name: "F10", vk: 121), SingleKeyOption(name: "F11", vk: 122), SingleKeyOption(name: "F12", vk: 123),
        SingleKeyOption(name: "Esc", vk: 27), SingleKeyOption(name: "Space", vk: 32), SingleKeyOption(name: "Enter", vk: 13), SingleKeyOption(name: "Backspace", vk: 8),
        SingleKeyOption(name: "Tab", vk: 9), SingleKeyOption(name: "Shift", vk: 160), SingleKeyOption(name: "Ctrl", vk: 162), SingleKeyOption(name: "Alt", vk: 164),
        SingleKeyOption(name: "Win/Cmd", vk: 91)
    ]
    
    public init() {}
    
    private var selectedKey: KeyItem? {
        guard let firstId = manager.selectedKeyIds.first else { return nil }
        return KeyroxLayout.keys.first(where: { $0.id == firstId })
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Card: Key Selection & Action Mode
            VStack(alignment: .leading, spacing: 10) {
                Text("НАЗНАЧЕНИЕ КЛАВИШ (REMAP & MACRO)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                // Target Key Indicator
                if let k = selectedKey {
                    HStack {
                        Text("Выбранная клавиша:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(k.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                        Text("(VK: \(k.vk), Index: \(k.id))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .background(Color(white: 0.14))
                    .cornerRadius(5)
                } else {
                    Text("⚠️ Кликните по клавише на клавиатуре выше, чтобы переназначить её.")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                        .padding(6)
                }
                
                // Mode Tabs
                Picker("", selection: $remapCategory) {
                    Text("Клавиша").tag(0)
                    Text("Медиа").tag(1)
                    Text("Сочетание").tag(2)
                    Text("Макрос").tag(3)
                    Text("Отключить").tag(4)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Detail Form based on selected tab
                Group {
                    switch remapCategory {
                    case 0:
                        // Single Key Remap
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Переназначить на клавишу:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $selectedTargetVK) {
                                ForEach(commonSingleKeys) { item in
                                    Text(item.name).tag(item.vk)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                    case 1:
                        // Media Key Remap
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Мультимедийное действие:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $selectedMediaAction) {
                                ForEach(MediaKeyAction.allCases) { m in
                                    Text(m.titleRu).tag(m)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                    case 2:
                        // Shortcuts Remap
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Горячее сочетание:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $selectedShortcut) {
                                ForEach(ShortcutAction.allCases) { s in
                                    Text(s.rawValue).tag(s)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                    case 3:
                        // Macro settings
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Повторов:")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Stepper("\(macroRepeatCount)", value: $macroRepeatCount, in: 1...99)
                                    .font(.system(size: 11))
                            }
                            
                            Picker("Задержка:", selection: $macroDelayType) {
                                Text("Фиксированная").tag(0)
                                Text("Реальная").tag(1)
                                Text("Без задержки").tag(2)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            if macroDelayType == 0 {
                                HStack {
                                    Text("Задержка: \(macroDelayMs) ms")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Slider(value: Binding(
                                        get: { Double(macroDelayMs) },
                                        set: { macroDelayMs = Int($0) }
                                    ), in: 5...500, step: 5)
                                }
                            }
                        }
                        
                    case 4:
                        // Disable Key
                        Text("Клавиша будет отключена в контроллере клавиатуры (нажатия игнорируются).")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                    default:
                        EmptyView()
                    }
                }
                
                Spacer(minLength: 0)
                
                // Action Buttons
                HStack(spacing: 8) {
                    Button("Применить назначение") {
                        applyRemap()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedKey == nil)
                    
                    Button("Сбросить все переназначения") {
                        manager.resetRemap()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
            
            // Right Card: Description & Remap Table
            VStack(alignment: .leading, spacing: 10) {
                Text("ИНФОРМАЦИЯ О НАЗНАЧЕНИИ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Функция Remap записывает таблицу сопоставления скан-кодов напрямую в контроллер клавиатуры ITE GK8911M.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• Переназначения работают аппаратно — даже без запущенного приложения на любом компьютере Mac, Windows или Linux.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• Поддерживается привязка к текущему активному профилю (P1 .. P4).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(manager.isSaving ? "Сохранение..." : "Сохранить профиль во Flash") {
                    manager.saveToFlash()
                }
                .buttonStyle(SuccessButtonStyle())
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
    
    private func applyRemap() {
        guard let k = selectedKey else { return }
        switch remapCategory {
        case 0:
            manager.remapKey(keyId: k.id, targetCode: selectedTargetVK)
        case 1:
            manager.remapKey(keyId: k.id, targetCode: selectedMediaAction.rawValue)
        case 2:
            manager.remapKey(keyId: k.id, targetCode: 0xE000)
        case 3:
            manager.remapKey(keyId: k.id, targetCode: 0xF000)
        case 4:
            manager.remapKey(keyId: k.id, targetCode: 0x0000)
        default:
            break
        }
    }
}
