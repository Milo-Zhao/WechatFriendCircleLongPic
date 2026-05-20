import SwiftUI
import AppKit

@main
struct WechatLongPicApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let icon = IconGenerator.makeIcon() {
            NSApplication.shared.applicationIconImage = icon
        }
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("WeChat Long Pic") {
            ContentView()
        }
    }
}
