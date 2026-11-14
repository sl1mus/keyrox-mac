import SwiftUI

public struct KeyboardCanvasView: View {
    @ObservedObject var manager = KeyroxDeviceManager.shared
    @State private var hoveredKeyId: Int? = nil
    
    // Original keyboard background size
    private let baseWidth: CGFloat = 506
    private let baseHeight: CGFloat = 231
    private let scale: CGFloat = 1.16
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 8) {
            // Keyboard Frame with 87 keys
            ZStack(alignment: .topLeading) {
                // Background Image
                if let imagePath = Bundle.main.path(forResource: "img_keyboard_bg", ofType: "png", inDirectory: "assets") ??
                                   Bundle.main.path(forResource: "img_keyboard_bg", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable(resizingMode: .tile)
                        .frame(width: baseWidth, height: baseHeight)
                        .clipped()
                } else if let localImage = NSImage(contentsOfFile: "/Users/kistenev/Documents/keyrox-ctl/swift-gui/assets/img_keyboard_bg.png") {
                    Image(nsImage: localImage)
                        .resizable(resizingMode: .tile)
                        .frame(width: baseWidth, height: baseHeight)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.12))
                        .frame(width: baseWidth, height: baseHeight)
                }
                
                // 87 Keys
                ForEach(KeyroxLayout.keys) { key in
                    let isSelected = manager.selectedKeyIds.contains(key.id)
                    let isHovered = hoveredKeyId == key.id
                    let customColor = manager.keyColors[key.id]
                    
                    KeyCapView(
                        key: key,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        customColor: customColor
                    )
                    .offset(x: key.x, y: key.y)
                    .onHover { hovering in
                        hoveredKeyId = hovering ? key.id : nil
                    }
                    .onTapGesture {
                        if manager.selectedKeyIds.contains(key.id) {
                            manager.selectedKeyIds.remove(key.id)
                        } else {
                            manager.selectedKeyIds.insert(key.id)
                        }
                    }
                }
            }
            .frame(width: baseWidth, height: baseHeight)
            .scaleEffect(scale)
            .frame(width: baseWidth * scale, height: baseHeight * scale)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.6), radius: 10, y: 4)
            
            // Quick Selection Toolbar
            HStack(spacing: 8) {
                Text("Выбрано клавиш: \(manager.selectedKeyIds.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Все") {
                    manager.selectedKeyIds = Set(KeyroxLayout.keys.map { $0.id })
                }
                .buttonStyle(MicroButtonStyle())
                
                Button("WASD + Стрелки") {
                    let wasd = Set(["W", "A", "S", "D", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"])
                    manager.selectedKeyIds = Set(KeyroxLayout.keys.filter { wasd.contains($0.name) }.map { $0.id })
                }
                .buttonStyle(MicroButtonStyle())
                
                Button("F-ряд") {
                    manager.selectedKeyIds = Set(KeyroxLayout.keys.filter {
                        $0.name.hasPrefix("F") || ["Esc", "PrintScreen", "ScrollLock", "Pause"].contains($0.name)
                    }.map { $0.id })
                }
                .buttonStyle(MicroButtonStyle())
                
                Button("Цифры") {
                    let nums = Set(["~", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="])
                    manager.selectedKeyIds = Set(KeyroxLayout.keys.filter { nums.contains($0.name) }.map { $0.id })
                }
                .buttonStyle(MicroButtonStyle())
                
                Button("Снять выделение") {
                    manager.selectedKeyIds.removeAll()
                }
                .buttonStyle(MicroButtonStyle())
            }
            .frame(width: baseWidth * scale)
        }
    }
}

// MARK: - Single Keycap Component
struct KeyCapView: View {
    let key: KeyItem
    let isSelected: Bool
    let isHovered: Bool
    let customColor: Color?
    
    var body: some View {
        ZStack {
            // Background glow / fill
            if let color = customColor {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.35))
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color, lineWidth: 1.2)
                    .shadow(color: color.opacity(0.8), radius: 4)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green.opacity(0.35))
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.green, lineWidth: 1.5)
                    .shadow(color: Color.green.opacity(0.9), radius: 6)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.orange.opacity(0.3))
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.orange, lineWidth: 1.2)
                    .shadow(color: Color.orange.opacity(0.8), radius: 5)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            
            // Text Label
            Text(key.shortName)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isSelected || isHovered || customColor != nil ? .white : Color(white: 0.7))
                .shadow(color: .black, radius: 1, y: 1)
                .allowsHitTesting(false)
        }
        .frame(width: key.w, height: key.h)
        .contentShape(Rectangle())
        .help("\(key.name) (VK: \(key.vk), ID: \(key.keyId))")
    }
}

// MARK: - Micro Button Style
struct MicroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(configuration.isPressed ? Color(white: 0.22) : Color(white: 0.15))
            .foregroundColor(configuration.isPressed ? .white : Color(white: 0.85))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
