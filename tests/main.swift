import Foundation

// 轻量断言框架
var failures = 0
func check(_ cond: Bool, _ name: String) {
    print((cond ? "PASS  " : "FAIL  ") + name)
    if !cond { failures += 1 }
}
func eq(_ a: EditResult, _ range: NSRange, _ rep: String, _ sel: NSRange, _ name: String) {
    check(NSEqualRanges(a.range, range) && a.replacement == rep && NSEqualRanges(a.selection, sel),
          name + (NSEqualRanges(a.range, range) && a.replacement == rep && NSEqualRanges(a.selection, sel) ? "" : "  [got range=\(a.range) rep=\(a.replacement.debugDescription) sel=\(a.selection)]"))
}
func sel(_ l: Int, _ len: Int) -> NSRange { NSRange(location: l, length: len) }

// ---- 加粗/斜体/删除线(幂等切换) ----
var r = EditorCommands.apply(.bold, to: "abc", selection: sel(0, 3))
eq(r, sel(0, 3), "**abc**", sel(2, 3), "加粗:包裹选中")

r = EditorCommands.apply(.bold, to: "**abc**", selection: sel(2, 3))
eq(r, sel(0, 7), "abc", sel(0, 3), "加粗:标记在外侧则解包")

r = EditorCommands.apply(.bold, to: "**abc**", selection: sel(0, 7))
eq(r, sel(0, 7), "abc", sel(0, 3), "加粗:选区含标记则解包")

r = EditorCommands.apply(.bold, to: "", selection: sel(0, 0))
eq(r, sel(0, 0), "****", sel(2, 0), "加粗:空选区插入标记光标居中")

r = EditorCommands.apply(.italic, to: "abc", selection: sel(0, 3))
eq(r, sel(0, 3), "*abc*", sel(1, 3), "斜体:包裹选中")

// 加粗与斜体互不干扰:**abc** 上按斜体应在外层加 *
r = EditorCommands.apply(.italic, to: "**abc**", selection: sel(0, 7))
eq(r, sel(0, 7), "***abc***", sel(1, 7), "斜体:叠加在加粗外")

// ---- 行内代码/代码块 ----
r = EditorCommands.apply(.inlineCode, to: "abc", selection: sel(0, 3))
eq(r, sel(0, 3), "`abc`", sel(1, 3), "行内代码:包裹")

r = EditorCommands.apply(.inlineCode, to: "a\nb", selection: sel(0, 3))
eq(r, sel(0, 3), "```\na\nb\n```", sel(4, 3), "代码块:多行加围栏")

r = EditorCommands.apply(.inlineCode, to: "```\na\nb\n```", selection: sel(0, 11))
check(r.replacement == "a\nb", "代码块:解围栏")

// ---- 链接 ----
r = EditorCommands.apply(.link, to: "标题", selection: sel(0, 2))
check(r.replacement == "[标题](https://)", "链接:文本作标题")

r = EditorCommands.apply(.link, to: "https://a.com", selection: sel(0, 13))
check(r.replacement == "[](https://a.com)" && r.selection.location == 1, "链接:URL 作地址")

r = EditorCommands.apply(.link, to: "", selection: sel(0, 0))
check(r.replacement == "[标题](https://)" && r.selection.location == 1 && r.selection.length == 2, "链接:空选区模板并选中占位")

// ---- 标题(幂等) ----
r = EditorCommands.apply(.heading(2), to: "abc", selection: sel(0, 0))
eq(r, sel(0, 3), "## abc", sel(0, 6), "标题:设置 H2")

r = EditorCommands.apply(.heading(2), to: "## abc", selection: sel(0, 0))
eq(r, sel(0, 6), "abc", sel(0, 3), "标题:同级再按清除")

r = EditorCommands.apply(.heading(1), to: "## abc", selection: sel(0, 0))
eq(r, sel(0, 6), "# abc", sel(0, 5), "标题:切换级别")

r = EditorCommands.apply(.heading(1), to: "a\n\nb", selection: sel(0, 4))
eq(r, sel(0, 4), "# a\n\n# b", sel(0, 8), "标题:多行且跳过空行")

// ---- 引用/列表(幂等) ----
r = EditorCommands.apply(.quote, to: "a\nb", selection: sel(0, 3))
eq(r, sel(0, 3), "> a\n> b", sel(0, 7), "引用:添加")

