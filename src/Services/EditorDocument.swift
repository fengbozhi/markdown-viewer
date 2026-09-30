import Foundation

/// 编辑文档状态:文本 + 脏标记 + 保存
/// 脏标记为计算属性(text != savedText),不可能出现状态不一致
@MainActor
final class EditorDocument: ObservableObject {

    @Published var text: String = ""
    @Published private(set) var savedText: String = ""

    private(set) var filePath: String?

    /// 最近一次「自己保存」的时间,用于让文件监听器忽略自己引发的变更事件
    private(set) var lastInternalSave: Date = .distantPast

    var isDirty: Bool { text != savedText }

    /// 从磁盘加载(解码失败也不会产生 nil)
    func load(path: String) {
        filePath = path
        let content: String
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            content = TextNormalizer.normalizeNewlines(String(decoding: data, as: UTF8.self))
        } else {
            content = ""
        }
        text = content
        savedText = content
    }

    /// 原子保存(先写临时文件再替换,不会写坏原文件)
    func save() throws {
        guard let filePath else { return }
        try text.write(toFile: filePath, atomically: true, encoding: .utf8)
        savedText = text
        lastInternalSave = Date()
    }

    /// 放弃修改,回滚到已保存内容
    func revert() {
        text = savedText
    }
}
