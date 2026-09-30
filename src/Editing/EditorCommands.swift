import Foundation

// MARK: - 编辑器命令(纯函数,不依赖 AppKit,可单元测试)
// 所有函数输入 (当前文本, 当前选区),输出最小替换范围 + 替换文本 + 新选区
// 约定:范围与长度均为 UTF-16 口径(与 NSString/NSTextView 一致)

/// 一次编辑操作的结果
struct EditResult: Equatable {
    let range: NSRange        // 在当前文本中的最小替换范围
    let replacement: String   // 替换内容
    let selection: NSRange    // 替换后的选区(基于替换后文本)
}

/// 支持的格式化命令
enum EditorCommand {
    case bold, italic, strikethrough, inlineCode, link
    case heading(Int)   // 1-6 设置标题级别,0 清除标题
    case quote, bulletList, orderedList, taskList
}

enum EditorCommands {

    // MARK: 入口

    static func apply(_ command: EditorCommand, to text: String, selection: NSRange) -> EditResult {
        switch command {
        case .bold: return toggleWrap(text: text, selection: selection, marker: "**")
        case .italic: return toggleWrap(text: text, selection: selection, marker: "*")
        case .strikethrough: return toggleWrap(text: text, selection: selection, marker: "~~")
        case .inlineCode: return toggleCode(text: text, selection: selection)
        case .link: return insertLink(text: text, selection: selection)
        case .heading(let level): return setHeading(text: text, selection: selection, level: level)
        case .quote: return toggleLinePrefix(text: text, selection: selection, kind: .quote)
        case .bulletList: return toggleLinePrefix(text: text, selection: selection, kind: .bullet)
        case .orderedList: return toggleLinePrefix(text: text, selection: selection, kind: .ordered)
        case .taskList: return toggleLinePrefix(text: text, selection: selection, kind: .task)
        }
    }

    // MARK: 包裹类命令(加粗/斜体/删除线)

    /// 幂等包裹:已包裹则解包(标记在选区内或紧贴选区外侧均可识别),否则包裹
    static func toggleWrap(text: String, selection sel: NSRange, marker: String) -> EditResult {
        let ns = text as NSString
        let mlen = (marker as NSString).length
        let selText = ns.substring(with: sel)
        let markerChar = marker.first!

        /// 连续相同标记字符的个数(区分 * 与 **:斜体不能把加粗误当已包裹)
        func runLength(_ s: String, fromStart: Bool) -> Int {
            let chars = fromStart ? Array(s) : Array(s.reversed())
            var n = 0
            for c in chars {
                if c == markerChar { n += 1 } else { break }
            }
            return n
        }
        /// 是否可以视为「已包裹 marker」:
        /// 单字符标记(如 *)要求连续字符数恰好等于标记长度,否则会把 ** 误判为 *;
        /// 多字符标记(如 **)允许更长的连续串,剥离一层即可
        func isWrappedRun(_ run: Int) -> Bool {
            mlen == 1 ? run == 1 : run >= mlen
        }

        // 1) 选区内部已包含标记 → 解包
        if sel.length >= mlen * 2, selText.hasPrefix(marker), selText.hasSuffix(marker),
           isWrappedRun(runLength(selText, fromStart: true)),
           isWrappedRun(runLength(selText, fromStart: false)) {
            let inner = (selText as NSString).substring(with: NSRange(location: mlen, length: sel.length - 2 * mlen))
            return EditResult(range: sel,
                              replacement: inner,
                              selection: NSRange(location: sel.location, length: (inner as NSString).length))
        }
        // 2) 标记紧贴选区外侧 → 解包
        if sel.location >= mlen, ns.length >= sel.location + sel.length + mlen {
            let before = ns.substring(with: NSRange(location: sel.location - mlen, length: mlen))
            let after = ns.substring(with: NSRange(location: sel.location + sel.length, length: mlen))
            if before == marker, after == marker {
                // 向外扩展连续标记字符,判断真实 run 长度
                let outerText = ns.substring(with: NSRange(location: sel.location - mlen, length: sel.length + 2 * mlen))
                let leadingRun = mlen + extraRun(ns, from: sel.location - mlen, step: -1, char: markerChar)
                let trailingRun = mlen + extraRun(ns, from: sel.location + sel.length + mlen, step: 1, char: markerChar)
                if isWrappedRun(leadingRun), isWrappedRun(trailingRun), outerText.count > 0 {
                    return EditResult(range: NSRange(location: sel.location - mlen, length: sel.length + 2 * mlen),
                                      replacement: selText,
                                      selection: NSRange(location: sel.location - mlen, length: sel.length))
                }
            }
        }
        // 3) 包裹(空选区时光标落在标记中间)
        return EditResult(range: sel,
                          replacement: marker + selText + marker,
                          selection: NSRange(location: sel.location + mlen, length: sel.length))
    }