r = EditorCommands.apply(.quote, to: "> a\n> b", selection: sel(0, 7))
eq(r, sel(0, 7), "a\nb", sel(0, 3), "引用:再按去除")

r = EditorCommands.apply(.bulletList, to: "a\nb", selection: sel(0, 3))
eq(r, sel(0, 3), "- a\n- b", sel(0, 7), "无序列表:添加")

r = EditorCommands.apply(.orderedList, to: "b\na", selection: sel(0, 3))
eq(r, sel(0, 3), "1. b\n2. a", sel(0, 9), "有序列表:自动编号")

r = EditorCommands.apply(.taskList, to: "a", selection: sel(0, 1))
eq(r, sel(0, 1), "- [ ] a", sel(0, 7), "任务列表:添加")

r = EditorCommands.apply(.bulletList, to: "1. a", selection: sel(0, 4))
eq(r, sel(0, 4), "- a", sel(0, 3), "列表:有序转无序")

// ---- 回车续行 ----
check(ListContinuation.enterAction(text: "- item", caret: 6) == .insert("\n- "), "续行:无序列表")
check(ListContinuation.enterAction(text: "  - [ ] task", caret: 12) == .insert("\n  - [ ] "), "续行:任务列表带缩进")
check(ListContinuation.enterAction(text: "3. item", caret: 7) == .insert("\n4. "), "续行:有序自增")
check(ListContinuation.enterAction(text: "> quote", caret: 7) == .insert("\n> "), "续行:引用")
check(ListContinuation.enterAction(text: "普通文本", caret: 4) == .plain, "续行:普通文本无处理")
if case .endList(let range) = ListContinuation.enterAction(text: "- ", caret: 2) {
    check(NSEqualRanges(range, sel(0, 2)), "续行:空标记结束列表")
} else { check(false, "续行:空标记结束列表") }
if case .endList = ListContinuation.enterAction(text: "- [ ] ", caret: 6) {
    check(true, "续行:空任务标记结束列表")
} else { check(false, "续行:空任务标记结束列表") }
check(ListContinuation.enterAction(text: "- a\n- ", caret: 6) == .endList(markerRange: sel(4, 2)), "续行:第二行空标记定位正确")

// ---- 自动配对 ----
if let a = AutoPair.action(text: "", selection: sel(0, 0), input: "(") {
    eq(a, sel(0, 0), "()", sel(1, 0), "配对:开括号补全")
} else { check(false, "配对:开括号补全") }
if let a = AutoPair.action(text: "abc", selection: sel(0, 3), input: "*") {
    eq(a, sel(0, 3), "*abc*", sel(1, 3), "配对:选中按 * 包裹")
} else { check(false, "配对:选中按 * 包裹") }
if let a = AutoPair.action(text: "()", selection: sel(1, 0), input: ")") {
    eq(a, sel(1, 1), ")", sel(2, 0), "配对:闭符号跳过")
} else { check(false, "配对:闭符号跳过") }
check(AutoPair.action(text: "", selection: sel(0, 0), input: "*") == nil, "配对:无选区 * 不自动配对")

// ---- 语法高亮 ----
let sample = "# 标题\n\n**加粗** 和 `code`\n\n```swift\nlet a = 1\n```\n\n> 引用\n- 列表\n$E=mc^2$\n"
let tokens = MarkdownHighlighter.tokens(in: sample)
check(tokens.contains { $0.1 == .heading(level: 1) && ($0.0.location == 0) }, "高亮:H1")
check(tokens.contains { $0.1 == .bold }, "高亮:加粗")
check(tokens.contains { $0.1 == .codeSpan }, "高亮:行内代码")
check(tokens.contains { $0.1 == .codeBlock }, "高亮:代码块")
check(tokens.contains { $0.1 == .quote }, "高亮:引用")
check(tokens.contains { $0.1 == .listMarker }, "高亮:列表标记")
check(tokens.contains { $0.1 == .math }, "高亮:数学公式")

// 高亮范围不得越界
let nsSample = sample as NSString
let allInBounds = tokens.allSatisfy { NSMaxRange($0.0) <= nsSample.length }
check(allInBounds, "高亮:所有范围在文本内")

print(failures == 0 ? "\nALL EDITOR TESTS PASSED" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
