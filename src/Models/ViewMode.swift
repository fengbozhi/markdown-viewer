import Foundation

/// 视图模式:预览 / 分屏 / 编辑
enum ViewMode: String, CaseIterable, Identifiable {
    case preview, split, edit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: return "预览"
        case .split: return "分屏"
        case .edit: return "编辑"
        }
    }

    var icon: String {
        switch self {
        case .preview: return "eye"
        case .split: return "rectangle.split.2x1"
        case .edit: return "pencil.line"
        }
    }
}
