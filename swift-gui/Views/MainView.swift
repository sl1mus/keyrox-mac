import SwiftUI

public enum AppTab: Int, CaseIterable, Identifiable {
    case panelLed = 0
    case keyRemap = 1
    case customMatrix = 2
    case settings = 3
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .panelLed: return "Panel LED"
        case .keyRemap: return "Key Remap & Macro"
        case .customMatrix: return "Custom Matrix"
        case .settings: return "Settings"
        }
    }
    
    public var iconName: String {
        switch self {
        case .panelLed: return "sun.max.fill"
        case .keyRemap: return "keyboard.fill"
        case .customMatrix: return "square.grid.3x3.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MainView: View {
    @ObservedObject var manager = KeyroxDeviceManager.shared
    @State private var currentTab: AppTab = .panelLed
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Authentic Background
            if let bgPath = Bundle.main.path(forResource: "bg", ofType: "png", inDirectory: "assets") ??
                            Bundle.main.path(forResource: "bg", ofType: "png"),
               let nsImage = NSImage(contentsOfFile: bgPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let localBg = NSImage(contentsOfFile: "/Users/kistenev/Documents/keyrox-ctl/swift-gui/assets/bg.png") {
                Image(nsImage: localBg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.08)
            }
            
            // Dark Overlay
            Color.black.opacity(0.82)
            
            // App Layout
            VStack(spacing: 0) {
                // 1. Header Bar (32px)
                headerBar
                
                // 2. Navigation Tabs & Profile Switcher (40px)
                navBar
                
                // 3. Interactive Keyboard Canvas
                VStack(spacing: 0) {
                    KeyboardCanvasView()
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.4))
                .overlay(Divider(), alignment: .bottom)
                
                // 4. Tab Content Panels
                VStack {
                    switch currentTab {
                    case .panelLed:
                        PanelLedView()
                    case .keyRemap:
                        KeyRemapView()
                    case .customMatrix:
                        CustomMatrixView()
                    case .settings:
                        SettingsView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 5. Statusbar (24px)
                statusBar
            }
        }
        .frame(width: 1024, height: 650)
        .edgesIgnoringSafeArea(.all)
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 8) {
            // Logo
            if let logoPath = Bundle.main.path(forResource: "logo", ofType: "png", inDirectory: "assets") ??
                              Bundle.main.path(forResource: "logo", ofType: "png"),
               let nsLogo = NSImage(contentsOfFile: logoPath) {
                Image(nsImage: nsLogo)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else if let localLogo = NSImage(contentsOfFile: "/Users/kistenev/Documents/keyrox-ctl/swift-gui/assets/logo.png") {
                Image(nsImage: localLogo)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            Text("RED SQUARE KEYROX TKL")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .tracking(0.8)
            
            Text("macOS Native Swift Edition")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.leading, 6)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 12)
                        .padding(.trailing, 4),
                    alignment: .leading
                )
            
            Spacer()
            
            // Window Controls (Minimize / Close)
            Button(action: {
                NSApp.keyWindow?.miniaturize(nil)
            }) {
                Text("—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.7))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Text("✕")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.7))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color(white: 0.07).opacity(0.98))
        .overlay(Divider(), alignment: .bottom)
    }
    
    // MARK: - Navigation Bar
    private var navBar: some View {
        HStack {
            // Tabs
            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { tab in
                    Button(action: {
                        currentTab = tab
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11))
                            Text(tab.title)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(currentTab == tab ?
                            AnyView(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)) :
                            AnyView(Color.clear)
                        )
                        .foregroundColor(currentTab == tab ? .white : Color(white: 0.65))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(currentTab == tab ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
            
            // Profile Switcher (P1..P4)
            HStack(spacing: 6) {
                Text("ПРОФИЛЬ:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { p in
                        Button(action: {
                            manager.setProfile(p)
                        }) {
                            Text("P\(p + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(manager.currentProfile == p ? Color.orange : Color(white: 0.12))
                                .foregroundColor(manager.currentProfile == p ? .black : Color(white: 0.75))
                                .cornerRadius(3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(2)
                .background(Color(white: 0.08))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color(white: 0.09).opacity(0.95))
        .overlay(Divider(), alignment: .bottom)
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            // Connection Dot & Status
            HStack(spacing: 6) {
                Circle()
                    .fill(manager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (manager.isConnected ? Color.green : Color.red).opacity(0.8), radius: 4)
                
                Text(manager.isConnected ?
                     "Подключено: Red Square Keyrox TKL (FW: \(manager.firmwareVersion))" :
                     "Отключено: Подключите клавиатуру Red Square по USB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(manager.isConnected ? Color(white: 0.85) : .red)
            }
            
            Spacer()
            
            // Official Website Link
            Button(action: {
                if let url = URL(string: "http://red-square.org/") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("red-square.org")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(white: 0.06))
        .overlay(Divider(), alignment: .top)
    }
}