    /// 从某位置向指定方向连续相同字符的额外个数(不含起点)
    private static func extraRun(_ ns: NSString, from start: Int, step: Int, char: Character) -> Int {
        var n = 0
        var i = start + step
        let target = String(char)
        while i >= 0, i < ns.length {
            if ns.substring(with: NSRange(location: i, length: 1)) == target {
                n += 1
                i += step
            } else {
                break
            }
        }
        return n
    }

    // MARK: 行内代码 / 代码块

    static func toggleCode(text: String, selection sel: NSRange) -> EditResult {
        let ns = text as NSString
        let selText = ns.substring(with: sel)
        if selText.contains("\n") {
            // 多行 → 代码围栏
            let fence = "```"
            if selText.hasPrefix(fence), selText.hasSuffix(fence) {
                var inner = selText as NSString
                inner = inner.substring(with: NSRange(location: 3, length: inner.length - 6)) as NSString
                var s = inner as String
                if s.hasPrefix("\n") { s.removeFirst() }
                if s.hasSuffix("\n") { s.removeLast() }
                return EditResult(range: sel, replacement: s,
                                  selection: NSRange(location: sel.location, length: (s as NSString).length))
            }
            let fenced = fence + "\n" + selText + "\n" + fence
            return EditResult(range: sel, replacement: fenced,
                              selection: NSRange(location: sel.location + 4, length: sel.length))
        }
        return toggleWrap(text: text, selection: sel, marker: "`")
    }

    // MARK: 链接

    static func insertLink(text: String, selection sel: NSRange) -> EditResult {
        let ns = text as NSString
        let selText = ns.substring(with: sel)
        let isURL = selText.lowercased().hasPrefix("http://") || selText.lowercased().hasPrefix("https://")

        if sel.length == 0 {
            // 空选区:插入模板并选中标题占位
            let template = "[标题](https://)"
            return EditResult(range: sel, replacement: template,
                              selection: NSRange(location: sel.location + 1, length: 2))
        }
        if isURL {
            // 选中的是 URL → 作为链接地址,标题留空待填
            let wrapped = "[](" + selText + ")"
            return EditResult(range: sel, replacement: wrapped,
                              selection: NSRange(location: sel.location + 1, length: 0))
        }
        // 选中文本作为标题,URL 占位并选中
        let wrapped = "[" + selText + "](https://)"
        return EditResult(range: sel, replacement: wrapped,
                          selection: NSRange(location: sel.location + sel.length + 3, length: 8))
    }

    // MARK: 标题

