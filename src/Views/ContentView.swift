import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - 窗口关闭拦截(未保存时确认)

struct WindowCloseGuard: NSViewRepresentable {
    let confirmClose: () -> Bool

    final class Coordinator: NSObject, NSWindowDelegate {
        var confirmClose: (() -> Bool)?
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            confirmClose?() ?? true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.confirmClose = confirmClose
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.confirmClose = confirmClose
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var store = FolderStore()
    @StateObject private var box = WebViewBox()
    @StateObject private var editorDoc = EditorDocument()
    @StateObject private var editorBox = EditorBox()
    @State private var headings: [Heading] = []
    @State private var scrollTarget: Int?
    @State private var activeHeading = -1
    @State private var fileStats = DocStats()
    /// 外部文件变更令牌:+1 触发 WebView 自动重载(Typora 式实时刷新)
    @State private var reloadToken = 0
    @State private var fileWatcher = FileWatcher()
    // 未保存修改的文档切换防护
    @State private var confirmedPath: String?
    @State private var pendingPath: String?
    @State private var isRevertingSelection = false
    @State private var bypassGuardOnce = false
    @State private var showUnsavedAlert = false
    @State private var showConflictAlert = false
    // 快速打开(⌘P)
    @State private var quickOpenVisible = false
    @State private var quickOpenQuery = ""
    @State private var quickOpenSelection = 0
    @AppStorage("MarkdownViewer.showSidebar") private var showSidebar = true
    @AppStorage("MarkdownViewer.showOutline") private var showOutline = true
    @AppStorage("MarkdownViewer.darkMode") private var darkMode = false
    @AppStorage("MarkdownViewer.zoom") private var zoomLevel: Double = 1.0
    @AppStorage("MarkdownViewer.viewMode") private var viewMode: ViewMode = .preview
    @AppStorage("MarkdownViewer.typewriter") private var typewriterMode = false
    @AppStorage("MarkdownViewer.currentLine") private var highlightCurrentLine = true

    /// 当前文档统计(编辑/分屏模式取编辑器实时文本,预览模式取文件解析结果)
    private var liveStats: DocStats {
        if viewMode == .preview { return fileStats }
        return DocStats(text: editorDoc.text)
    }

    /// 预计阅读时长(分钟):中文按约 400 字/分钟估算
    private var readingMinutes: Int {
        guard liveStats.words > 0 else { return 0 }
        return max(1, Int((Double(liveStats.words) / 400.0).rounded()))
    }

