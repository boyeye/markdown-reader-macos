import SwiftUI
import WebKit

struct Preview: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.loadHTMLString(#"<html><body style="font:18px -apple-system;padding:32px"><h1>Markdown 查看器</h1><p>SwiftUI 与 WebKit 编译验证成功。</p></body></html>"#, baseURL: nil)
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else {
            NSLog("AppIcon could not be loaded")
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("Markdown 查看器 · 工具链验证") {
            Preview().frame(minWidth: 600, minHeight: 400)
        }
    }
}
