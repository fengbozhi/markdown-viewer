// Markdown 阅读器 - macOS 两栏 Markdown 阅读器(参考 Typora)
// 左栏:文件列表(文件名 + 文档标题,可收起)  中栏:大纲(可收起)  右栏:完整渲染
// 双击图片:弹窗全屏查看,支持捏合缩放与拖动

import SwiftUI
import WebKit
import AppKit

// MARK: - 文档条目模型

struct DocItem: Identifiable, Hashable {
    let id: String          // 文件绝对路径
    let fileName: String    // 不含扩展名的文件名
    let docTitle: String    // Markdown 中的一级标题(可能为空)
    let dateLabel: String   // 修改日期

    var primaryText: String { fileName }
    var secondaryText: String { docTitle.isEmpty ? dateLabel : docTitle }
}

// MARK: - 本地资源协议处理器(让 WKWebView 能读取本地图片)

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
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Markdown 渲染器(内置 marked.js + highlight.js,离线可用)

enum MarkdownRenderer {

    static let markedJS: String = loadResource("marked.min", "js") ?? ""
    static let hljsJS: String = loadResource("highlight.min", "js") ?? ""
    static let mermaidJS: String = loadResource("mermaid.min", "js") ?? ""
    static let githubCSS: String = loadResource("github-markdown-light", "css") ?? ""
    static let hljsCSS: String = loadResource("github", "css") ?? ""
    static let githubDarkCSS: String = loadResource("github-markdown-dark", "css") ?? ""
    static let hljsDarkCSS: String = loadResource("github-dark", "css") ?? ""

    static func loadResource(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let str = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return str
    }

