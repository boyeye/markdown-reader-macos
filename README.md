# Markdown 查看器

原生 macOS SwiftUI + WKWebView 离线 Markdown 阅读器。Apple Silicon，macOS 13+。

- `Reader.swift`：正式程序源码。
- `Resources/reader.html`：排版与渲染模板。
- `Resources/vendor/`：随应用离线打包的第三方库、版本记录和许可证。
- `Assets/AppIcon-D1.svg`：当前图标（青底纸页、墨色 M、朱红印章）；`AppIcon-D1-small.svg` 是 16/32 px 用的简化版，`AppIcon-D1.icns` 由两者生成。旧图标 `AppIcon-D-down.*` 保留。
- `inline_katex_fonts.py`：把 KaTeX 字体以 data URI 嵌入 `Resources/vendor/katex.css`，供离线使用。
- `Probe.swift`：早期工具链验证源码，正式应用不使用。
- `Tests/Harness.swift`：真实 WebKit 渲染、PDF 导出与标签页路由的集成验证；`Tests/results.json` 为验证结果。
- `toolchain.py`：构建与测试共用的编译参数、SDK 选择和版本号。

构建：`python3 build.py`。需要 Apple Command Line Tools，无需 Xcode 或付费开发者证书。输出 `MarkdownReader.app`，使用 ad-hoc 本地签名。
测试：`python3 test.py`，编译并运行 `Tests/Harness.swift`，结果写入 `Tests/results.json`，浅色/深色渲染截图写入 `.build/`。
制作镜像：`python3 package.py`，输出 `dist/MarkdownViewer-<版本>-arm64.dmg`，不覆盖已有镜像。版本号统一在 `toolchain.py` 中维护。

工具链说明：macOS 27 SDK 中 SwiftUI 的 `@State` 依赖宏插件，该插件只随 Xcode 提供。只装 Command Line Tools 时，`toolchain.py` 会自动改用已安装的最新 macOS 26.x SDK；可用环境变量 `READER_SDK` 指定 SDK 路径。

支持打开、拖放、多窗口与标签页（⌘T 新建标签页、⌘N 新建窗口；从窗口内打开的文件以新标签打开，已打开的文件直接切换过去）、Finder 打开方式、大纲、表格、代码高亮、数学公式、Mermaid 图表、相对路径本地图片、查找、源码查看、主题、字号、最近文件和 PDF 导出。排版参考 Typora 默认风格，深色模式采用石墨灰配色。源文件不被修改；修改后使用 ⌘R 重读。若在系统设置中关闭「退出 App 时关闭窗口」，重新启动后各窗口会恢复各自的文档。

限制：Markdown 文档最多 5 MB；图片最多 20 MB。图片限定在文档所在目录及其子目录，不加载远程图片、SVG 或越界符号链接。只读工具，不包含编辑功能。

数学公式：行内 `$...$`，独立公式 `$$...$$` 或 ```` ```math ```` 代码块，由 KaTeX 渲染；不支持 `\href` 等可产生链接或 HTML 的命令。`$5` 这类金额不会被当成公式，`\$` 可输出美元符号。

Mermaid 图表：写在 ```` ```mermaid ```` 代码块中。以 strict 安全级别渲染，生成的 SVG 会再经 DOMPurify 清理，图中的点击链接不会生效。语法有误时显示错误原因和原始代码。图表随浅色/深色主题切换配色，导出 PDF 时会等图表渲染完成。Mermaid 库约 5 MB，仅在文档含 mermaid 代码块时加载。

为防止异常文档拖慢阅读器，每篇文档最多渲染 2000 个公式（单个不超过 5000 字符）和 50 个图表（单个不超过 5 万字符，合计不超过 30 万字符），超出部分按源码显示。图表中的 CSS 只保留作用于该图表本身的规则，引用外部地址的样式会被丢弃。导出 PDF 时最多等待图表 15 秒，若文档在等待期间被切换则放弃导出并提示。最近文件路径和阅读设置保存在本机偏好设置中。

未做 Apple 公证，其他 Mac 首次运行可能需要在系统设置中允许打开。当前在 macOS 15.7.5 Apple Silicon 实测；其他系统仍应实际运行验证。

## ☕ 请我喝杯咖啡

这个工具免费使用。如果它帮到了你，欢迎[请我喝杯咖啡](https://github.com/boyeye#-%E8%AF%B7%E6%88%91%E5%96%9D%E6%9D%AF%E5%92%96%E5%95%A1--buy-me-a-coffee)，用微信扫码即可，金额随意。谢谢支持 ❤️

If you find it useful, you can [buy me a coffee](https://github.com/boyeye#-%E8%AF%B7%E6%88%91%E5%96%9D%E6%9D%AF%E5%92%96%E5%95%A1--buy-me-a-coffee).
