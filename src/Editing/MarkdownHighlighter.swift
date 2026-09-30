import Foundation

// MARK: - Markdown 语法高亮(纯函数:输入文本,输出语义 token 列表)
// 视图层负责把 token 映射为字体/颜色,便于单元测试

enum MDToken: Equatable {
    case heading(level: Int)
    case bold
    case italic
    case strikethrough
    case codeSpan
    case codeBlock
    case link
    case quote
    case listMarker
    case math
}

enum MarkdownHighlighter {

    /// 提取语法 token,按优先级从低到高返回(后应用的高优先级覆盖)
    static func tokens(in text: String) -> [(NSRange, MDToken)] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [(NSRange, MDToken)] = []

        func collect(_ pattern: String, options: NSRegularExpression.Options = [.anchorsMatchLines],
                     _ map: (NSTextCheckingResult, NSString) -> (NSRange, MDToken)?) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            re.enumerateMatches(in: text, range: full) { m, _, _ in
                guard let m, let item = map(m, ns) else { return }
                result.append(item)
            }
        }

        // 低优先级:行级结构
        collect("^>+[^\\n]*$") { m, _ in (m.range, .quote) }
        collect("^(\\s*)([-*+]|\\d+[.)])( \\[[ xX]\\])?(?= )") { m, _ in (m.range, .listMarker) }
        collect("^(#{1,6}) [^\\n]*$") { m, ns in
            (m.range, .heading(level: ns.substring(with: m.range(at: 1)).count))
        }

        // 行内样式
        collect("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__") { m, _ in (m.range, .bold) }
        collect("(?<!\\*)\\*[^*\\n]+\\*(?!\\*)|(?<!_)_[^_\\n]+_(?!_)") { m, _ in (m.range, .italic) }
        collect("~~[^~\\n]+~~") { m, _ in (m.range, .strikethrough) }
        collect("\\[[^\\]\\n]*\\]\\([^)\\n]*\\)") { m, _ in (m.range, .link) }

        // 高优先级:代码与公式(覆盖内部样式)
        collect("`[^`\\n]+`") { m, _ in (m.range, .codeSpan) }
        collect("\\$\\$[\\s\\S]+?\\$\\$|\\$[^$\\n]+\\$") { m, _ in (m.range, .math) }
        collect("^(```|~~~)[\\s\\S]*?^(\\1)$", options: [.anchorsMatchLines]) { m, _ in (m.range, .codeBlock) }

        return result
    }
}
