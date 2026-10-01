import Foundation

// MARK: - 任务列表复选框翻转(纯函数,不依赖 AppKit,可单元测试)

enum TaskToggle {

    /// 把文档中第 index 个(0 起,按文档顺序)任务复选框 `- [ ]` / `- [x]` 取反。
    /// 返回翻转后的完整文本;index 越界或文档中没有任务列表时返回 nil。
    static func flip(in text: String, index: Int) -> String? {
        guard index >= 0 else { return nil }
        let ns = text as NSString
        guard let re = try? NSRegularExpression(
            pattern: "^([ \\t]*[-*+] )\\[([ xX])\\]",
            options: [.anchorsMatchLines]) else { return nil }
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard index < matches.count else { return nil }
        let boxRange = matches[index].range(at: 2)
        let current = ns.substring(with: boxRange)
        let flipped = current == " " ? "x" : " "
        return ns.replacingCharacters(in: boxRange, with: flipped)
    }
}
