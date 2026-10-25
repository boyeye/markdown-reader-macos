import AppKit
import SwiftUI
import WebKit

@MainActor final class TestRunner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    var attempts = 0
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    func applicationDidFinishLaunching(_ note: Notification) {
        ReaderModel.shared.open(root.appendingPathComponent("Tests/sample.md"))
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1100,height: 760),styleMask: [.titled,.closable,.resizable],backing: .buffered,defer: false)
        window.contentView = NSHostingView(rootView: ReaderView());window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5,repeats: true) { _ in Task { @MainActor in self.check() } }
    }
    func finish(_ result: [String:Any]) {
        timer?.invalidate()
        let data = try! JSONSerialization.data(withJSONObject: result,options: [.prettyPrinted,.sortedKeys])
        try! data.write(to: root.appendingPathComponent("Tests/results.json"))
        NSApp.terminate(nil)
    }
    func check() {
        attempts += 1
        if attempts > 50 { finish(["passed":false,"error": ReaderModel.shared.error ?? "Timed out"]);return }
        guard let web = ReaderModel.shared.web, ReaderModel.shared.headings.count == 2 else { return }
        web.evaluateJavaScript("JSON.stringify({table:document.querySelectorAll('table tbody tr').length,highlight:document.querySelectorAll('code.hljs span').length,localImage:[...document.querySelectorAll('img')].some(i=>i.naturalWidth>0),remoteBlocked:document.querySelectorAll('.remote-image').length===1,injectionBlocked:window.injected!==true && !document.querySelector('main script') && !document.querySelector('main [onerror]'),anchor:document.querySelector('a').getAttribute('href')==='#section-1',tasks:document.querySelectorAll('input[type=checkbox]').length})") { value,error in
            guard let string=value as? String, let data=string.data(using:.utf8), let checks=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
            guard checks["localImage"] as? Bool == true else { return }
            self.timer?.invalidate()
            let config = WKFindConfiguration()
            web.find("中文阅读",configuration: config) { found in
                web.createPDF(configuration: WKPDFConfiguration()) { pdf in
                    var result=checks
                    result["find"]=found.matchFound
                    result["outline"]=ReaderModel.shared.headings.count
                    do { let bytes=try pdf.get();try bytes.write(to:self.root.appendingPathComponent("Tests/export.pdf"));result["pdf"]=bytes.starts(with:Data("%PDF".utf8)) } catch { result["pdf"]=false }
                    let expected = (checks["table"] as? Int == 1) && ((checks["highlight"] as? Int ?? 0)>0) && (checks["tasks"] as? Int == 2)
                    let bools=["localImage","remoteBlocked","injectionBlocked","anchor","find","pdf"]
                    result["passed"]=expected && bools.allSatisfy { result[$0] as? Bool == true }
                    self.finish(result)
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
