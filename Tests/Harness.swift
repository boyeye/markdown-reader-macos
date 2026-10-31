import AppKit
import SwiftUI
import WebKit

@MainActor final class TestRunner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    var attempts = 0
    let model = ReaderModel()
    var pdfOutcomes: [String: Bool] = [:]
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
            let mode = theme.hasPrefix("dark") ? "dark" : "light"
            web.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            // "-diagrams" frames scroll to the math and Mermaid section.
            web.callAsyncJavaScript("window.setAppearance(mode,16);await window.readerReady;if(theme.endsWith('-diagrams'))document.querySelector('.math-inline').scrollIntoView();else window.scrollTo(0,0);", arguments: ["theme": theme, "mode": mode], in: nil, in: .page) { _ in
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
        shoot(["light", "dark", "light-diagrams", "dark-diagrams"])
    }
    // Pathological input: over-budget diagrams and formulas, plus `$` runs that would make a naive regex backtrack.
    // Rendering must finish within the time limit and leave the over-budget parts as source text.
    func stress(_ web: WKWebView, done: @escaping (Bool, String) -> Void) {
        let js = """
        const diagrams=[];for(let i=0;i<55;i++)diagrams.push('```mermaid\\nflowchart LR\\n  A'+i+' --> B'+i+'\\n```');
        const formulas=[];for(let i=0;i<2100;i++)formulas.push('$x_{'+i+'}$');
        const cases={diagrams:diagrams.join('\\n\\n'),formulas:formulas.join('\\n\\n'),dollars:'$'.repeat(100000),openBlock:'$$'+'a'.repeat(200000),aRun:'$a'.repeat(50000)};
        const times={},counts={};
        for(const [name,doc] of Object.entries(cases)){const t=performance.now();window.renderMarkdown(doc);await window.readerReady;times[name]=Math.round(performance.now()-t);
        counts[name]={svg:document.querySelectorAll('.mermaid-diagram svg').length,skipped:document.querySelectorAll('.diagram-skipped').length,math:document.querySelectorAll('.katex').length,mathSkipped:document.querySelectorAll('.math-skipped').length}}
        const ok=counts.diagrams.svg===50&&counts.diagrams.skipped===5&&counts.formulas.math===2000&&Object.values(times).every(ms=>ms<30000);
        return JSON.stringify({ok,times,counts});
        """
        web.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let text = value as? String, let data = text.data(using: .utf8),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { done(false, "\(result)"); return }
            done(info["ok"] as? Bool == true, text)
        }
    }
    // Feeds a forged Mermaid SVG through the real insertion path: only the rule scoped to the diagram's own id may survive.
    func cssBoundary(_ web: WKWebView, done: @escaping (Bool) -> Void) {
        let js = """
        const real=mermaid.render;mermaid.render=async id=>({svg:'<svg id="'+id+'"><style>#'+id+'x p{color:red} #'+id+' ~ p{display:none} #'+id+' + p{display:none} #'+id+'{& ~ p{display:none}} #'+id+' :is(p){color:red} @media screen{#'+id+' .ok{fill:blue}} #'+id+' .ok{fill:red} #'+id+' .u{fill:url(https://example.com/x)} #'+id+' .e{fill:u\\\\72 l(https://example.com/z)} #'+id+' .f{position:f\\\\69 xed} @keyframes k{to{fill:url(https://example.com/k)}} body{display:none}</style><g id="'+id+'"><rect class="ok" width="5" height="5" style="fill:url(https://example.com/y)"></rect></g></svg>'});
        try{window.renderMarkdown('```mermaid\\ngraph LR\\n```\\n\\nafter');await window.readerReady}finally{mermaid.render=real}
        const svg=document.querySelector('.mermaid-diagram svg'),rules=svg?[...svg.querySelectorAll('style')].map(st=>st.textContent).join('|'):'';
        const scoped=!!svg&&/\\.ok/.test(rules)&&!/~|\\+|&|:is|@media|url\\(|body|#mermaid-[0-9-]+x/.test(rules)&&svg.querySelectorAll('[id="'+svg.id+'"]').length===0&&!svg.querySelector('rect').hasAttribute('style')&&!/example\\.com|fixed/.test(rules)&&getComputedStyle(document.querySelector('main p:last-child')).display!=='none';
        mermaid.render=async id=>({svg:'<svg id="other"><style>@keyframes k{to{opacity:0}} #other .x{fill:red}</style><rect class="x"></rect></svg>'});
        let mismatch=false;try{window.renderMarkdown('```mermaid\\ngraph LR\\n```');await window.readerReady;const svg2=document.querySelector('.mermaid-diagram svg');mismatch=!!svg2&&svg2.querySelectorAll('style').length===0}finally{mermaid.render=real}
        return scoped&&mismatch;
        """
        web.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            if case .success(let value) = result { done(value as? Bool == true) } else { done(false) }
        }
    }
    // makePDF must fail, not export, when: diagrams never finish; diagram rendering throws unexpectedly; the page still
    // shows an older document; a newer render replaces the one being waited for and never finishes; or the document
    // changes while the PDF is being generated.
    func pdfFailures(_ web: WKWebView, done: @escaping (Bool, Bool) -> Void) {
        func failed(_ r: Result<Data, Error>) -> Bool { if case .failure = r { return true } else { return false } }
        let rev = model.revision
        let steps: [(String, String)] = [
            ("timeout", "window.readerRevision=revision;window.readerReady=new Promise(()=>{})"),
            ("thrown", "const real=mermaid.initialize;mermaid.initialize=()=>{throw new Error('boom')};try{window.renderMarkdown('```mermaid\\ngraph LR\\n  A-->B\\n```',revision)}finally{mermaid.initialize=real}"),
            ("oldPage", "window.readerRevision=revision-1;window.readerReady=Promise.resolve()"),
            ("replaced", "window.readerRevision=revision;window.readerReady=new Promise(r=>setTimeout(r,300));setTimeout(()=>{window.readerReady=new Promise(()=>{});window.readerRenderId++},100)"),
        ]
        var outcomes: [String: Bool] = [:]
        func run(_ index: Int) {
            guard index < steps.count else {
                // A real theme switch re-renders the diagrams while the PDF is being created; then a document switch.
                web.callAsyncJavaScript("window.setAppearance('light',16);window.renderMarkdown('```mermaid\\ngraph LR\\n  A-->B\\n```',revision);await window.readerReady", arguments: ["revision": rev], in: nil, in: .page) { _ in
                    var themeHook = false
                    self.model.pdfWillCreate = { themeHook = true; web.evaluateJavaScript("window.setAppearance('dark',16)") }
                    self.model.makePDF { rerendered in
                        var hookRan = false
                        self.model.pdfWillCreate = { hookRan = true; self.model.revision += 1 }
                        self.model.makePDF { switched in
                            self.model.pdfWillCreate = nil
                            outcomes["rerendered"] = themeHook && failed(rerendered)
                            // Two documents opened back to back: the page must end up showing the second, and export it.
                            self.model.show(self.root.appendingPathComponent("Tests/second.md"), text: "# 第一篇")
                            self.model.show(self.root.appendingPathComponent("Tests/second.md"), text: "# 第二篇\n\n```mermaid\ngraph LR\n  C-->D\n```")
                            self.model.makePDF { latest in
                                web.evaluateJavaScript("document.querySelector('h1')?.textContent+'|'+window.readerRevision") { value, _ in
                                    outcomes["consecutive"] = (try? latest.get()) != nil && (value as? String) == "第二篇|\(self.model.revision)"
                                    self.pdfOutcomes = outcomes
                                    done(outcomes.values.allSatisfy { $0 } && outcomes.count == steps.count + 2, hookRan && failed(switched))
                                }
                            }
                        }
                    }
                }
                return
            }
            web.callAsyncJavaScript(steps[index].1, arguments: ["revision": rev], in: nil, in: .page) { _ in
                self.model.makePDF { result in outcomes[steps[index].0] = failed(result); run(index + 1) }
            }
        }
        run(0)
    }
    func check() {
        attempts += 1
        if attempts > 50 { finish(["passed":false,"error": model.error ?? "Timed out"]);return }
        guard let web = model.web, model.headings.count == 2 else { return }
        web.callAsyncJavaScript("await window.readerReady;return JSON.stringify({math:document.querySelectorAll('.math-inline .katex').length,displayMath:document.querySelectorAll('.math-display .katex-display').length,currency:document.querySelector('main').textContent.includes('$5 和 $10'),mathLinkBlocked:!document.querySelector('.katex a, .katex [href], .katex img, .katex .evil, #readerReady, .katex [style*=fixed]'),diagramErrors:[...document.querySelectorAll('.diagram-error p')].map(p=>p.textContent),cssContained:getComputedStyle(document.body).display!=='none'&&getComputedStyle(document.getElementById('reader-content')).display!=='none'&&[...document.querySelectorAll('.mermaid-diagram style')].every(st=>!/url\\(|body|reader-content/i.test(st.textContent)),mermaid:document.querySelectorAll('.mermaid-diagram:not(.diagram-error) svg').length,mermaidError:document.querySelectorAll('.diagram-error').length,mermaidSafe:!document.querySelector('.mermaid-diagram [href], .mermaid-diagram [*|href], .mermaid-diagram foreignObject, .mermaid-diagram [onerror], .mermaid-diagram [onclick]'),table:document.querySelectorAll('table tbody tr').length,highlight:document.querySelectorAll('code.hljs span').length,localImage:[...document.querySelectorAll('img')].some(i=>i.naturalWidth>0),remoteBlocked:document.querySelectorAll('.remote-image').length===1,injectionBlocked:window.injected!==true && !document.querySelector('main script') && !document.querySelector('main [onerror]'),anchor:document.querySelector('a').getAttribute('href')==='#section-1',tasks:document.querySelectorAll('input[type=checkbox]').length})", arguments: [:], in: nil, in: .page) { outcome in
            guard case .success(let value) = outcome, let string=value as? String, let data=string.data(using:.utf8), let checks=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
            guard checks["localImage"] as? Bool == true else { return }
            self.timer?.invalidate()
            let config = WKFindConfiguration()
            web.find("中文阅读",configuration: config) { found in
                self.model.makePDF { pdf in
                    var result=checks
                    result["stress"]=true
                    result["find"]=found.matchFound
                    result["outline"]=self.model.headings.count
                    result["tabs"]=self.checkTabs()
                    do { let bytes=try pdf.get();try bytes.write(to:self.root.appendingPathComponent("Tests/export.pdf"));result["pdf"]=bytes.starts(with:Data("%PDF".utf8)) } catch { result["pdf"]=false }
                    let expected = (checks["table"] as? Int == 1) && ((checks["highlight"] as? Int ?? 0)>0) && (checks["tasks"] as? Int == 2) && (checks["math"] as? Int == 7) && (checks["displayMath"] as? Int == 2) && (checks["mermaid"] as? Int == 5) && (checks["mermaidError"] as? Int == 1)
                    let bools=["localImage","remoteBlocked","injectionBlocked","anchor","find","pdf","tabs","currency","mathLinkBlocked","mermaidSafe","cssContained"]
                    result["passed"]=expected && bools.allSatisfy { result[$0] as? Bool == true }
                    self.snapshots(web) { self.stress(web) { ok, detail in
                        result["stress"]=ok; result["stressDetail"]=detail
                        self.cssBoundary(web) { css in
                            result["cssBoundary"]=css
                            self.pdfFailures(web) { timeout, switched in
                                result["pdfTimeoutFails"]=timeout; result["pdfSwitchFails"]=switched; result["pdfOutcomes"]=self.pdfOutcomes
                                result["passed"]=(result["passed"] as? Bool == true) && ok && css && timeout && switched
                                self.finish(result)
                            }
                        }
                    } }
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
