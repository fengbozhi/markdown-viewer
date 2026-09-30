import Foundation

/// 文档条目模型(左栏列表的一行)
struct DocItem: Identifiable, Hashable {
    let id: String          // 文件绝对路径
    let fileName: String    // 不含扩展名的文件名
    let docTitle: String    // Markdown 中的一级标题(可能为空)
    let dateLabel: String   // 修改日期

    var primaryText: String { fileName }
    var secondaryText: String { docTitle.isEmpty ? dateLabel : docTitle }
}
