import Foundation
import AppKit

/// 数据仓库:管理当前文件夹、文档列表与选中状态
@MainActor
final class FolderStore: ObservableObject {

    static let folderKey = "MarkdownViewer.lastFolderPath"

    @Published var folderURL: URL? {
        didSet {
            UserDefaults.standard.set(folderURL?.path, forKey: Self.folderKey)
            rescan()
            watchFolder()
        }
    }
    @Published var items: [DocItem] = []
    @Published var selectedPath: String?
    @Published var query: String = ""

    /// 目录变更监听:Finder 或其他程序增删文件时自动刷新列表
    private let folderWatcher = FileWatcher(debounceInterval: 0.5)

    var filteredItems: [DocItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.primaryText.localizedCaseInsensitiveContains(query)
                || $0.secondaryText.localizedCaseInsensitiveContains(query)
        }
    }

    init() {
        folderWatcher.onEvent = { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        if let saved = UserDefaults.standard.string(forKey: Self.folderKey) {
            let url = URL(fileURLWithPath: saved)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
                folderURL = url
            }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择包含 Markdown 文件的文件夹"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
        }
    }

    private func watchFolder() {
        if let folder = folderURL {
            folderWatcher.watch(path: folder.path)
        } else {
            folderWatcher.stop()
        }
    }

    func rescan() {
        guard let folder = folderURL else { items = []; return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.contentModificationDateKey],
                                             options: [.skipsHiddenFiles]) else {
            items = []
            return
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                urls.append(url)
            }
        }
        items = urls.map { makeItem(for: $0) }.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        // 当前选中文件不在新目录中时清除选中
        if let sel = selectedPath, !items.contains(where: { $0.id == sel }) {
            selectedPath = nil
        }
        // 未选中任何文档时,自动选中第一个
        if selectedPath == nil, let first = items.first {
            selectedPath = first.id
        }
    }

    private func makeItem(for url: URL) -> DocItem {
        let fileName = url.deletingPathExtension().lastPathComponent
        // 只读前 64KB 提取标题,避免大文件拖慢列表
        var title = ""
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            let prefix = data.prefix(64 * 1024)
            let text = String(decoding: prefix, as: UTF8.self)
            title = MarkdownRenderer.extractTitle(from: text)
        }
        var dateLabel = ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dateLabel = formatter.string(from: date)
        }
        return DocItem(id: url.standardizedFileURL.path,
                       fileName: fileName,
                       docTitle: title,
                       dateLabel: dateLabel)
    }
}
