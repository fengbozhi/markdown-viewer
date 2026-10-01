import Foundation

// MARK: - 图片粘贴服务(Typora 风格:粘贴图片自动存入文档旁 assets/ 并插入相对路径链接)

enum ImagePasteService {

    /// 保存位图数据到 `<文档目录>/assets/`,返回 Markdown 图片链接;失败返回 nil
    static func saveImage(data: Data, ext: String, docDir: URL) -> String? {
        let assets = docDir.appendingPathComponent("assets", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let name = uniqueName(ext: ext, in: assets)
        let url = assets.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return nil }
        return "![](assets/\(name))"
    }

    /// 剪贴板中的图片文件:已在文档目录内 → 直接用相对路径;否则复制进 assets/
    static func link(for fileURL: URL, docDir: URL) -> String? {
        let docPath = docDir.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(docPath + "/") {
            let rel = String(filePath.dropFirst(docPath.count + 1))
            let encoded = rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rel
            return "![](\(encoded))"
        }
        let assets = docDir.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension.lowercased()
        let name = uniqueName(ext: ext, in: assets)
        let dest = assets.appendingPathComponent(name)
        guard (try? FileManager.default.copyItem(at: fileURL, to: dest)) != nil else {
            return nil
        }
        return "![](assets/\(name))"
    }

    /// 生成不重名的粘贴文件名: pasted-20261001-000536.png,冲突时追加序号
    private static func uniqueName(ext: String, in dir: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var name = "pasted-\(stamp).\(ext)"
        var seq = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "pasted-\(stamp)-\(seq).\(ext)"
            seq += 1
        }
        return name
    }
}
