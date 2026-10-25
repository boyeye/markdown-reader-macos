# Markdown 查看器

原生 macOS SwiftUI + WKWebView 离线 Markdown 阅读器。Apple Silicon，macOS 13+。

- `Reader.swift`：正式程序源码。
- `Resources/reader.html`：排版与渲染模板。
- `Resources/vendor/`：随应用离线打包的第三方库、版本记录和许可证。
- `Assets/AppIcon-D-down.png`：采用的图标设计；原版图标也保留。
- `Probe.swift`：早期工具链验证源码，正式应用不使用。
- `Tests/Harness.swift`：真实 WebKit 渲染与 PDF 导出的集成验证；`Tests/results.json` 为验证结果。

构建：`python3 build.py`。需要 Apple Command Line Tools，无需付费开发者证书。输出 `MarkdownReader.app`，使用 ad-hoc 本地签名。
制作镜像：`python3 package.py`，输出 `dist/MarkdownViewer-1.0-arm64.dmg`，不覆盖已有镜像。

支持打开、拖放、Finder 打开方式、目录、表格、代码高亮、相对路径本地图片、查找、源码查看、主题、字号、最近文件和 PDF 导出。源文件不被修改；修改后使用 ⌘R 重读。

限制：Markdown 文档最多 5 MB；图片最多 20 MB。图片限定在文档所在目录及其子目录，不加载远程图片、SVG 或越界符号链接。只读工具，不包含编辑、Mermaid 或数学公式扩展。最近文件路径和阅读设置保存在本机偏好设置中。

未做 Apple 公证，其他 Mac 首次运行可能需要在系统设置中允许打开。当前在 macOS 15.7.5 Apple Silicon 实测；其他系统仍应实际运行验证。
