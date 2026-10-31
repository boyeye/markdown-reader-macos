# 阅读测试

## 表格与代码

| 名称 | 内容 |
| --- | --- |
| 本地 | 中文阅读 |

```swift
let title = "Hello"
print(title)
```

![本地图标](local.png)

![远程图片](https://example.com/tracker.png)

<script>window.injected = true</script>
<img src="local.png" onerror="window.injected=true">

[跳到章节](#表格与代码)

- [x] 已完成
- [ ] 待完成

行内公式 $E=mc^2$，价格 $5 和 $10 不是公式，转义 \$x\$ 也不是。

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```math
\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
```

$\href{javascript:alert(1)}{点我}$

$\htmlStyle{position:fixed;top:0}{x}$ $\htmlClass{evil}{y}$ $\htmlId{readerReady}{z}$ $\url{javascript:alert(1)}$ $\includegraphics{local.png}$

```mermaid
flowchart LR
  A[打开文档] --> B{含图表?}
  B -->|是| C[渲染 Mermaid]
  B -->|否| D[直接显示]
  click A "javascript:window.injected=true"
  E["<img src=x onerror=window.injected=true>"]
```

```mermaid
sequenceDiagram
  阅读器->>WebKit: 渲染
```

```mermaid
这不是合法的图表
```

```mermaid
%%{init: {"themeCSS": "body{display:none} #reader-content{display:none}", "securityLevel": "loose"}}%%
flowchart LR
  P --> Q
```

```mermaid
%%{init: {"themeVariables": {"fontFamily": "x;} body{display:none} .a{"}}}%%
flowchart LR
  R --> S
```

```mermaid
flowchart LR
  X:::evil --> Y
  classDef evil fill:#f00,color:#fff
  style Y fill:#0f0,stroke:#333
```
