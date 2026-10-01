import SwiftUI
import WebKit

// MARK: - WebView 桥接(供外部调用 JS / 打印)

final class WebViewBox: ObservableObject {
    weak var webView: WKWebView?
    /// 任务复选框点击回调(参数为复选框在文档中的序号)
    var onTaskToggle: ((Int) -> Void)?
}

/// 任务列表复选框点击上报(渲染区点击 → 回写源文件)
final class TaskToggleHandler: NSObject, WKScriptMessageHandler {
    var onToggle: ((Int) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "taskToggle",
              let body = message.body as? [String: Any],
              let index = body["index"] as? Int else { return }
        onToggle?(index)
    }
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

/// 当前章节上报(滚动同步大纲高亮)
final class ActiveHeadingHandler: NSObject, WKScriptMessageHandler {
    var onActiveHeading: ((Int) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "activeHeading", let v = message.body as? Int {
            onActiveHeading?(v)
        }
    }
}

// MARK: - WKWebView 封装

struct MarkdownWebView: NSViewRepresentable {
    let url: URL
    let dark: Bool
    /// 变更令牌:外部文件被修改时 +1,强制重新加载
    let reloadToken: Int
    /// 非空时直接渲染该 Markdown 文本(编辑模式实时预览),nil 时从 url 读文件渲染
    let sourceMarkdown: String?
    @Binding var zoomLevel: Double
    /// 大纲跳转目标:heading 在文档中的序号,nil 表示不跳转
    @Binding var scrollTarget: Int?
    /// 阅读进度 0-100
    @Binding var progress: Int
    /// 当前可视章节序号(滚动同步大纲高亮),-1 表示文首
    @Binding var activeHeading: Int
    let box: WebViewBox

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastKey: String?
        /// 编辑实时预览:上次渲染的源文本(相等则不重载)
        var lastSource: String?
        var lastDark: Bool = false
        var lastScrollTarget: Int?
        let popupController = PopupImageWindowController()
        let scrollHandler = ScrollProgressHandler()
        let headingHandler = ActiveHeadingHandler()
        let taskHandler = TaskToggleHandler()
        weak var webView: WKWebView?
        /// 自动重载前记录阅读进度,加载完成后恢复滚动位置
        var pendingRestoreProgress: Int?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let p = pendingRestoreProgress, p > 0 else { return }
            pendingRestoreProgress = nil
            // 恢复滚动必须瞬间完成:临时关闭 CSS scroll-behavior: smooth,否则会看到滚动动画
            let js = """
            (function () {
              var d = document.documentElement;
              var prev = d.style.scrollBehavior;
              d.style.scrollBehavior = "auto";
              var max = d.scrollHeight - d.clientHeight;
              if (max > 0) window.scrollTo(0, max * \(p) / 100);
              d.style.scrollBehavior = prev;
            })();
            """
            // 等渲染管线(marked/mermaid 异步)完成后再恢复
            webView.evaluateJavaScript(js, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        config.userContentController.add(context.coordinator.popupController,
                                         name: PopupImageWindowController.messageHandlerName)
        config.userContentController.add(context.coordinator.scrollHandler,
                                         name: "scrollProgress")
        config.userContentController.add(context.coordinator.headingHandler,
                                         name: "activeHeading")
        config.userContentController.add(context.coordinator.taskHandler,
                                         name: "taskToggle")
        context.coordinator.scrollHandler.onProgress = { p in
            DispatchQueue.main.async { progress = p }
        }
        context.coordinator.headingHandler.onActiveHeading = { idx in
            DispatchQueue.main.async { activeHeading = idx }
        }
        context.coordinator.taskHandler.onToggle = { idx in
            DispatchQueue.main.async { box.onTaskToggle?(idx) }
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.pageZoom = CGFloat(zoomLevel)
        // 加载完成前的底色与正文一致,避免深色模式下白闪
        webView.underPageBackgroundColor = Self.pageBackgroundColor(dark: dark)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        box.webView = webView
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        coordinator.popupController.close()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let source = sourceMarkdown {
            // 编辑实时预览:文本或主题变化才重载,并保持滚动位置
            if context.coordinator.lastSource != source || context.coordinator.lastDark != dark {
                context.coordinator.lastSource = source
                context.coordinator.lastDark = dark
                context.coordinator.lastScrollTarget = nil
                context.coordinator.pendingRestoreProgress = progress
                let processed = MarkdownRenderer.absolutizeResources(in: source, baseDir: url.deletingLastPathComponent())
                webView.loadHTMLString(MarkdownRenderer.buildHTML(markdown: processed, dark: dark), baseURL: nil)
            }
        } else {
            // 文件模式:切换文档/主题/外部变更才重载
            context.coordinator.lastSource = nil
            let path = url.standardizedFileURL.path
            let key = path + (dark ? "|dark" : "|light") + "|r\(reloadToken)"
            if context.coordinator.lastKey != key {
                let isSameFileReload = context.coordinator.lastKey?.hasPrefix(path) == true
                context.coordinator.lastKey = key
                context.coordinator.lastScrollTarget = nil
                // 同一文件自动重载时,记录进度以便恢复滚动位置
                context.coordinator.pendingRestoreProgress = isSameFileReload ? progress : nil
                webView.loadHTMLString(MarkdownRenderer.html(forFile: url, dark: dark), baseURL: nil)
            }
        }
        if webView.pageZoom != CGFloat(zoomLevel) {
            webView.pageZoom = CGFloat(zoomLevel)
        }
        let bg = Self.pageBackgroundColor(dark: dark)
        if webView.underPageBackgroundColor != bg {
            webView.underPageBackgroundColor = bg
        }
        handleScrollTarget(webView, context: context)
    }

    /// 与渲染 HTML 的 body 背景一致的底色
    private static func pageBackgroundColor(dark: Bool) -> NSColor {
        dark ? NSColor(red: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1) : .white
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