    /// 统一换行符为 \n(兼容 Windows \r\n 与老式 Mac \r,否则按行解析会全部失效)
    static func normalizeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .replacingOccurrences(of: "\r", with: "\n")
    }

    /// 读取文件(解码失败时也不会返回 nil)
    static func readFile(_ url: URL) -> String {
        if let data = try? Data(contentsOf: url) {
            return normalizeNewlines(String(decoding: data, as: UTF8.self))
        }
        return "*(无法读取文件)*"
    }

    /// 把 Markdown 中相对路径的图片/资源改写为 local:// 绝对路径
    static func absolutizeResources(in markdown: String, baseDir: URL) -> String {
        func convert(_ rawPath: String) -> String? {
            let p = rawPath.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            let lower = p.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://")
                || lower.hasPrefix("data:") || lower.hasPrefix("local:")
                || lower.hasPrefix("file:") || p.hasPrefix("#") {
                return nil
            }
            let absPath: String
            if p.hasPrefix("/") {
                absPath = URL(fileURLWithPath: p).standardizedFileURL.path
            } else {
                absPath = baseDir.appendingPathComponent(p).standardizedFileURL.path
            }
            guard let enc = absPath.addingPercentEncoding(
                withAllowedCharacters: CharacterSet(charactersIn: "/")
                    .union(.alphanumerics)
                    .union(CharacterSet(charactersIn: "-._~!$&'()*+,;=:@"))) else { return nil }
            return LocalFileSchemeHandler.scheme + "://" + enc
        }

        var result = markdown

        // 通用替换:按匹配逐个回调转换
        func replacing(_ regex: NSRegularExpression, in text: String, _ transform: (NSTextCheckingResult, NSString) -> String) -> String {
            let ns = text as NSString
            var out = ""
            var lastEnd = 0
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.range.location != NSNotFound else { return }
                out += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
                out += transform(m, ns)
                lastEnd = m.range.location + m.range.length
            }
            out += ns.substring(from: lastEnd)
            return out
        }

        // 处理 Markdown 图片语法 ![alt](path "title") 与链接中的 <path> 形式
        if let regex = try? NSRegularExpression(pattern: "(!\\[[^\\]\\n]*\\]\\(\\s*)([^)\\s]+)([^)\\n]*\\))") {
            result = replacing(regex, in: result) { m, ns in
                if let abs = convert(ns.substring(with: m.range(at: 2))) {
                    return ns.substring(with: m.range(at: 1)) + abs + ns.substring(with: m.range(at: 3))
                }
                return ns.substring(with: m.range)
            }
        }
        // 处理内联 HTML <img src="..."> / <video src="...">
        if let regex = try? NSRegularExpression(pattern: "(<(?:img|video|source|audio)\\b[^>]*?\\bsrc\\s*=\\s*[\"'])([^\"']+)([\"'])") {
            result = replacing(regex, in: result) { m, ns in
                if let abs = convert(ns.substring(with: m.range(at: 2))) {
                    return ns.substring(with: m.range(at: 1)) + abs + ns.substring(with: m.range(at: 3))
                }
                return ns.substring(with: m.range)
            }
        }
        return result
    }

    /// 提取文档标题:第一个 `# 一级标题`
    static func extractTitle(from markdown: String) -> String {
        let normalized = normalizeNewlines(markdown)
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") && t.count > 2 {
                return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    static func html(forFile url: URL, dark: Bool = false) -> String {
        let markdown = readFile(url)
        let processed = absolutizeResources(in: markdown, baseDir: url.deletingLastPathComponent())
        let html = buildHTML(markdown: processed, dark: dark)
        // 调试:设置环境变量 MDV_DUMP_HTML 时把生成的 HTML 写到 /tmp 供测试
        if ProcessInfo.processInfo.environment["MDV_DUMP_HTML"] != nil {
            try? html.write(toFile: "/tmp/mdv_dump.html", atomically: true, encoding: .utf8)
        }
        return html
    }

    static func buildHTML(markdown: String, dark: Bool = false) -> String {
        // JSON 编码后嵌入 JS 字符串字面量,转义 </ 防止提前闭合 script
        let rawLiteral: String
        if let data = try? JSONEncoder().encode(markdown),
           let s = String(data: data, encoding: .utf8) {
            rawLiteral = s
        } else {
            rawLiteral = "\"\""
        }
        let mdLiteral = rawLiteral
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")

        let contentCSS = dark ? githubDarkCSS : githubCSS
        let codeCSS = dark ? hljsDarkCSS : hljsCSS
        let bodyBg = dark ? "#0d1117" : "#ffffff"
        let markHit = dark ? "rgba(187, 128, 9, 0.45)" : "#ffe58f"
        let markCur = dark ? "rgba(249, 168, 37, 0.9)" : "#ffab40"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body { margin: 0; padding: 0; background: \(bodyBg); }
        .markdown-body {
          box-sizing: border-box;
          min-width: 200px;
          max-width: 1200px;
          margin: 0 auto;
          padding: 36px 44px;
          font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", sans-serif;
        }
        .markdown-body img {
          background-color: transparent;
          cursor: zoom-in;
          -webkit-user-drag: none;
        }
        .mermaid-chart {
          display: flex;
          justify-content: center;
          margin: 16px 0;
          overflow-x: auto;
        }
        .mermaid-chart svg { max-width: 100%; height: auto; }
        mark.mdv-hit { background: \(markHit); color: inherit; border-radius: 2px; }
        mark.mdv-current { background: \(markCur); color: inherit; border-radius: 2px; }
        \(contentCSS)
        \(codeCSS)
        </style>
        </head>
        <body>
        <div class="markdown-body" id="content"></div>
        <script>\(markedJS)</script>
        <script>\(hljsJS)</script>
        <script>\(mermaidJS)</script>
        <script>
        var MDV_DARK = \(dark);
        try {
          var MD = \(mdLiteral);
          document.getElementById("content").innerHTML = marked.parse(MD, { gfm: true, breaks: false });
          if (window.hljs) {
            hljs.configure({ ignoreUnescapedHTML: true });
            document.querySelectorAll("pre code").forEach(function (el) {
              if (el.className.indexOf("language-mermaid") === -1) {
                try { hljs.highlightElement(el); } catch (e) {}
              }
            });
          }
          // Mermaid 流程图渲染:把 ```mermaid 代码块转换为图表
          if (window.mermaid) {
            mermaid.initialize({
              startOnLoad: false,
              theme: MDV_DARK ? "dark" : "default",
              securityLevel: "loose",
              fontFamily: '-apple-system, "PingFang SC", "Hiragino Sans GB", sans-serif'
            });
            var mmdBlocks = document.querySelectorAll("pre code.language-mermaid");
            (async function () {
              var seq = 0;
              for (var el of mmdBlocks) {
                var pre = el.closest("pre");
                if (!pre) { continue; }
                try {
                  var result = await mermaid.render("mmd-svg-" + Date.now() + "-" + (seq++), el.textContent);
                  var chart = document.createElement("div");
                  chart.className = "mermaid-chart";
                  chart.innerHTML = result.svg;
                  pre.replaceWith(chart);
                } catch (err) {
                  // 渲染失败时保留原始代码块
                  console.warn("mermaid render failed:", err);
                }
              }
            })();
          }
        } catch (e) {
          document.getElementById("content").textContent = "渲染出错: " + e.message;
        }
        // 双击图片 → 通知原生弹窗全屏显示
        document.addEventListener("dblclick", function (e) {
          var t = e.target;
          if (t && t.tagName === "IMG") {
            var src = t.getAttribute("src") || "";
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.imagePopup) {
              window.webkit.messageHandlers.imagePopup.postMessage(src);
            }
          }
        });
        // 文档内查找
        window.MDV = {
          clearHits: function () {
            document.querySelectorAll("mark.mdv-hit").forEach(function (m) {
              var parent = m.parentNode;
              if (!parent) return;
              while (m.firstChild) parent.insertBefore(m.firstChild, m);
              parent.removeChild(m);
              parent.normalize();
            });
          },
          search: function (text) {
            this.clearHits();
            if (!text) return 0;
            var root = document.getElementById("content");
            if (!root) return 0;
            var needle = text.toLowerCase();
            var matches = [];
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
            var node;
            while ((node = walker.nextNode())) {
              var p = node.parentElement;
              if (!p || p.closest("script,style,noscript")) continue;
              var hay = node.nodeValue.toLowerCase();
              if (hay.indexOf(needle) === -1) continue;
              var starts = [];
              var i = hay.indexOf(needle);
              while (i !== -1) { starts.push(i); i = hay.indexOf(needle, i + needle.length); }
              matches.push([node, starts]);
            }
            var total = 0;
            matches.forEach(function (pair) {
              var n = pair[0], starts = pair[1];
              for (var k = starts.length - 1; k >= 0; k--) {
                try {
                  var range = document.createRange();
                  range.setStart(n, starts[k]);
                  range.setEnd(n, starts[k] + needle.length);
                  var mark = document.createElement("mark");
                  mark.className = "mdv-hit";
                  range.surroundContents(mark);
                  total++;
                } catch (e) {}
              }
            });
            return total;
          },
          jumpTo: function (index) {
            var marks = document.querySelectorAll("mark.mdv-hit");
            if (!marks.length) return -1;
            var i = ((index % marks.length) + marks.length) % marks.length;
            marks.forEach(function (m) { m.classList.remove("mdv-current"); });
            var m = marks[i];
            m.classList.add("mdv-current");
            m.scrollIntoView({ behavior: "smooth", block: "center" });
            return i;
          }
        };
        // 阅读进度上报
        window.addEventListener("scroll", (function () {
          var last = 0;
          return function () {
            var now = Date.now();
            if (now - last < 100) return;
            last = now;
            var d = document.documentElement;
            var max = d.scrollHeight - d.clientHeight;
            var p = max > 0 ? d.scrollTop / max : 0;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollProgress) {
              window.webkit.messageHandlers.scrollProgress.postMessage(Math.round(Math.max(0, Math.min(1, p)) * 100));
            }
          };
        })(), true);
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - 大纲(标题层级)

