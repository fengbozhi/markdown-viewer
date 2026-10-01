# 测试说明

## 单元测试(编辑器核心逻辑,67 用例)

构建时自动运行(`build.sh` 第一步,失败即中止)。手动运行:

```bash
swiftc -O -o /tmp/mdv_editor_tests tests/main.swift \
  src/Editing/EditorCommands.swift src/Editing/MarkdownHighlighter.swift src/Editing/TaskToggle.swift \
  src/Models/FuzzyMatch.swift src/Models/DocStats.swift \
  -framework Foundation
/tmp/mdv_editor_tests
```

覆盖:加粗/斜体/删除线幂等切换、行内代码/代码块、链接、标题、引用/三种列表、
回车续行(有序自增/空标记结束)、自动配对、语法高亮范围、表格插入、
任务复选框翻转、模糊匹配打分、文档统计。

## 渲染管线端到端测试(29 断言,需 Node + jsdom)

```bash
# 1. 用 harness 生成真实 HTML(顶层表达式需以 main.swift 命名编译)
mkdir -p /tmp/mdv_hb && cp tests/render_harness.swift /tmp/mdv_hb/main.swift
swiftc -O -o /tmp/mdv_harness /tmp/mdv_hb/main.swift \
  src/Rendering/MarkdownRenderer.swift src/Rendering/LocalFileSchemeHandler.swift \
  src/Models/Heading.swift -framework Foundation -framework WebKit
/tmp/mdv_harness   # 输出 /tmp/mdv_test.html

# 2. jsdom 中执行完整渲染管线并断言
npm install jsdom   # 任意工作目录
node tests/render_e2e.js
```

覆盖:KaTeX 行内/块级公式、TOC、脚注、==高亮==、~下标~、^上标^、删除线、
代码复制按钮/语言标签/行号、代码块内 $ 与 :emoji: 不渲染、MDV 搜索接口、
Callout 提示框、Emoji 短代码、Front Matter 属性面板、任务复选框可点击。
