import Foundation
import WebKit

/// 本地资源协议处理器(让 WKWebView 能读取本地图片与字体等资源)
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "local"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let path = url.path.removingPercentEncoding else {
            task.didFailWithError(NSError(domain: "LocalFileScheme", code: 404))
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              !isDir.boolValue,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            task.didFailWithError(NSError(domain: "LocalFileScheme", code: 404,
                                          userInfo: [NSLocalizedDescriptionKey: "文件不存在: \(path)"]))
            return
        }
        let response = URLResponse(url: url,
                                   mimeType: Self.mime(forExtension: url.pathExtension.lowercased()),
                                   expectedContentLength: data.count,
                                   textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func mime(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "ico": return "image/x-icon"
        case "pdf": return "application/pdf"
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "css": return "text/css"
        case "js": return "text/javascript"
        case "json": return "application/json"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        default: return "application/octet-stream"
        }
    }
}