struct Heading: Identifiable, Hashable, Sendable {
    let id: Int      // 文档内序号,与 DOM 中 heading 出现顺序一致
    let level: Int   // 1-6
    let text: String

    /// 解析 Markdown 中的标题(跳过代码块内的 # 行与 YAML front matter)
    static func extract(from markdown: String) -> [Heading] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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

// MARK: - 图片全屏弹窗(双击图片打开;Esc/单击关闭;捏合缩放;拖动平移)

final class PopupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PopupImageContainer: NSView {
    let imageView = NSImageView()
    var onClose: (() -> Void)?
    private var fitSize: NSSize = .zero
    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var gestureStartScale: CGFloat = 1
    private var gestureStartOffset: CGPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(onMagnify(_:)))
        addGestureRecognizer(magnify)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.buttonMask = 1
        addGestureRecognizer(pan)
        let click = NSClickGestureRecognizer(target: self, action: #selector(onClick))
        click.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        scale = 1
        offset = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        relayoutImage()
    }

    private func relayoutImage() {
        guard let img = imageView.image else { return }
        let margin: CGFloat = 56
        let availW = max(bounds.width - margin * 2, 10)
        let availH = max(bounds.height - margin * 2, 10)
        let isz = img.size
        let s = min(availW / max(isz.width, 1), availH / max(isz.height, 1))
        fitSize = NSSize(width: isz.width * s, height: isz.height * s)
        let size = NSSize(width: fitSize.width * scale, height: fitSize.height * scale)
        let origin = NSPoint(x: bounds.midX + offset.x - size.width / 2,
                             y: bounds.midY - offset.y - size.height / 2)
        imageView.frame = NSRect(origin: origin, size: size)
    }

