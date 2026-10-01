import Foundation

let md = """
---
title: 测试文档
tags: [markdown, 测试]
draft: false
---

# 测试文档

[TOC]

质能方程 $E=mc^2$ 与价格 $100 到 $200 不应混淆。

$$
\\\\int_0^1 x^2 dx = \\\\frac{1}{3}
$$

## 扩展语法

==重点内容==、H~2~O、x^2^、~~删除线~~。

脚注引用[^note1]示例。

[^note1]: 这是第一条脚注。

## Callout 提示框

> [!NOTE]
> 这是一个提示框内容。

> [!WARNING]
> 这是警告内容。

## Emoji 与任务列表

心情 :smile: 发射 :rocket: 爱心 :heart:

- [ ] 未完成任务
- [x] 已完成任务

```swift
let a = "$x$ 不应渲染 :smile: 不转换"
print(a)
```

```cmd
pip install modelscope
modelscope download --model BAAI/bge-reranker-large
```
"""
let html = MarkdownRenderer.buildHTML(markdown: md, dark: false)
try! html.write(toFile: "/tmp/mdv_test.html", atomically: true, encoding: .utf8)
// 校验 katex 字体路径改写
print("katex CSS rewritten:", html.contains("local://") && html.contains(".woff2"))
print("katex JS embedded:", html.contains("katex.render") )