    private var currentFileName: String {
        guard let path = store.selectedPath else { return "Markdown 阅读器" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        ZStack {
            HSplitView {
                if showSidebar {
                    SidebarView(store: store)
                }
                if showOutline {
                    OutlineView(headings: headings,
                                scrollTarget: $scrollTarget,
                                activeHeading: $activeHeading)
                }
                DetailView(selectedPath: $store.selectedPath,
                           scrollTarget: $scrollTarget,
                           zoomLevel: $zoomLevel,
                           activeHeading: $activeHeading,
                           mode: viewMode,
                           darkMode: darkMode,
                           stats: liveStats,
                           readingMinutes: readingMinutes,
                           reloadToken: reloadToken,
                           box: box,
                           editorDoc: editorDoc,
                           editorBox: editorBox,
                           typewriterMode: typewriterMode,
                           highlightCurrentLine: highlightCurrentLine)
            }
            // 快速打开浮层(⌘P,Obsidian Quick Switcher 风格)
            if quickOpenVisible {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { quickOpenVisible = false }
                VStack {
                    QuickOpenView(items: store.items,
                                  query: $quickOpenQuery,
                                  selection: $quickOpenSelection,
                                  onSubmit: { item in
                                      quickOpenVisible = false
                                      store.selectedPath = item.id
                                  },
                                  onClose: { quickOpenVisible = false })
                        .padding(.top, 90)
                    Spacer()
                }
            }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .navigationTitle((editorDoc.isDirty ? "● " : "") + currentFileName)
        .background(WindowCloseGuard(confirmClose: confirmWindowClose))
        .background {
            // ⌘1/⌘2/⌘3 切换视图模式
            Button("") { viewMode = .preview }.keyboardShortcut("1", modifiers: .command)
            Button("") { viewMode = .split }.keyboardShortcut("2", modifiers: .command)
            Button("") { viewMode = .edit }.keyboardShortcut("3", modifiers: .command)
            // ⌘P 快速打开
            Button("") {
                quickOpenQuery = ""
                quickOpenSelection = 0
                quickOpenVisible = true
            }
            .keyboardShortcut("p", modifiers: .command)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSidebar.toggle()
                } label: {
                    Label("文档列表", systemImage: "sidebar.leading")
                }
                .help("显示/隐藏文档列表")
            }
            ToolbarItem(placement: .principal) {
                Picker("视图模式", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .help("预览 (⌘1) / 分屏 (⌘2) / 编辑 (⌘3)")
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
                    quickOpenQuery = ""
                    quickOpenSelection = 0
                    quickOpenVisible = true
                } label: {
                    Label("快速打开", systemImage: "magnifyingglass")
                }
                .help("快速打开文档 (⌘P)")
                Menu {
                    Button {
                        saveDocument()
                    } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!editorDoc.isDirty)
                    Divider()
                    Button {
                        exportHTML()
                    } label: {
                        Label("导出 HTML", systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.selectedPath == nil)
                    Button {
                        exportPDF()
                    } label: {
                        Label("导出 PDF", systemImage: "doc.richtext")
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(store.selectedPath == nil)
                    Divider()
                    Button {
                        typewriterMode.toggle()
                    } label: {
                        Label("打字机模式",
                              systemImage: typewriterMode ? "checkmark.circle.fill" : "circle")
                    }
                    .help("编辑时光标行始终垂直居中(iA Writer 风格)")
                    Button {
                        highlightCurrentLine.toggle()
                    } label: {
                        Label("当前行高亮",
                              systemImage: highlightCurrentLine ? "checkmark.circle.fill" : "circle")
                    }
                    .help("编辑器中高亮光标所在行(VS Code 风格)")
                    Divider()
                    Button {
                        revealInFinder()
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder.badge.magnifyingglass")
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.selectedPath == nil)
                    Button {
                        openWithDefaultApp()
                    } label: {
                        Label("用默认编辑器打开", systemImage: "pencil.circle")
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(store.selectedPath == nil)
                    Divider()
                    Button {
                        printCurrentDocument()
                    } label: {
                        Label("打印", systemImage: "printer")
                    }
                    .disabled(store.selectedPath == nil)
                } label: {
                    Label("更多操作", systemImage: "ellipsis.circle")
                }
                .help("保存 / 导出 / 编辑偏好 / 定位 / 打印")
            }
        }
        // 文档切换防护:有未保存修改时拦截并询问
        .onChange(of: store.selectedPath) { newPath in
            handleSelectionChange(newPath)
        }
        .alert("有未保存的修改", isPresented: $showUnsavedAlert) {
            Button("保存并切换") {
                saveDocument()
                switchToPending()
            }
            Button("放弃修改并切换", role: .destructive) {
                switchToPending()
            }
            Button("取消", role: .cancel) {
                pendingPath = nil
            }
        } message: {
            Text("当前文档有未保存的修改,切换文档前要保存吗?")
        }
        .alert("文件已被外部修改", isPresented: $showConflictAlert) {
            Button("重新加载(丢弃我的修改)", role: .destructive) {
                if let path = store.selectedPath {
                    editorDoc.load(path: path)
                    reloadToken += 1
                }
            }
            Button("保留我的版本", role: .cancel) {}
        } message: {
            Text("当前文档在磁盘上被其他程序修改,且你有未保存的编辑。重新加载将丢弃你的修改。")
        }
        // 菜单栏 ⌘S(App 层转发)
        .onReceive(NotificationCenter.default.publisher(for: .mdvSaveRequest)) { _ in
            saveDocument()
        }
        // 解析大纲与统计(后台线程,不阻塞界面);外部变更时随 reloadToken 重新解析
        .task(id: "\(store.selectedPath ?? "")|\(reloadToken)") {
            let path = store.selectedPath
            scrollTarget = nil
            activeHeading = -1
            guard let path else {
                headings = []
                fileStats = DocStats()
                return
            }
            let parsed = await Task.detached(priority: .userInitiated) { () -> ([Heading], DocStats) in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return ([], DocStats()) }
                let text = TextNormalizer.normalizeNewlines(String(decoding: data, as: UTF8.self))
                return (Heading.extract(from: text), DocStats(text: text))
            }.value
            if !Task.isCancelled, store.selectedPath == path {
                headings = parsed.0
                fileStats = parsed.1
            }
        }
        .onAppear {
            fileWatcher.onEvent = {
                Task { @MainActor in handleExternalChange() }
            }
            box.onTaskToggle = { index in
                Task { @MainActor in handleTaskToggle(index) }
            }
            // 恢复会话后的初始加载
            if editorDoc.filePath == nil, let path = store.selectedPath {
                confirmedPath = path
                editorDoc.load(path: path)
            }
            if store.folderURL == nil {
                store.chooseFolder()
            }
        }
    }

    // MARK: 文档切换防护

    private func handleSelectionChange(_ newPath: String?) {
        // 切回原文档的这次变化:忽略,不重新加载(避免覆盖未保存编辑)
        if isRevertingSelection {
            isRevertingSelection = false
            return
        }
        // 用户确认后的强制切换
        if bypassGuardOnce {
            bypassGuardOnce = false
            confirmedPath = newPath
            if let newPath { editorDoc.load(path: newPath) }
            return
        }
        if editorDoc.isDirty, newPath != confirmedPath {
            // 有未保存修改:先切回原文档,再弹窗询问
            pendingPath = newPath
            isRevertingSelection = true
            store.selectedPath = confirmedPath
            showUnsavedAlert = true
            return
        }
        confirmedPath = newPath
        // 同一文档重复点击不重新加载(保护未保存编辑)
        if let newPath, newPath != editorDoc.filePath {
            editorDoc.load(path: newPath)
        }
    }

    private func switchToPending() {
        guard let pending = pendingPath else { return }
        pendingPath = nil
        bypassGuardOnce = true
        store.selectedPath = pending
    }

    // MARK: 保存

    private func saveDocument() {
        guard editorDoc.isDirty else { return }
        do {
            try editorDoc.save()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: 任务复选框回写(渲染区点击 → 修改源文件)

    private func handleTaskToggle(_ index: Int) {
        guard let path = store.selectedPath, editorDoc.filePath == path else { return }
        let wasDirty = editorDoc.isDirty
        guard let newText = TaskToggle.flip(in: editorDoc.text, index: index) else { return }
        editorDoc.text = newText
        // 干净文档上的显式点击:直接落盘(Typora 行为);有未保存编辑时只改缓冲区
        if !wasDirty {
            try? editorDoc.save()
        }
    }

    // MARK: 外部文件变更

    private func handleExternalChange() {
        // 自己刚保存引发的变更事件,忽略
        if Date().timeIntervalSince(editorDoc.lastInternalSave) < 1.5 { return }
        if editorDoc.isDirty {
            // 与未保存编辑冲突:绝不静默覆盖,交给用户决定
            showConflictAlert = true
        } else {
            if let path = store.selectedPath {
                editorDoc.load(path: path)
            }
            reloadToken += 1
        }
    }

    // MARK: 窗口关闭防护

    private func confirmWindowClose() -> Bool {
        guard editorDoc.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "有未保存的修改"
        alert.informativeText = "关闭窗口前是否保存对「\(currentFileName)」的修改?"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: 文件操作

    /// ⌘⇧E:导出独立 HTML(图片与字体内嵌 base64,可脱离 App 分发)
    private func exportHTML() {
        guard let path = store.selectedPath else { return }
        let url = URL(fileURLWithPath: path)
        // 有未保存修改时导出编辑器中的最新内容
        let html: String
        if editorDoc.isDirty, editorDoc.filePath == path {
            let processed = MarkdownRenderer.absolutizeResources(in: editorDoc.text, baseDir: url.deletingLastPathComponent())
            html = MarkdownRenderer.embedLocalResources(in: MarkdownRenderer.buildHTML(markdown: processed, dark: darkMode))
        } else {
            html = MarkdownRenderer.standaloneHTML(forFile: url, dark: darkMode)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".html"
        panel.message = "导出为独立 HTML(图片与字体已内嵌)"
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try html.write(to: dest, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// ⌘⇧P:导出 PDF(把当前渲染结果整页捕获为 PDF)
    private func exportPDF() {
        guard let path = store.selectedPath else { return }
        guard let webView = box.webView else {
            let alert = NSAlert()
            alert.messageText = "请先切换到预览或分屏模式"
            alert.informativeText = "PDF 基于渲染结果生成,纯编辑模式下没有渲染视图。"
            alert.runModal()
            return
        }
        let url = URL(fileURLWithPath: path)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".pdf"
        panel.message = "导出为 PDF(包含全部排版样式)"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let config = WKPDFConfiguration()
        config.rect = .null   // 捕获完整页面而非可视区域
        webView.createPDF(configuration: config) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: dest)
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    } catch {
                        NSAlert(error: error).runModal()
                    }
                case .failure(let error):
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    /// ⌘⇧R:在 Finder 中显示当前文件
    private func revealInFinder() {
        guard let path = store.selectedPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// ⌘⇧O:用系统默认编辑器打开当前文件
    private func openWithDefaultApp() {
        guard let path = store.selectedPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// 调起系统打印面板(快捷键已让位给「快速打开 ⌘P」与「导出 PDF ⌘⇧P」)
    private func printCurrentDocument() {
        guard let webView = box.webView else { return }
        let printInfo = NSPrintInfo.shared
        let op = webView.printOperation(with: printInfo)
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }
}
