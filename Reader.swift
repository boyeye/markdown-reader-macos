import SwiftUI
import WebKit
import UniformTypeIdentifiers
import Combine

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

// Appearance and recent files are app-wide; every window observes the same settings.
@MainActor final class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()
    static let defaultFontSize = 16.0
    @Published var fontSize = UserDefaults.standard.object(forKey: "readerFontSize") as? Double ?? ReaderSettings.defaultFontSize {
        didSet { UserDefaults.standard.set(fontSize, forKey: "readerFontSize") }
    }
    @Published var theme = UserDefaults.standard.string(forKey: "readerTheme") ?? "system" {
        didSet { UserDefaults.standard.set(theme, forKey: "readerTheme") }
    }
    @Published var recent = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
    func noteRecent(_ url: URL) {
        recent.removeAll { $0 == url.path }; recent.insert(url.path, at: 0); recent = Array(recent.prefix(10))
        UserDefaults.standard.set(recent, forKey: "recentFiles")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
}

// One model per window (tab).
@MainActor final class ReaderModel: ObservableObject {
    @Published var markdown = welcome
    @Published var fileURL: URL?
    @Published var headings: [Heading] = []
    @Published var error: String?
    @Published var showSource = false
    @Published var showFind = false
    @Published var query = ""
    @Published var findStatus = ""
    @Published var revision = 0
    weak var web: WKWebView?
    weak var window: NSWindow?
    private var appearance: AnyCancellable?
    var title: String { fileURL?.lastPathComponent ?? "欢迎" }
    init() {
        // @Published emits before the stored value changes, so apply the emitted values directly.
        appearance = ReaderSettings.shared.$theme.combineLatest(ReaderSettings.shared.$fontSize).dropFirst()
            .sink { [weak self] theme, size in self?.applyAppearance(theme: theme, size: size) }
    }
    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { for url in panel.urls { WindowRouter.open(url, from: self) } }
    }
    static func read(_ url: URL) throws -> String {
        let attrs = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attrs.isRegularFile == true else { throw ReaderError.message("请选择 Markdown 或文本文件。") }
        guard ["md", "markdown", "txt", "mdown", "mkd"].contains(url.pathExtension.lowercased()) else { throw ReaderError.message("支持 .md、.markdown 和 .txt 文件。") }
        guard (attrs.fileSize ?? 0) <= 5_000_000 else { throw ReaderError.message("文件超过 5 MB，请先使用文本编辑器拆分。") }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw ReaderError.message("无法读取文字编码，请将文件另存为 UTF-8。") }
        return text
    }
    func open(_ url: URL) {
        do { show(url, text: try Self.read(url)) } catch { self.error = error.localizedDescription }
    }
    func show(_ url: URL, text: String) {
        markdown = text; fileURL = url; headings = []; revision += 1
        ReaderSettings.shared.noteRecent(url)
    }
    func reload() { if let url = fileURL { open(url) } }
    func jump(_ id: String) {
        web?.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView({behavior:'smooth',block:'start'})", arguments: ["id": id], in: nil, in: .page) { _ in }
    }
    func applyAppearance(theme: String? = nil, size: Double? = nil) {
        let settings = ReaderSettings.shared
        web?.callAsyncJavaScript("window.setAppearance(theme,size)", arguments: ["theme": theme ?? settings.theme, "size": size ?? settings.fontSize], in: nil, in: .page) { _ in }
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

// Routes files to windows: an already-open file is brought to front, an empty welcome window is reused,
// otherwise the file opens in a new tab beside the window it came from.
@MainActor enum WindowRouter {
    struct Request { let url: URL?; let text: String?; weak var tabOf: NSWindow? }
    static var openWindow: OpenWindowAction?
    static var pending: [Request] = []
    static let models = NSHashTable<ReaderModel>.weakObjects()
    static var keyModel: ReaderModel? { models.allObjects.first { $0.window != nil && $0.window === NSApp.keyWindow } ?? models.allObjects.first }

    static func open(_ url: URL, from source: ReaderModel?) {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = models.allObjects.first(where: { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() == url }) {
            existing.window?.makeKeyAndOrderFront(nil); existing.reload(); return
        }
        let text: String
        do { text = try ReaderModel.read(url) } catch { (source ?? keyModel)?.error = error.localizedDescription; return }
        if let source, source.fileURL == nil { source.show(url, text: text); return }
        newWindow(Request(url: url, text: text, tabOf: source?.window ?? NSApp.keyWindow))
    }
    static func newWindow(_ request: Request) {
        pending.append(request)
        openWindow?(id: "reader")
    }
    // Called once when a window's view is attached to its NSWindow.
    static func attach(_ model: ReaderModel, to window: NSWindow) {
        guard model.window == nil else { return }
        model.window = window; models.add(model)
        guard !pending.isEmpty else { return }
        let request = pending.removeFirst()
        if let url = request.url, let text = request.text { model.show(url, text: text) }
        if let target = request.tabOf, target !== window, target.isVisible {
            DispatchQueue.main.async { target.addTabbedWindow(window, ordered: .above); window.makeKeyAndOrderFront(nil) }
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { let view = AccessorView(); view.onWindow = onWindow; return view }
    func updateNSView(_ view: NSView, context: Context) {}
    final class AccessorView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { onWindow?(window) } }
    }
}

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
            webView.callAsyncJavaScript("window.renderMarkdown(text);window.setAppearance(theme,size)", arguments: ["text": model.markdown, "theme": ReaderSettings.shared.theme, "size": ReaderSettings.shared.fontSize], in: nil, in: .page) { [weak self] result in
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
                if file.path.hasPrefix(base.path + "/") { WindowRouter.open(file, from: model) }
            }
        }
    }
}

