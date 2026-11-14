import SwiftUI

public struct CustomMatrixView: View {
    @ObservedObject var manager = KeyroxDeviceManager.shared
    @State private var paintColor: Color = .red
    
    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan,
        .blue, .purple, Color(red: 1.0, green: 0.0, blue: 0.8), .white, .black
    ]
    
    public init() {}
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Card: Slot & Paint Controls
            VStack(alignment: .leading, spacing: 10) {
                Text("ПОКЛАВИШНЫЙ RGB (CUSTOM MATRIX)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                // Custom Slot Selector (Custom 1..5)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Слот кастомизации (Custom 1..5):")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { manager.customSlot },
                        set: { manager.setCustomSlot($0) }
                    )) {
                        ForEach(1...5, id: \.self) { slot in
                            Text("Слот \(slot)").tag(slot)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // Color Picker
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Цвет кисти:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        ColorPicker("", selection: $paintColor)
                            .labelsHidden()
                            .frame(height: 24)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Быстрые пресеты:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 5) {
                            ForEach(presetColors, id: \.self) { c in
                                Circle()
                                    .fill(c)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                    .onTapGesture {
                                        paintColor = c
                                    }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                // Actions
                HStack(spacing: 8) {
                    Button("Залить выбранные") {
                        manager.applyColorToSelected(color: paintColor)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(manager.selectedKeyIds.isEmpty)
                    
                    Button("Очистить матрицу") {
                        manager.clearCustomColors()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
            
            // Right Card: Information & Save
            VStack(alignment: .leading, spacing: 10) {
                Text("ИНСТРУКЦИЯ И СОХРАНЕНИЕ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Выберите одну или несколько клавиш на виртуальной клавиатуре выше (кликните по нужным кнопкам или используйте быстрые фильтры 'WASD', 'F-ряд', 'Цифры').")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• Выберите цвет в палитре слева и нажмите кнопку «Залить выбранные». Клавиши на физической клавиатуре окрасятся индивидуально.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• Нажмите кнопку «Сохранить матрицу во Flash», чтобы профиль сохранился в постоянную память клавиатуры.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(manager.isSaving ? "Сохранение..." : "Сохранить матрицу во Flash") {
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
}