    /// 设置选区覆盖的所有行的标题级别;同级再按一次则清除(幂等)
    static func setHeading(text: String, selection sel: NSRange, level: Int) -> EditResult {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        let pattern = try? NSRegularExpression(pattern: "^(\\s*)(#{1,6})?[ ]?(.*)$")
        guard let pattern else {
            return EditResult(range: lineRange, replacement: block, selection: sel)
        }
        var newLines: [String] = []
        for line in lines {
            let lns = line as NSString
            guard lns.length > 0,
                  let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: lns.length)) else {
                newLines.append(line)
                continue
            }
            let indent = lns.substring(with: m.range(at: 1))
            let content = lns.substring(with: m.range(at: 3))
            if content.isEmpty {
                newLines.append(line)
                continue
            }
            let currentLevel = m.range(at: 2).location == NSNotFound ? 0 : lns.substring(with: m.range(at: 2)).count
            if level == 0 || currentLevel == level {
                newLines.append(indent + content)   // 清除(幂等切换)
            } else {
                newLines.append(indent + String(repeating: "#", count: level) + " " + content)
            }
        }
        let newBlock = newLines.joined(separator: "\n")
        return EditResult(range: lineRange, replacement: newBlock,
                          selection: NSRange(location: lineRange.location, length: (newBlock as NSString).length))
    }

    // MARK: 行前缀类命令(引用/列表)

    enum LinePrefixKind {
        case quote, bullet, ordered, task

        /// 匹配行首标记,返回 (标记范围, 是否为本类型标记)
        func match(in line: String) -> NSRange? {
            let patternString: String
            switch self {
            case .quote: patternString = "^\\s*>+[ ]?"
            case .bullet: patternString = "^\\s*[-*+][ ]"
            case .ordered: patternString = "^\\s*\\d+[.)][ ]"
            case .task: patternString = "^\\s*[-*+] \\[[ xX]\\][ ]"
            }
            guard let re = try? NSRegularExpression(pattern: patternString) else { return nil }
            let ns = line as NSString
            return re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range
        }

        func marker(index: Int) -> String {
            switch self {
            case .quote: return "> "
            case .bullet: return "- "
            case .ordered: return "\(index + 1). "
            case .task: return "- [ ] "
            }
        }
    }

    /// 幂等行前缀:选区内所有非空行都有该标记 → 统一去除;否则统一添加
    static func toggleLinePrefix(text: String, selection sel: NSRange, kind: LinePrefixKind) -> EditResult {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpty.isEmpty else {
            return EditResult(range: lineRange, replacement: block, selection: sel)
        }
        let allMarked = nonEmpty.allSatisfy { kind.match(in: $0) != nil }

        var newLines: [String] = []
        var orderIndex = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                newLines.append(line)
                continue
            }
            if allMarked {
                // 去除标记
                if let r = kind.match(in: line) {
                    newLines.append((line as NSString).replacingCharacters(in: r, with: ""))
                } else {
                    newLines.append(line)
                }
            } else {
                // 先去掉可能存在的其他列表/引用标记,再加新标记
                var content = line
                for other in [LinePrefixKind.task, .quote, .bullet, .ordered] {
                    if let r = other.match(in: content) {
                        content = (content as NSString).replacingCharacters(in: r, with: "")
                        break
                    }
                }
                newLines.append(kind.marker(index: orderIndex) + content)
                orderIndex += 1
            }
        }
        let newBlock = newLines.joined(separator: "\n")
        return EditResult(range: lineRange, replacement: newBlock,
                          selection: NSRange(location: lineRange.location, length: (newBlock as NSString).length))
    }
}

// MARK: - 回车列表续行(纯函数)

/// 回车行为:继续列表 / 结束列表
enum EnterAction: Equatable {
    /// 插入指定文本(如 "\n- ")
    case insert(String)
    /// 当前行只剩空标记(如 "- "):删除该标记范围后走默认换行,即结束列表
    case endList(markerRange: NSRange)
    /// 无特殊处理
    case plain

    static func == (lhs: EnterAction, rhs: EnterAction) -> Bool {
        switch (lhs, rhs) {
        case (.insert(let a), .insert(let b)): return a == b
        case (.endList(let a), .endList(let b)): return NSEqualRanges(a, b)
        case (.plain, .plain): return true
        default: return false
        }
    }
}

enum ListContinuation {

