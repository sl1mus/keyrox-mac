import SwiftUI

public struct SettingsView: View {
    @ObservedObject var manager = KeyroxDeviceManager.shared
    @State private var showConfirmReset: Bool = false
    
    public init() {}
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Card: Factory Resets
            VStack(alignment: .leading, spacing: 10) {
                Text("СБРОС И ПАРАМЕТРЫ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                Text("Сброс параметров клавиатуры до исходных заводских значений:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Button("Сбросить все настройки к заводским") {
                        showConfirmReset = true
                    }
                    .buttonStyle(DangerButtonStyle())
                    .alert(isPresented: $showConfirmReset) {
                        Alert(
                            title: Text("Восстановление настроек"),
                            message: Text("Сбросить все профили, подсветку и макросы к исходным заводским настройкам?"),
                            primaryButton: .destructive(Text("Сбросить")) {
                                manager.restoreFactoryDefaults()
                            },
                            secondaryButton: .cancel(Text("Отмена"))
                        )
                    }
                    
                    Button("Сбросить световые эффекты") {
                        manager.setMode(.wave, direction: .left)
                        manager.setBrightness(4)
                        manager.setSpeed(2)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Сбросить пользовательский RGB") {
                        manager.clearCustomColors()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Сбросить записанные макросы") {
                        manager.resetMacro()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
            
            // Right Card: Hardware & Diagnostics
            VStack(alignment: .leading, spacing: 10) {
                Text("ИНФОРМАЦИЯ ОБ ОБОРУДОВАНИИ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                    .overlay(Divider().offset(y: 12), alignment: .bottom)
                
                VStack(spacing: 6) {
                    InfoRow(label: "Модель устройства:", value: "Red Square Keyrox TKL")
                    InfoRow(label: "Микроконтроллер (MCU):", value: "ITE Tech GK8911M")
                    InfoRow(label: "USB VID / PID:", value: "0x1A2C : 0x2511")
                    InfoRow(label: "Версия прошивки:", value: manager.firmwareVersion)
                    InfoRow(label: "Драйвер подсистемы:", value: "Apple IOKit (Native Swift)")
                    InfoRow(label: "Статус watchdog:", value: "Активен (juchen-keepalive)", valueColor: .green)
                    InfoRow(label: "Интерфейс связи:", value: "UsagePage 0xFF00, Usage 0x02")
                }
                
                Spacer()
                
                HStack {
                    Text("Статус:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(manager.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(6)
                .background(Color(white: 0.14))
                .cornerRadius(5)
            }
            .padding(12)
            .background(Color(white: 0.09).opacity(0.92))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 2)
        .overlay(Divider().offset(y: 10), alignment: .bottom)
    }
}
