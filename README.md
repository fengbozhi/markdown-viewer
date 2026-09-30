# Markdown 阅读器（Markdown Viewer）

一款原生 macOS Markdown **阅读 + 编辑**工具，致力于成为最好用的 Markdown 文档查看器。基于 Swift + SwiftUI + WebKit + NSTextView 构建，无任何第三方运行时依赖，开箱即用，**完全离线**。

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![License](https://img.shields.io/badge/license-MIT-green) ![Tests](https://img.shields.io/badge/tests-42%2B17%20passed-brightgreen)

## ✨ 功能特性

### 编辑功能（v2 新增）
- **三种视图模式**：预览（⌘1）/ 分屏实时预览（⌘2）/ 纯编辑（⌘3），一键切换
- **原生编辑器**：基于 NSTextView，完整支持撤销/重做、输入法、系统查找（⌘F）
- **Markdown 语法高亮**：标题/加粗/斜体/代码/链接/引用/列表/公式实时着色
- **格式化命令**：⌘B 加粗、⌘I 斜体、⇧⌘X 删除线、⌘K 链接、行内代码/代码块、H1-H3、引用、无序/有序/任务列表——全部**幂等可切换**（再按一次还原）
- **智能输入**：括号/引号/反引号自动配对、选中内容按 `*`/`_` 直接包裹、回车自动续列表（有序列表自增编号、空标记回车自动结束列表）、Tab 缩进
- **数据安全三道防线**：
  1. ⌘S 原子保存（先写临时文件再替换，绝不写坏原文件），标题栏 `●` 脏标记
  2. 切换文档 / 关闭窗口时若有未保存修改 → 弹窗确认，永不静默丢稿
  3. 文件被外部修改且本地有未保存编辑 → 冲突弹窗，绝不静默覆盖
- **分屏实时预览**：编辑内容 0.35s 防抖后渲染，预览保持滚动位置

### 阅读体验
- **三栏布局**：文档列表 / 大纲面板 / 正文阅读区，左栏与大纲均可收起（状态自动记忆）
- **完整渲染**：基于 [marked.js](https://github.com/markedjs/marked) + [GitHub 风格样式](https://github.com/sindresorhus/github-markdown-css)，完整支持 GFM 语法
- **数学公式**：内置 [KaTeX](https://katex.org)，`$行内$` 与 `$$块级$$`（Pandoc 规则，`$100 到 $200` 价格不会误判）
- **Mermaid 流程图**：```mermaid``` 代码块自动渲染为图表
- **扩展语法**：`==高亮==`、`~下标~`、`^上标^`、`[^脚注]`、`[TOC]` 目录（可点击跳转）
- **深色模式**：一键切换明暗主题，编辑器与渲染区同步适配
- **图片高清显示**：双击图片弹窗全屏查看，支持缩放与拖动

### 效率功能
- **大纲导航**：点击平滑跳转；滚动时大纲自动高亮当前章节
- **文件自动重载**：外部编辑器保存后自动刷新，保持滚动位置；目录增删文件自动刷新列表
- **代码块增强**：Carbon 风格窗口 + 语言标签 + 一键复制按钮 + 行号
- **文档内查找**（⌘F）：全部命中高亮，回车逐项跳转，显示"第 n / 共 m 处"
- **底部状态栏**：字数统计 + 预计阅读时长 + 阅读进度百分比
- **字体缩放**：⌘+ / ⌘- / ⌘0，50% ~ 200%
- **导出独立 HTML**（⌘⇧E）：图片与字体内嵌 base64，单文件可直接分发（有未保存修改时导出编辑器最新内容）
- **导出 PDF**（⌘P）/ **在 Finder 中显示**（⌘⇧R）/ **用默认编辑器打开**（⌘⇧O）
- **会话记忆**：自动恢复上次打开的文件夹、选中状态、面板开关、主题、缩放与视图模式

## 🚀 快速开始

### 方式一：直接下载使用

从 [Releases](../../releases) 下载 `Markdown Viewer.app`，拖入「应用程序」文件夹即可。

> 首次打开若提示"无法验证开发者"：右键点击应用 →「打开」，或在「系统设置 → 隐私与安全性」中允许。

### 方式二：从源码构建

```bash
git clone https://github.com/fengbozhi/markdown-viewer.git
cd markdown-viewer
./build.sh        # 构建前自动运行 42 项单元测试,失败即中止
```

**环境要求**：macOS 13+，Xcode Command Line Tools（`xcode-select --install`）

## 📁 项目结构

按软件工程规范分层组织，核心逻辑纯函数化、可测试：

```
markdown-viewer/
├── src/
│   ├── App/MarkdownViewerApp.swift      # App 入口、生命周期、菜单栏命令
│   ├── Models/
│   │   ├── DocItem.swift                # 文档条目模型
│   │   ├── Heading.swift                # 大纲模型 + 文本规范化
│   │   └── ViewMode.swift               # 预览/分屏/编辑模式
│   ├── Editing/                         # 编辑器核心(纯函数,不依赖 AppKit)
│   │   ├── EditorCommands.swift         # 格式化命令/列表续行/自动配对
│   │   └── MarkdownHighlighter.swift    # 语法高亮 token 提取
│   ├── Rendering/
│   │   ├── MarkdownRenderer.swift       # Markdown → HTML 渲染管线
│   │   └── LocalFileSchemeHandler.swift # local:// 本地资源协议
│   ├── Services/
│   │   ├── FolderStore.swift            # 文件夹数据仓库
│   │   ├── EditorDocument.swift         # 文档状态/脏标记/原子保存
│   │   └── FileWatcher.swift            # 文件/目录变更监听
│   ├── Views/
│   │   ├── ContentView.swift            # 主界面/工具栏/数据安全防护
│   │   ├── SidebarView.swift            # 文档列表侧栏
│   │   ├── OutlineView.swift            # 大纲面板(滚动同步)
│   │   ├── DetailView.swift             # 三模式内容区/查找栏/状态栏
│   │   ├── MarkdownWebView.swift        # WKWebView 封装(文件/内存双渲染源)
│   │   ├── MarkdownEditorView.swift     # NSTextView 编辑器封装
│   │   └── ImagePopup.swift             # 图片全屏弹窗
│   └── Resources/                       # 渲染引擎(完全离线)
│       ├── marked/highlight/mermaid/katex + 样式
│       └── fonts/                       # KaTeX woff2 字体(20 个,296KB)
├── tests/
│   ├── main.swift                       # 编辑器单元测试(42 用例,构建门禁)
│   ├── render_harness.swift             # 渲染 HTML 生成器
│   ├── render_e2e.js                    # 渲染管线端到端测试(17 断言,jsdom)
│   └── README.md                        # 测试运行说明
├── build.sh                             # 一键构建(测试 → 编译 → 打包 → 签名)
└── README.md
```

## 🔧 质量保障

- **单元测试**：编辑器所有格式化命令、列表续行、自动配对、语法高亮均为纯函数，42 个用例覆盖正常/边界/幂等路径，作为 `build.sh` 构建门禁
- **端到端测试**：渲染管线（marked/KaTeX/Mermaid/TOC/脚注等 12 步）在 jsdom 中执行真实产物并做 17 项断言
- **防御式设计**：脏标记是计算属性（`text != savedText`，不可能状态不一致）；原子保存；外部冲突永不静默覆盖；超过 30 万字符的文档编辑器只高亮可视区域

## 🗺️ 功能路线图

- [x] KaTeX 数学公式渲染
- [x] [TOC] 目录 / 脚注 / 高亮 / 上下标扩展语法
- [x] 文件变更自动重载
- [x] 导出独立 HTML
- [x] 编辑功能（三种模式 / 语法高亮 / 格式化命令 / 智能输入 / 数据安全）
- [ ] 文件夹嵌套子目录树
- [ ] 多标签页
- [ ] 跨文件全文搜索
- [ ] 编辑器与预览滚动同步
- [ ] 壁纸级自定义主题

## 📄 许可证

[MIT](LICENSE)

渲染引擎版权归属：
- [marked](https://github.com/markedjs/marked) — MIT © Christopher Jeffrey
- [highlight.js](https://github.com/highlightjs/highlight.js) — BSD-3-Clause
- [mermaid](https://github.com/mermaid-js/mermaid) — MIT
- [KaTeX](https://github.com/KaTeX/KaTeX) — MIT © Khan Academy
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) — MIT © Sindre Sorhus