    /// 根据光标前行内容计算回车行为。caret 为 UTF-16 位置。
    static func enterAction(text: String, caret: Int) -> EnterAction {
        let ns = text as NSString
        let clamped = max(0, min(caret, ns.length))
        // 光标所在行的起点
        var lineStart = 0
        if clamped > 0 {
            let r = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: clamped))
            if r.location != NSNotFound { lineStart = r.location + 1 }
        }
        let prefix = ns.substring(with: NSRange(location: lineStart, length: clamped - lineStart))

        // 任务列表:indent + bullet + [ ] + 内容
        if let m = match(pattern: "^(\\s*)([-*+]) \\[[ xX]\\] ?(.*)$", in: prefix) {
            return action(prefix: prefix, lineStart: lineStart,
                          indent: m[0], marker: "\(m[1]) [ ] ", content: m[2])
        }
        // 无序列表
        if let m = match(pattern: "^(\\s*)([-*+]) (.*)$", in: prefix) {
            return action(prefix: prefix, lineStart: lineStart,
                          indent: m[0], marker: "\(m[1]) ", content: m[2])
        }
        // 有序列表(序号自增)
        if let m = match(pattern: "^(\\s*)(\\d+)([.)]) (.*)$", in: prefix),
           let n = Int(m[1]) {
            return action(prefix: prefix, lineStart: lineStart,
                          indent: m[0], marker: "\(n + 1)\(m[2]) ", content: m[3])
        }
        // 引用
        if let m = match(pattern: "^(\\s*)((?:>+ )*)(.*)$", in: prefix), !m[1].isEmpty {
            return action(prefix: prefix, lineStart: lineStart,
                          indent: m[0], marker: m[1], content: m[2])
        }
        return .plain
    }

    /// 通用决策:内容为空 → 结束列表;否则插入 "\n" + 缩进 + 标记
    private static func action(prefix: String, lineStart: Int, indent: String, marker: String, content: String) -> EnterAction {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // 空标记行:删除 "缩进+标记",结束列表
            let markerLen = ((indent + marker) as NSString).length
            return .endList(markerRange: NSRange(location: lineStart, length: markerLen))
        }
        return .insert("\n" + indent + marker)
    }

    /// 正则辅助:返回各捕获组字符串(组 0 除外),无匹配返回 nil
    private static func match(pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return groups
    }
}

// MARK: - 自动配对(纯函数)

enum AutoPair {
    /// 输入开符号时需要补全的闭符号
    static let closingFor: [String: String] = [
        "(": ")", "[": "]", "{": "}", "`": "`", "\"": "\"", "'": "'",
    ]
    /// 仅在有选区时用于包裹的符号(* 与 _ 不自动配对,避免输入 ** 时干扰)
    static let wrapOnlySymbols: Set<String> = ["*", "_"]

    /// 判断输入单个字符时的行为
    static func action(text: String, selection sel: NSRange, input: String) -> EditResult? {
        let ns = text as NSString
        // 有选区:开符号/包裹符号 → 包裹选中内容
        if sel.length > 0 {
            if let closing = closingFor[input] ?? (wrapOnlySymbols.contains(input) ? input : nil) {
                let selText = ns.substring(with: sel)
                return EditResult(range: sel,
                                  replacement: input + selText + closing,
                                  selection: NSRange(location: sel.location + 1, length: sel.length))
            }
            return nil
        }
        // 无选区:输入闭符号且下一个字符就是它 → 跳过(不重复插入)
        if closingFor.values.contains(input), sel.location < ns.length {
            let next = ns.substring(with: NSRange(location: sel.location, length: 1))
            if next == input {
                return EditResult(range: NSRange(location: sel.location, length: 1),
                                  replacement: input,
                                  selection: NSRange(location: sel.location + 1, length: 0))
            }
        }
        // 无选区:开符号 → 自动补全闭符号,光标居中
        if let closing = closingFor[input] {
            return EditResult(range: sel,
                              replacement: input + closing,
                              selection: NSRange(location: sel.location + 1, length: 0))
        }
        return nil
    }
}
