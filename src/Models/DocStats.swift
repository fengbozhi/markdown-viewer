import Foundation

/// 文档统计:字数(非空白字符)/ 字符数 / 行数
struct DocStats: Equatable {
    var words = 0
    var chars = 0
    var lines = 0

    init() {}

    init(words: Int, chars: Int, lines: Int) {
        self.words = words
        self.chars = chars
        self.lines = lines
    }

    init(text: String) {
        chars = text.count
        words = text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
        lines = text.isEmpty ? 0 : text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } + 1
    }
}
