# Markdown 阅读器（Markdown Viewer）

一款原生 macOS Markdown 阅读器，专注于**完整、优雅地阅读**本地 Markdown 文档。基于 Swift + SwiftUI + WebKit 构建，无任何第三方运行时依赖，开箱即用。

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## ✨ 功能特性

### 阅读体验
- **三栏布局**：文档列表 / 大纲面板 / 正文阅读区，左栏与大纲均可收起（状态自动记忆）
- **完整渲染**：基于 [marked.js](https://github.com/markedjs/marked) + [GitHub 风格样式](https://github.com/sindresorhus/github-markdown-css)，完整支持标题、表格、代码高亮、引用块、任务列表、删除线等 GFM 语法
- **Mermaid 流程图**：内置 [mermaid.js](https://github.com/mermaid-js/mermaid)，```mermaid``` 代码块自动渲染为流程图 / 时序图 / 饼图等图表
- **深色模式**：一键切换明暗主题，正文字体、代码块、流程图同步适配
- **图片高清显示**：双击图片弹窗全屏查看，支持缩放与拖动

### 效率功能
- **大纲导航**：自动提取文档标题层级，点击平滑跳转到对应位置
- **文档内查找**（⌘F）：全部命中高亮，回车/方向键逐项跳转，显示"第 n / 共 m 处"
- **底部状态栏**：实时字数统计 + 阅读进度百分比
- **字体缩放**：⌘+ / ⌘- / ⌘0，50% ~ 200%
- **导出 PDF**（⌘P）：通过系统打印面板"存储为 PDF"
- **文档搜索**：按文件名 / 文档标题快速过滤
- **会话记忆**：自动恢复上次打开的文件夹、选中状态、面板开关、主题与缩放

## 📸 界面预览

```
┌────────────┬──────────┬─────────────────────────────┐
│  搜索文档   │  大纲     │                             │
│ ▸ 文档列表  │  H1 标题  │                             │
│   文档标题  │   H2 标题 │      Markdown 渲染正文       │
│   文档标题  │    H3 …  │   （表格 / 代码 / 流程图）     │
│            │          │                             │
│ 📁 当前目录 │          │          阅读区              │
├────────────┴──────────┴─────────────────────────────┤
│  1,234 字                                    50%  A- A+ │
└──────────────────────────────────────────────────────┘
```

## 🚀 快速开始

### 方式一：直接下载使用

从 [Releases](../../releases) 下载 `Markdown Viewer.app`，拖入「应用程序」文件夹即可。

> 首次打开若提示"无法验证开发者"：右键点击应用 →「打开」，或在「系统设置 → 隐私与安全性」中允许。

### 方式二：从源码构建

```bash
git clone https://github.com/<你的用户名>/markdown-viewer.git
cd markdown-viewer
./build.sh
```

构建脚本会自动完成编译、打包资源、签名并启动应用。

**环境要求**：
- macOS 13+
- Xcode Command Line Tools（`xcode-select --install`）

## 📁 项目结构

```
markdown-viewer/
├── src/
│   └── MarkdownViewerApp.swift   # 全部源码（约 1300 行，单文件应用）
├── build.sh                      # 一键构建脚本
└── README.md
```

渲染引擎（marked.js、highlight.js、mermaid.js、GitHub CSS）位于 `src/`，构建时复制进 app bundle，**完全离线可用**，无需联网。

## 🔧 技术实现

- **纯原生**：SwiftUI 负责窗口与界面，WKWebView 负责 Markdown 渲染，通过 `WKScriptMessageHandler` 实现 JS ↔ Swift 双向通信（图片弹窗、查找、滚动定位、进度上报）
- **零依赖构建**：不使用 Xcode 工程和 SPM，`swiftc` 直接编译单文件，渲染引擎资源以 bundle 资源形式打包
- **本地图片**：通过自定义 `WKURLSchemeHandler` 安全加载本地文件，相对路径图片自动解析
- **健壮性**：自动处理 `\r` / `\r\n` 换行符文档的大纲提取；Mermaid 渲染失败时回退为显示原始代码块

## 🗺️ 功能路线图

- [ ] KaTeX 数学公式渲染
- [ ] 文件夹嵌套子目录树
- [ ] 多标签页
- [ ] 壁纸级自定义主题

## 📄 许可证

[MIT](LICENSE)

渲染引擎版权归属：
- [marked](https://github.com/markedjs/marked) — MIT © Christopher Jeffrey
- [highlight.js](https://github.com/highlightjs/highlight.js) — BSD-3-Clause
- [mermaid](https://github.com/mermaid-js/mermaid) — MIT
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) — MIT © Sindre Sorhus
