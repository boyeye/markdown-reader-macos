import AppKit
import SwiftUI
import WebKit

@MainActor final class TestRunner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    var attempts = 0
    let model = ReaderModel()
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    func applicationDidFinishLaunching(_ note: Notification) {
        model.open(root.appendingPathComponent("Tests/sample.md"))
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1100,height: 760),styleMask: [.titled,.closable,.resizable],backing: .buffered,defer: false)
        window.contentView = NSHostingView(rootView: ReaderView(model: model));window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5,repeats: true) { _ in Task { @MainActor in self.check() } }
    }
    func finish(_ result: [String:Any]) {
        timer?.invalidate()
        let data = try! JSONSerialization.data(withJSONObject: result,options: [.prettyPrinted,.sortedKeys])
        try! data.write(to: root.appendingPathComponent("Tests/results.json"))
        NSApp.terminate(nil)
    }
    // No SwiftUI scene runs here, so new-tab requests stay queued in WindowRouter.pending.
    func checkTabs() -> Bool {
        let attached = WindowRouter.models.allObjects.contains { $0 === model } && model.window === window
        WindowRouter.open(root.appendingPathComponent("Tests/sample.md"), from: model)
        let deduped = WindowRouter.pending.isEmpty && model.error == nil
        WindowRouter.open(root.appendingPathComponent("Tests/second.md"), from: model)
        let queued = WindowRouter.pending.count == 1 && WindowRouter.pending.first?.url?.lastPathComponent == "second.md" && WindowRouter.pending.first?.tabOf === window
        WindowRouter.open(root.appendingPathComponent("Tests/local.png"), from: model)
        let rejected = WindowRouter.pending.count == 1 && model.error != nil
        model.error = nil; WindowRouter.pending.removeAll()
        return attached && deduped && queued && rejected && model.fileURL?.lastPathComponent == "sample.md"
    }
    // Writes light and dark renderings to .build/ for visual review of the stylesheet.
    func snapshots(_ web: WKWebView, done: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true); window.orderFrontRegardless()
        func shoot(_ themes: [String]) {
            guard let theme = themes.first else { done(); return }
            web.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
            web.callAsyncJavaScript("window.setAppearance(theme,16);window.scrollTo(0,0);", arguments: ["theme": theme], in: nil, in: .page) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    web.takeSnapshot(with: nil) { image, _ in
                        if let tiff = image?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                            try? png.write(to: self.root.appendingPathComponent(".build/snapshot-\(theme).png"))
                        }
                        shoot(Array(themes.dropFirst()))
                    }
                }
            }
        }
        shoot(["light", "dark"])
    }
    func check() {
        attempts += 1
        if attempts > 50 { finish(["passed":false,"error": model.error ?? "Timed out"]);return }
        guard let web = model.web, model.headings.count == 2 else { return }
        web.evaluateJavaScript("JSON.stringify({table:document.querySelectorAll('table tbody tr').length,highlight:document.querySelectorAll('code.hljs span').length,localImage:[...document.querySelectorAll('img')].some(i=>i.naturalWidth>0),remoteBlocked:document.querySelectorAll('.remote-image').length===1,injectionBlocked:window.injected!==true && !document.querySelector('main script') && !document.querySelector('main [onerror]'),anchor:document.querySelector('a').getAttribute('href')==='#section-1',tasks:document.querySelectorAll('input[type=checkbox]').length})") { value,error in
            guard let string=value as? String, let data=string.data(using:.utf8), let checks=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
            guard checks["localImage"] as? Bool == true else { return }
            self.timer?.invalidate()
            let config = WKFindConfiguration()
            web.find("中文阅读",configuration: config) { found in
                web.createPDF(configuration: WKPDFConfiguration()) { pdf in
                    var result=checks
                    result["find"]=found.matchFound
                    result["outline"]=self.model.headings.count
                    result["tabs"]=self.checkTabs()
                    do { let bytes=try pdf.get();try bytes.write(to:self.root.appendingPathComponent("Tests/export.pdf"));result["pdf"]=bytes.starts(with:Data("%PDF".utf8)) } catch { result["pdf"]=false }
                    let expected = (checks["table"] as? Int == 1) && ((checks["highlight"] as? Int ?? 0)>0) && (checks["tasks"] as? Int == 2)
                    let bools=["localImage","remoteBlocked","injectionBlocked","anchor","find","pdf","tabs"]
                    result["passed"]=expected && bools.allSatisfy { result[$0] as? Bool == true }
                    self.snapshots(web) { self.finish(result) }
                }
            }
        }
    }
}
@main struct Harness {
    static func main() {
        let application=NSApplication.shared
        let delegate=TestRunner();application.delegate=delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
