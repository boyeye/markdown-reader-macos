import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct Heading: Identifiable { let id: String; let title: String; let level: Int }
let welcome = #"""
# 欢迎使用 Markdown 查看器

让文字回到阅读本身。

点击工具栏的 **打开文件**，或把 `.md` 文件拖入窗口。也可以在 Finder 中选择「打开方式 → Markdown 查看器」。

## 阅读功能

- 左侧目录，快速跳转章节
- **⌘F** 查找、**⌘O** 打开、**⌘R** 重新载入
- 调整字号，切换浅色、深色或跟随系统
- 支持表格、任务列表、引用和代码高亮
- 同目录的本地图片可直接显示

## 代码示例

```swift
struct Reading {
    let title = "专注阅读"
    func open() { print(title) }
}
```

## 表格

| 功能 | 状态 |
| --- | --- |
| 离线阅读 | 已支持 |
| 本地图片 | 已支持 |
| 导出 PDF | 菜单「文件 → 导出 PDF」 |

> 文档只在本机处理。远程图片默认不加载，网页链接会在系统浏览器中打开。

## 开始阅读

- [x] 一个轻巧的原生 Mac 窗口
- [x] 为长文准备的舒适排版
- [ ] 打开你的第一篇 Markdown
"""#

@MainActor final class ReaderModel: ObservableObject {
    static let shared = ReaderModel()
    @Published var markdown = welcome
    @Published var fileURL: URL?
    @Published var headings: [Heading] = []
    @Published var error: String?
    @Published var showSource = false
    @Published var showFind = false
    @Published var query = ""
    @Published var findStatus = ""
    @Published var recent = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
    @Published var revision = 0
    @Published var fontSize = UserDefaults.standard.object(forKey: "readerFontSize") as? Double ?? 17 {
        didSet { UserDefaults.standard.set(fontSize, forKey: "readerFontSize"); applyAppearance() }
    }
    @Published var theme = UserDefaults.standard.string(forKey: "readerTheme") ?? "system" {
        didSet { UserDefaults.standard.set(theme, forKey: "readerTheme"); applyAppearance() }
    }
    weak var web: WKWebView?
    var title: String { fileURL?.lastPathComponent ?? "欢迎" }
    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL) {
        do {
            let attrs = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard attrs.isRegularFile == true else { throw ReaderError.message("请选择 Markdown 或文本文件。") }
            guard ["md", "markdown", "txt", "mdown", "mkd"].contains(url.pathExtension.lowercased()) else { throw ReaderError.message("支持 .md、.markdown 和 .txt 文件。") }
            guard (attrs.fileSize ?? 0) <= 5_000_000 else { throw ReaderError.message("文件超过 5 MB，请先使用文本编辑器拆分。") }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw ReaderError.message("无法读取文字编码，请将文件另存为 UTF-8。") }
            markdown = text; fileURL = url; headings = []; revision += 1
            recent.removeAll { $0 == url.path }; recent.insert(url.path, at: 0); recent = Array(recent.prefix(10))
            UserDefaults.standard.set(recent, forKey: "recentFiles")
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch { self.error = error.localizedDescription }
    }
    func reload() { if let url = fileURL { open(url) } }
    func jump(_ id: String) {
        web?.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView({behavior:'smooth',block:'start'})", arguments: ["id": id], in: nil, in: .page) { _ in }
    }
    func applyAppearance() {
        web?.callAsyncJavaScript("window.setAppearance(theme,size)", arguments: ["theme": theme, "size": fontSize], in: nil, in: .page) { _ in }
    }
    func find(backwards: Bool = false) {
        guard !query.isEmpty else { findStatus = ""; return }
        let config = WKFindConfiguration(); config.backwards = backwards; config.wraps = true
        web?.find(query, configuration: config) { [weak self] result in self?.findStatus = result.matchFound ? "" : "未找到" }
    }
    func exportPDF() {
        guard let web else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Markdown") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        web.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            do { try result.get().write(to: url) } catch { self?.error = error.localizedDescription }
        }
    }
}
enum ReaderError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }

// Only local images within the selected document's directory are exposed to WebKit.
final class LocalImages: NSObject, WKURLSchemeHandler {
    var root: URL?
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let root, let url = task.request.url else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let path = String(url.path.drop(while: { $0 == "/" }))
        let file = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/"), ["png","jpg","jpeg","gif","webp","heic","avif"].contains(file.pathExtension.lowercased()),
              let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), (attrs.fileSize ?? 0) <= 20_000_000,
              let data = try? Data(contentsOf: file) else { task.didFailWithError(URLError(.noPermissionsToReadFile)); return }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct ReadingWebView: NSViewRepresentable {
    @ObservedObject var model: ReaderModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(context.coordinator.images, forURLScheme: "reader")
        config.userContentController.add(context.coordinator, name: "outline")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        model.web = web
        context.coordinator.load(web)
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastRevision != model.revision { context.coordinator.load(web) }
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: ReaderModel; let images = LocalImages(); var lastRevision = -1
        init(_ model: ReaderModel) { self.model = model }
        func load(_ web: WKWebView) {
            lastRevision = model.revision; images.root = model.fileURL?.deletingLastPathComponent()
            guard let dir = Bundle.main.resourceURL,
                  var html = try? String(contentsOf: dir.appendingPathComponent("reader.html"), encoding: .utf8) else { model.error = "阅读模板缺失，请重新安装应用。"; return }
            let nonce = UUID().uuidString
            html = html.replacingOccurrences(of: "__NONCE__", with: nonce)
            for (token,name) in [("__MARKED__","marked.js"),("__PURIFY__","purify.js"),("__HIGHLIGHT__","highlight.js")] {
                guard let js = try? String(contentsOf: dir.appendingPathComponent("vendor/" + name), encoding: .utf8) else { model.error = "离线组件缺失：" + name; return }
                html = html.replacingOccurrences(of: token, with: js)
            }
            web.loadHTMLString(html, baseURL: URL(string: "reader://document/"))
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.callAsyncJavaScript("window.renderMarkdown(text);window.setAppearance(theme,size)", arguments: ["text": model.markdown, "theme": model.theme, "size": model.fontSize], in: nil, in: .page) { [weak self] result in
                if case .failure(let error) = result { self?.model.error = "文档渲染失败：" + error.localizedDescription }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let list = message.body as? [[String:Any]] else { return }
            model.headings = list.compactMap { item in
                guard let id = item["id"] as? String, let title = item["title"] as? String, let level = item["level"] as? Int else { return nil }
                return Heading(id: id, title: title, level: level)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated else { decisionHandler(.allow); return }
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "reader", url.fragment != nil { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            if ["https","http","mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            else if url.scheme == "reader", let root = images.root {
                let base = root.resolvingSymlinksInPath().standardizedFileURL
                let file = base.appendingPathComponent(String(url.path.drop(while: { $0 == "/" }))).resolvingSymlinksInPath().standardizedFileURL
                if file.path.hasPrefix(base.path + "/") { model.open(file) }
            }
        }
    }
}

struct ReaderView: View {
    @ObservedObject var model = ReaderModel.shared
    @State private var targeted = false
    @State private var sidebar: NavigationSplitViewVisibility = .all
    @FocusState private var findFocused: Bool
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebar) {
            VStack(alignment: .leading, spacing: 0) {
                Label("文档目录", systemImage: "text.alignleft").font(.headline).padding()
                if model.headings.isEmpty { Text("打开文档后在这里浏览章节").foregroundStyle(.secondary).font(.callout).padding() }
                List(model.headings) { heading in
                    Button { model.jump(heading.id) } label: {
                        Text(heading.title).lineLimit(2).font(heading.level == 1 ? .headline : .body)
                            .padding(.leading, CGFloat(min(heading.level - 1, 3)) * 10).padding(.vertical, 3)
                    }.buttonStyle(.plain)
                }.listStyle(.sidebar)
                Divider()
                Menu {
                    ForEach(model.recent, id: \.self) { path in Button(URL(fileURLWithPath: path).lastPathComponent) { model.open(URL(fileURLWithPath: path)) } }
                    if model.recent.isEmpty { Text("暂无最近文件") }
                } label: { Label("最近打开", systemImage: "clock") }.padding()
            }.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if model.showFind {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("查找文档内容", text: $model.query).textFieldStyle(.roundedBorder).focused($findFocused).onSubmit { model.find() }
                        Text(model.findStatus).font(.caption).foregroundStyle(.secondary)
                        Button { model.find(backwards: true) } label: { Image(systemName: "chevron.up") }.help("上一处")
                        Button { model.find() } label: { Image(systemName: "chevron.down") }.help("下一处")
                        Button { model.showFind = false } label: { Image(systemName: "xmark") }.help("关闭查找")
                    }.padding(10)
                    Divider()
                }
                ZStack {
                    ReadingWebView(model: model).opacity(model.showSource ? 0 : 1)
                    if model.showSource {
                        ScrollView { Text(model.markdown).font(.system(size: model.fontSize - 2, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(28) }
                    }
                    if targeted { RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.tint, lineWidth: 3)).padding(8).allowsHitTesting(false) }
                }
                Divider()
                HStack {
                    Text(model.fileURL == nil ? "打开或拖入 Markdown 文件" : model.fileURL!.path).lineLimit(1).truncationMode(.middle)
                    Spacer(); Text("\(model.markdown.count) 字符"); Text("本机阅读").foregroundStyle(.tertiary)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .navigationTitle(model.title)
        .toolbar {
            ToolbarItemGroup {
                Button { model.openPanel() } label: { Label("打开文件", systemImage: "folder") }.help("打开文件 ⌘O")
                Button { model.reload() } label: { Label("重新载入", systemImage: "arrow.clockwise") }.disabled(model.fileURL == nil)
                Button { model.showFind.toggle() } label: { Label("查找", systemImage: "magnifyingglass") }
                Button { model.showSource.toggle() } label: { Label(model.showSource ? "阅读预览" : "查看源码", systemImage: model.showSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") }
                Menu {
                    Picker("外观", selection: $model.theme) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Divider()
                    Button("增大字号") { model.fontSize = min(28, model.fontSize + 1) }
                    Button("减小字号") { model.fontSize = max(12, model.fontSize - 1) }
                    Button("恢复默认字号") { model.fontSize = 17 }
                } label: { Label("阅读设置", systemImage: "textformat.size") }
            }
        }
        .preferredColorScheme(model.theme == "system" ? nil : (model.theme == "dark" ? .dark : .light))
        .onChange(of: model.showFind) { visible in if visible { model.showSource = false; findFocused = true } }
        .alert("无法完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好", role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                Task { @MainActor in if let url { model.open(url) } else { model.error = error?.localizedDescription ?? "无法读取拖入的文件。" } }
            }
            return true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { NSApplication.shared.applicationIconImage = image }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { ReaderModel.shared.open(URL(fileURLWithPath: first)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#if !TESTING
@main struct MarkdownReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var model = ReaderModel.shared
    var body: some Scene {
        Window("Markdown 查看器", id: "reader") { ReaderView().onOpenURL { model.open($0) } }.defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { Button("打开…") { model.openPanel() }.keyboardShortcut("o") }
            CommandGroup(after: .newItem) {
                Button("重新载入") { model.reload() }.keyboardShortcut("r").disabled(model.fileURL == nil)
                Button("导出 PDF…") { model.exportPDF() }.disabled(model.showSource)
            }
            CommandGroup(after: .textEditing) { Button("查找…") { model.showFind = true }.keyboardShortcut("f") }
        }
    }
}

#endif
