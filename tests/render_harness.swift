import Foundation

let md = """
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

```swift
let a = "$x$ 不应渲染"
print(a)
```
"""
let html = MarkdownRenderer.buildHTML(markdown: md, dark: false)
try! html.write(toFile: "/tmp/mdv_test.html", atomically: true, encoding: .utf8)
// 校验 katex 字体路径改写
print("katex CSS rewritten:", html.contains("local://") && html.contains(".woff2"))
print("katex JS embedded:", html.contains("katex.render") )
