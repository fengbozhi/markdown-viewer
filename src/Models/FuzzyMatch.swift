import Foundation

/// 快速打开用的模糊匹配(子序列匹配,大小写不敏感)
enum FuzzyMatch {

    /// query 的字符是否按顺序出现在 target 中
    static func matches(_ target: String, _ query: String) -> Bool {
        score(target, query) >= 0
    }

    /// 匹配打分:不匹配返回 -1;连续匹配与开头匹配加权,分越高越靠前
    static func score(_ target: String, _ query: String) -> Int {
        let t = Array(target.lowercased())
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        guard !t.isEmpty, q.count <= t.count else { return -1 }
        var total = 0
        var qi = 0
        var streak = 0
        for (i, c) in t.enumerated() where qi < q.count {
            if c == q[qi] {
                streak += 1
                total += 1 + streak * 2 + (i == 0 ? 5 : 0)
                qi += 1
            } else {
                streak = 0
            }
        }
        return qi == q.count ? total : -1
    }
}
