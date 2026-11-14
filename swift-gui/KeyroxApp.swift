import SwiftUI
import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        let contentView = MainView()
            .frame(width: 1024, height: 650)
            
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1024, height: 650)
        
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 650),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Red Square Keyrox TKL"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.center()
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.sharingType = .readOnly
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
