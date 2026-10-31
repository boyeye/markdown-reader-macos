// Renders an SVG to a PNG with a transparent background using WebKit (qlmanage fills transparency with white).
// Usage: svg2png <in.svg> <out.png>. The output is 1024 pt; on a Retina display it is 2048 px, so make_icon.py downsamples it.
import AppKit
import WebKit
let args = CommandLine.arguments; let svg = try! String(contentsOfFile: args[1], encoding: .utf8); let out = URL(fileURLWithPath: args[2])
final class Delegate: NSObject, WKNavigationDelegate {
    func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let config = WKSnapshotConfiguration(); config.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024); config.snapshotWidth = 1024
            web.takeSnapshot(with: config) { image, error in
                guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("snapshot failed", error as Any); exit(1) }
                let rep = NSBitmapImageRep(cgImage: cg); rep.size = NSSize(width: 1024, height: 1024)
                try! rep.representation(using: .png, properties: [:])!.write(to: out); exit(0)
            }
        }
    }
}
let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), styleMask: [.borderless], backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024)); web.setValue(false, forKey: "drawsBackground")
window.contentView = web
let delegate = Delegate(); web.navigationDelegate = delegate
web.loadHTMLString("<html><body style='margin:0;background:transparent'><div style='width:1024px;height:1024px'>\(svg)</div></body></html>", baseURL: nil)
app.run()