struct ReaderWindow: View {
    @StateObject private var model = ReaderModel()
    @Environment(\.openWindow) private var openWindow
    // Lets macOS window restoration reopen each window's document after relaunch.
    @SceneStorage("documentPath") private var documentPath = ""
    var body: some View {
        ReaderView(model: model)
            .onAppear {
                WindowRouter.openWindow = openWindow
                DispatchQueue.main.async { restore() }
            }
            .onChange(of: model.fileURL) { documentPath = $0?.path ?? "" }
            // Finder opens go to an existing window and are routed from there, instead of SwiftUI spawning a window each time.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onOpenURL { url in if url.isFileURL { WindowRouter.open(url, from: WindowRouter.keyModel ?? model) } }
    }
    private func restore() {
        guard model.fileURL == nil, !documentPath.isEmpty else { return }
        let url = URL(fileURLWithPath: documentPath)
        guard !WindowRouter.models.allObjects.contains(where: { $0.fileURL == url }), let text = try? ReaderModel.read(url) else { documentPath = ""; return }
        model.show(url, text: text)
    }
}

struct ReaderView: View {
    @ObservedObject var model: ReaderModel
    @ObservedObject var settings = ReaderSettings.shared
    @State private var targeted = false
    @State private var sidebar: NavigationSplitViewVisibility = .all
    @FocusState private var findFocused: Bool
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebar) {
            VStack(alignment: .leading, spacing: 0) {
                Label("大纲", systemImage: "text.alignleft").font(.headline).padding()
                if model.headings.isEmpty { Text("打开文档后在这里浏览章节").foregroundStyle(.secondary).font(.callout).padding() }
                List(model.headings) { heading in
                    Button { model.jump(heading.id) } label: {
                        Text(heading.title).lineLimit(2).font(heading.level == 1 ? .headline : .body)
                            .padding(.leading, CGFloat(min(heading.level - 1, 3)) * 10).padding(.vertical, 3)
                    }.buttonStyle(.plain)
                }.listStyle(.sidebar)
                Divider()
                Menu {
                    ForEach(settings.recent, id: \.self) { path in Button(URL(fileURLWithPath: path).lastPathComponent) { WindowRouter.open(URL(fileURLWithPath: path), from: model) } }
                    if settings.recent.isEmpty { Text("暂无最近文件") }
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
                        ScrollView { Text(model.markdown).font(.system(size: settings.fontSize - 2, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(28) }
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
                    Picker("外观", selection: $settings.theme) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Divider()
                    Button("增大字号") { settings.fontSize = min(28, settings.fontSize + 1) }
                    Button("减小字号") { settings.fontSize = max(12, settings.fontSize - 1) }
                    Button("恢复默认字号") { settings.fontSize = ReaderSettings.defaultFontSize }
                } label: { Label("阅读设置", systemImage: "textformat.size") }
            }
        }
        .preferredColorScheme(settings.theme == "system" ? nil : (settings.theme == "dark" ? .dark : .light))
        .background(WindowAccessor { WindowRouter.attach(model, to: $0) })
        .focusedSceneObject(model)
        .onChange(of: model.showFind) { visible in if visible { model.showSource = false; findFocused = true } }
        .alert("无法完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好", role: .cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    Task { @MainActor in if let url { WindowRouter.open(url, from: model) } else { model.error = error?.localizedDescription ?? "无法读取拖入的文件。" } }
                }
            }
            return !providers.isEmpty
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { NSApplication.shared.applicationIconImage = image }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#if !TESTING
@main struct MarkdownReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Markdown 查看器", id: "reader") { ReaderWindow() }.defaultSize(width: 1080, height: 760)
        .commands { ReaderCommands() }
    }
}

struct ReaderCommands: Commands {
    @FocusedObject var model: ReaderModel?
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建窗口") { WindowRouter.newWindow(.init(url: nil, text: nil, tabOf: nil)) }.keyboardShortcut("n")
            Button("新建标签页") { WindowRouter.newWindow(.init(url: nil, text: nil, tabOf: NSApp.keyWindow)) }.keyboardShortcut("t")
            Divider()
            Button("打开…") { (model ?? WindowRouter.keyModel)?.openPanel() }.keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Button("重新载入") { model?.reload() }.keyboardShortcut("r").disabled(model?.fileURL == nil)
            Button("导出 PDF…") { model?.exportPDF() }.disabled(model == nil || model?.showSource == true)
        }
        CommandGroup(after: .textEditing) { Button("查找…") { model?.showFind = true }.keyboardShortcut("f").disabled(model == nil) }
    }
}

#endif