    @objc private func onMagnify(_ g: NSMagnificationGestureRecognizer) {
        switch g.state {
        case .began:
            gestureStartScale = scale
        case .changed:
            scale = min(max(gestureStartScale * (1 + g.magnification), 1), 12)
        default: break
        }
    }

    @objc private func onPan(_ g: NSPanGestureRecognizer) {
        let t = g.translation(in: self)
        switch g.state {
        case .began:
            gestureStartOffset = offset
        case .changed:
            offset = CGPoint(x: gestureStartOffset.x + t.x, y: gestureStartOffset.y - t.y)
        default: break
        }
    }

    @objc private func onClick() {
        onClose?()
    }
}

final class PopupImageWindowController: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "imagePopup"

    private var window: PopupWindow?
    private var keyMonitor: Any?
    private weak var container: PopupImageContainer?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName, let src = message.body as? String else { return }
        present(resourceString: src)
    }

    private func resolvePath(_ src: String) -> String? {
        if src.hasPrefix("local://") || src.hasPrefix("file://") {
            guard let url = URL(string: src) else { return nil }
            return url.path.removingPercentEncoding ?? url.path
        }
        if src.hasPrefix("/") { return src }
        return nil
    }

    private func present(resourceString src: String) {
        close()
        guard let path = resolvePath(src),
              let image = NSImage(contentsOfFile: path),
              let screen = NSScreen.main else { return }

        let win = PopupWindow(contentRect: screen.frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        win.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1.0)
        let container = PopupImageContainer(frame: screen.frame)
        container.setImage(image)
        container.onClose = { [weak self] in self?.close() }
        win.contentView = container
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        window = win
        self.container = container

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 {  // Esc
                DispatchQueue.main.async { self?.close() }
                return nil
            }
            return ev
        }
    }

    @objc func close() {
        container?.onClose = nil
        container = nil
        window?.orderOut(nil)
        window = nil
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}

// MARK: - WebView 桥接(供外部调用 JS / 打印)

final class WebViewBox: ObservableObject {
    weak var webView: WKWebView?
}

final class ScrollProgressHandler: NSObject, WKScriptMessageHandler {
    var onProgress: ((Int) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "scrollProgress", let v = message.body as? Int {
            onProgress?(v)
        }
    }
}

// MARK: - WKWebView 封装

struct MarkdownWebView: NSViewRepresentable {
    let url: URL
    let dark: Bool
    @Binding var zoomLevel: Double
    /// 大纲跳转目标:heading 在文档中的序号,nil 表示不跳转
    @Binding var scrollTarget: Int?
    /// 阅读进度 0-100
    @Binding var progress: Int
    let box: WebViewBox

