import Foundation

/// 大纲条目(标题层级)
struct Heading: Identifiable, Hashable, Sendable {
    let id: Int      // 文档内序号,与 DOM 中 heading 出现顺序一致
    let level: Int   // 1-6
    let text: String

    /// 解析 Markdown 中的标题(跳过代码块内的 # 行与 YAML front matter)
    static func extract(from markdown: String) -> [Heading] {
        let normalized = TextNormalizer.normalizeNewlines(markdown)
        var lines = Array(normalized.split(separator: "\n", omittingEmptySubsequences: false))

        // 跳过 YAML front matter
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" {
            if let closeIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                lines = Array(lines[(closeIdx + 1)...])
            }
        }

        var result: [Heading] = []
        var inFence = false
        let pattern = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+?)\\s*#*\\s*$")
        guard let pattern else { return [] }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            let ns = t as NSString
            if let m = pattern.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
                let level = ns.substring(with: m.range(at: 1)).count
                let text = ns.substring(with: m.range(at: 2))
                result.append(Heading(id: result.count, level: level, text: text))
            }
        }
        return result
    }
}

/// 文本规范化工具
enum TextNormalizer {
    /// 统一换行符为 \n(兼容 Windows \r\n 与老式 Mac \r,否则按行解析会全部失效)
    static func normalizeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .replacingOccurrences(of: "\r", with: "\n")
    }
}
