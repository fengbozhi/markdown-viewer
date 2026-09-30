import SwiftUI
import WebKit

// MARK: - 详情视图(预览 / 分屏 / 编辑 + 查找栏 + 状态栏)

struct DetailView: View {
    @Binding var selectedPath: String?
    @Binding var scrollTarget: Int?
    @Binding var zoomLevel: Double
    @Binding var activeHeading: Int
    let mode: ViewMode
    let darkMode: Bool
    let wordCount: Int
    /// 预计阅读时长(分钟,0 表示未知)
    let readingMinutes: Int
    /// 外部文件变更令牌(自动重载)
    let reloadToken: Int
    let box: WebViewBox
    @ObservedObject var editorDoc: EditorDocument
    let editorBox: EditorBox

    @State private var findVisible = false
    @FocusState private var findFocused: Bool
    @State private var findText = ""
    @State private var totalHits = 0
    @State private var currentHit = 0
    @State private var readProgress = 0
    @State private var findTask: Task<Void, Never>?
    /// 编辑实时预览文本(防抖后)
    @State private var previewSource: String = ""
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        if let path = selectedPath,
           let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "file://" + encoded) {
            VStack(spacing: 0) {
                headerBar(url: url)
                Divider()
                contentArea(url: url)
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
                previewSource = editorDoc.text
            }
            .onAppear { previewSource = editorDoc.text }
            .background {
                if mode != .edit {
                    // ⌘F 唤起渲染区查找
                    Button("") { findVisible = true; findFocused = true }
                        .keyboardShortcut("f", modifiers: .command)
                }
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

    // MARK: 顶栏

    private func headerBar(url: URL) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
                .font(.caption)
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help(url.path)
            if editorDoc.isDirty {
                Text("未保存")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
            }
            Spacer()
            if findVisible, mode != .edit {
                findBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: 内容区(三模式)

    @ViewBuilder
    private func contentArea(url: URL) -> some View {
        switch mode {
        case .preview:
            webArea(url: url, source: nil)
        case .edit:
            editorArea
        case .split:
            HSplitView {
                editorArea.frame(minWidth: 280)
                webArea(url: url, source: previewSource).frame(minWidth: 280)
            }
        }
    }

    private func webArea(url: URL, source: String?) -> some View {
        MarkdownWebView(url: url, dark: darkMode, reloadToken: reloadToken,
                        sourceMarkdown: source,
                        zoomLevel: $zoomLevel, scrollTarget: $scrollTarget,
                        progress: $readProgress, activeHeading: $activeHeading, box: box)
    }

    // MARK: 编辑区(格式化工具栏 + 编辑器)

    private var editorArea: some View {
        VStack(spacing: 0) {
            formatBar
            Divider()
            MarkdownEditorView(text: $editorDoc.text, box: editorBox)
                .onChange(of: editorDoc.text) { newText in
                    // 实时预览防抖 0.35s
                    previewTask?.cancel()
                    previewTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        previewSource = newText
                    }
                }
        }
        .background {
            // 编辑快捷键
            Button("") { editorBox.apply(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("") { editorBox.apply(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("") { editorBox.apply(.link) }
                .keyboardShortcut("k", modifiers: .command)
            Button("") { editorBox.apply(.strikethrough) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
        }
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            formatButton("bold", "加粗 (⌘B)") { editorBox.apply(.bold) }
            formatButton("italic", "斜体 (⌘I)") { editorBox.apply(.italic) }
            formatButton("strikethrough", "删除线 (⇧⌘X)") { editorBox.apply(.strikethrough) }
            formatButton("chevron.left.forwardslash.chevron.right", "行内代码/代码块") { editorBox.apply(.inlineCode) }
            formatButton("link", "链接 (⌘K)") { editorBox.apply(.link) }
            Divider().frame(height: 14).padding(.horizontal, 4)
            formatTextButton("H1", "一级标题") { editorBox.apply(.heading(1)) }
            formatTextButton("H2", "二级标题") { editorBox.apply(.heading(2)) }
            formatTextButton("H3", "三级标题") { editorBox.apply(.heading(3)) }
            Divider().frame(height: 14).padding(.horizontal, 4)
            formatButton("text.quote", "引用") { editorBox.apply(.quote) }
            formatButton("list.bullet", "无序列表") { editorBox.apply(.bulletList) }
            formatButton("list.number", "有序列表") { editorBox.apply(.orderedList) }
            formatButton("checklist", "任务列表") { editorBox.apply(.taskList) }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func formatButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func formatTextButton(_ title: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
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
            if readingMinutes > 0 {
                Text(readingMinutes < 1 ? "1 分钟内读完" : "约 \(readingMinutes) 分钟读完")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("按中文约 400 字/分钟估算")
            }
            Spacer()
            if readProgress > 0, mode != .edit {
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