    final class Coordinator {
        var lastKey: String?
        var lastScrollTarget: Int?
        let popupController = PopupImageWindowController()
        let scrollHandler = ScrollProgressHandler()
        weak var webView: WKWebView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        config.userContentController.add(context.coordinator.popupController,
                                         name: PopupImageWindowController.messageHandlerName)
        config.userContentController.add(context.coordinator.scrollHandler,
                                         name: "scrollProgress")
        context.coordinator.scrollHandler.onProgress = { p in
            DispatchQueue.main.async { progress = p }
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.pageZoom = CGFloat(zoomLevel)
        context.coordinator.webView = webView
        box.webView = webView
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        coordinator.popupController.close()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let path = url.standardizedFileURL.path
        let key = path + (dark ? "|dark" : "|light")
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            context.coordinator.lastScrollTarget = nil
            webView.loadHTMLString(MarkdownRenderer.html(forFile: url, dark: dark), baseURL: nil)
        }
        if webView.pageZoom != CGFloat(zoomLevel) {
            webView.pageZoom = CGFloat(zoomLevel)
        }
        handleScrollTarget(webView, context: context)
    }

    private func handleScrollTarget(_ webView: WKWebView, context: Context) {
        guard let target = scrollTarget,
              context.coordinator.lastScrollTarget != target else { return }
        context.coordinator.lastScrollTarget = target
        let js = """
        (function () {
          var hs = document.querySelectorAll('.markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6');
          if (hs.length > \(target)) {
            hs[\(target)].scrollIntoView({ behavior: 'smooth', block: 'start' });
          }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
        DispatchQueue.main.async { scrollTarget = nil }
    }
}

// MARK: - 数据仓库

@MainActor
final class FolderStore: ObservableObject {

    static let folderKey = "MarkdownViewer.lastFolderPath"

    @Published var folderURL: URL? {
        didSet { UserDefaults.standard.set(folderURL?.path, forKey: Self.folderKey); rescan() }
    }
    @Published var items: [DocItem] = []
    @Published var selectedPath: String?
    @Published var query: String = ""

    var filteredItems: [DocItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.primaryText.localizedCaseInsensitiveContains(query)
                || $0.secondaryText.localizedCaseInsensitiveContains(query)
        }
    }

    init() {
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

// MARK: - 侧栏行(自定义柔和选中样式)

struct SidebarRowView: View {
    let item: DocItem
    let selected: Bool
    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var background: Color {
        if selected {
            // 浅色模式用柔和浅蓝灰,深色模式用系统非强调选中色
            return colorScheme == .dark
                ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                : Color(red: 0.88, green: 0.91, blue: 0.95)
        }
        if hovered {
            return Color.primary.opacity(0.05)           // 很淡的悬停
        }
        return Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.primaryText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .help(item.primaryText)
            Text(item.secondaryText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help(item.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(background)
        .cornerRadius(6)
        .padding(.horizontal, 6)
        .onHover { hovered = $0 }
    }
}

// MARK: - 侧栏视图

struct SidebarView: View {
    @ObservedObject var store: FolderStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索文档", text: $store.query)
                    .textFieldStyle(.plain)
                if !store.query.isEmpty {
                    Button(action: { store.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .quaternarySystemFill))
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            List {
                ForEach(store.filteredItems) { item in
                    SidebarRowView(item: item, selected: item.id == store.selectedPath)
                        .onTapGesture { store.selectedPath = item.id }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)

            Divider()
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(store.folderURL?.lastPathComponent ?? "未选择文件夹")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button(action: { store.chooseFolder() }) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("选择文件夹")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 180, idealWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 大纲面板

struct OutlineView: View {
    let headings: [Heading]
    @Binding var scrollTarget: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("大纲")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if headings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .font(.title3)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Text("本文档没有标题")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(headings) { heading in
                        Text(heading.text)
                            .font(.system(size: heading.level <= 2 ? 12 : 11,
                                          weight: heading.level <= 2 ? .medium : .regular))
                            .lineLimit(1)
                            .help(heading.text)
                            .padding(.leading, CGFloat(heading.level - 1) * 12)
                            .contentShape(Rectangle())
                            .id(heading.id)
                            .onTapGesture { scrollTarget = heading.id }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .frame(minWidth: 150, idealWidth: 200)
    }
}

// MARK: - 详情视图(正文 + 查找栏 + 状态栏)

struct DetailView: View {
    @Binding var selectedPath: String?
    @Binding var scrollTarget: Int?
    @Binding var zoomLevel: Double
    let darkMode: Bool
    let wordCount: Int
    let box: WebViewBox

    @State private var findVisible = false
    @FocusState private var findFocused: Bool
    @State private var findText = ""
    @State private var totalHits = 0
    @State private var currentHit = 0
    @State private var readProgress = 0
    @State private var findTask: Task<Void, Never>?

    var body: some View {
        if let path = selectedPath,
           let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "file://" + encoded) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(url.lastPathComponent)
                    Spacer()
                    if findVisible {
                        findBar
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                Divider()
                MarkdownWebView(url: url, dark: darkMode, zoomLevel: $zoomLevel,
                                scrollTarget: $scrollTarget, progress: $readProgress, box: box)
                Divider()
                statusBar
            }
            .frame(minWidth: 480)
            .onExitCommand {
                if findVisible { closeFind() }
            }
            .onChange(of: selectedPath) { _ in
                findText = ""
                totalHits = 0
                currentHit = 0
                readProgress = 0
            }
            .background {
                // ⌘F 唤起查找
                Button("") { findVisible = true; findFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                // ⌘+ / ⌘- / ⌘0 缩放
                Button("") { zoomLevel = min(2.0, zoomLevel + 0.1) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("") { zoomLevel = max(0.5, zoomLevel - 0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { zoomLevel = 1.0 }
                    .keyboardShortcut("0", modifiers: .command)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 48))
                    .foregroundColor(Color(nsColor: .quaternaryLabelColor))
                Text("选择左侧文档开始阅读")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 查找栏

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("在文档中查找", text: $findText)
                .textFieldStyle(.roundedBorder)
                .focused($findFocused)
                .frame(width: 200)
                .onSubmit { jumpNext() }
            Text(totalHits > 0 ? "\(currentHit)/\(totalHits)" : (findText.isEmpty ? "" : "无匹配"))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(minWidth: 52, alignment: .leading)
            Button { jumpPrev() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .help("上一个 (⏎)")
            Button { jumpNext() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .help("下一个 (⏎)")
            Divider().frame(height: 14)
            Button { closeFind() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("关闭 (Esc)")
        }
        .onChange(of: findText) { q in
            findTask?.cancel()
            findTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                runSearch(q)
            }
        }
    }

    // MARK: 状态栏

    private var statusBar: some View {
        HStack(spacing: 12) {
            if wordCount > 0 {
                Text("字数 \(wordCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("正文总字数(不含空白字符)")
            }
            Spacer()
            if readProgress > 0 {
                Text("已读 \(readProgress)%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Divider().frame(height: 12)
            Button { zoomLevel = max(0.5, zoomLevel - 0.1) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.borderless)
            .help("缩小 (⌘-)")
            Text("\(Int((zoomLevel * 100).rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
            Button { zoomLevel = min(2.0, zoomLevel + 0.1) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.borderless)
            .help("放大 (⌘+)")
            Button { zoomLevel = 1.0 } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("重置缩放 (⌘0)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: 查找逻辑

    private func runSearch(_ q: String) {
        guard let webView = box.webView else { return }
        guard let data = try? JSONEncoder().encode(q),
              let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.MDV ? MDV.search(\(literal)) : 0") { result, _ in
            let total = result as? Int ?? 0
            totalHits = total
            if total > 0 {
                jump(to: 0)
            } else {
                currentHit = 0
            }
        }
    }

    private func jump(to index: Int) {
        guard let webView = box.webView, totalHits > 0 else { return }
        webView.evaluateJavaScript("window.MDV ? MDV.jumpTo(\(index)) : -1") { result, _ in
            if let i = result as? Int, i >= 0 {
                currentHit = i + 1
            }
        }
    }

    private func jumpNext() { jump(to: currentHit) }        // currentHit 为 1-based,传下去正好是下一个的 0-based
    private func jumpPrev() { jump(to: currentHit - 2) }

    private func closeFind() {
        findVisible = false
        findText = ""
        totalHits = 0
        currentHit = 0
        box.webView?.evaluateJavaScript("window.MDV && MDV.clearHits()", completionHandler: nil)
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var store = FolderStore()
    @StateObject private var box = WebViewBox()
    @State private var headings: [Heading] = []
    @State private var scrollTarget: Int?
    @State private var wordCount = 0
    @AppStorage("MarkdownViewer.showSidebar") private var showSidebar = true
    @AppStorage("MarkdownViewer.showOutline") private var showOutline = true
    @AppStorage("MarkdownViewer.darkMode") private var darkMode = false
    @AppStorage("MarkdownViewer.zoom") private var zoomLevel: Double = 1.0

    var body: some View {
        HSplitView {
            if showSidebar {
                SidebarView(store: store)
            }
            if showOutline {
                OutlineView(headings: headings, scrollTarget: $scrollTarget)
            }
            DetailView(selectedPath: $store.selectedPath,
                       scrollTarget: $scrollTarget,
                       zoomLevel: $zoomLevel,
                       darkMode: darkMode,
                       wordCount: wordCount,
                       box: box)
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSidebar.toggle()
                } label: {
                    Label("文档列表", systemImage: "sidebar.leading")
                }
                .help("显示/隐藏文档列表")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    darkMode.toggle()
                } label: {
                    Label(darkMode ? "浅色模式" : "深色模式",
                          systemImage: darkMode ? "sun.max" : "moon")
                }
                .help("切换深色/浅色模式")
                Button {
                    showOutline.toggle()
                } label: {
                    Label("大纲", systemImage: "list.bullet.indent")
                }
                .help("显示/隐藏大纲")
                Button {
                    store.chooseFolder()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
                .help("打开文件夹")
                Button {
                    store.rescan()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新文档列表")
                Button {
                    printCurrentDocument()
                } label: {
                    Label("打印/导出 PDF", systemImage: "printer")
                }
                .keyboardShortcut("p", modifiers: .command)
                .help("打印或导出为 PDF (⌘P)")
            }
        }
        // 选中文件变化时重新解析大纲与字数(后台线程,不阻塞界面)
        .task(id: store.selectedPath) {
            let path = store.selectedPath
            scrollTarget = nil
            guard let path else {
                headings = []
                wordCount = 0
                return
            }
            let parsed = await Task.detached(priority: .userInitiated) { () -> ([Heading], Int) in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return ([], 0) }
                let text = String(decoding: data, as: UTF8.self)
                return (Heading.extract(from: text), text.filter { !$0.isWhitespace }.count)
            }.value
            if !Task.isCancelled, store.selectedPath == path {
                headings = parsed.0
                wordCount = parsed.1
            }
        }
        .onAppear {
            if store.folderURL == nil {
                store.chooseFolder()
            }
        }
    }

    /// ⌘P:调起系统打印面板(可另存为 PDF)
    private func printCurrentDocument() {
        guard let webView = box.webView else { return }
        let printInfo = NSPrintInfo.shared
        let op = webView.printOperation(with: printInfo)
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }
}

// MARK: - App 委托(确保任何情况下都有窗口)

final class AppDelegate: NSObject, NSApplicationDelegate {

    private func hasMainWindow() -> Bool {
        NSApp.windows.contains { w in
            w.isVisible && w.level == .normal && !(w is PopupWindow) && w.frame.height > 100
        }
    }

    private func createNewWindow() {
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 窗口状态恢复为空(如上次被强制结束)时,自动新建窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self, !self.hasMainWindow() {
                self.createNewWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标时若无窗口,新建一个
        if !flag {
            createNewWindow()
        }
        return true
    }
}

// MARK: - App 入口

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Markdown 阅读器") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
