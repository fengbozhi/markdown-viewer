import SwiftUI
import AppKit

// MARK: - 编辑器桥接(供工具栏按钮调用格式化命令)

final class EditorBox: ObservableObject {
    weak var textView: NSTextView?

    func apply(_ command: EditorCommand) {
        guard let tv = textView else { return }
        let result = EditorCommands.apply(command, to: tv.string, selection: tv.selectedRange())
        tv.insertText(result.replacement, replacementRange: result.range)
        tv.setSelectedRange(result.selection)
        tv.scrollRangeToVisible(result.selection)
        tv.window?.makeFirstResponder(tv)
    }
}

// MARK: - 自定义文本视图(拦截粘贴:图片自动存 assets/ 并插入链接)

final class MDVTextView: NSTextView {
    /// 文档所在目录(粘贴图片时计算 assets/ 路径)
    var imageDirectory: URL?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let dir = imageDirectory {
            // 1) 剪贴板中的位图数据(截图/复制的图像)
            let pngData = pb.data(forType: .png)
                ?? pb.data(forType: .tiff).flatMap {
                    NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
                }
            if let data = pngData,
               let md = ImagePasteService.saveImage(data: data, ext: "png", docDir: dir) {
                insertText(md, replacementRange: selectedRange())
                return
            }
            // 2) 剪贴板中的图片文件(Finder 复制的图片)
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
                let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "heic"]
                let images = urls.filter { imageExts.contains($0.pathExtension.lowercased()) }
                if !images.isEmpty {
                    let links = images.compactMap { ImagePasteService.link(for: $0, docDir: dir) }
                    if !links.isEmpty {
                        insertText(links.joined(separator: "\n"), replacementRange: selectedRange())
                        return
                    }
                }
            }
        }
        super.paste(sender)
    }
}

// MARK: - Markdown 编辑器(NSTextView 封装:高亮 / 自动配对 / 列表续行 / 打字机模式)

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    let box: EditorBox
    /// 打字机模式(iA Writer):光标行始终垂直居中
    var typewriterMode: Bool = false
    /// 当前行高亮(VS Code 风格)
    var highlightCurrentLine: Bool = true
    /// 字号缩放(跟随全局 ⌘+/⌘- 缩放,1.0 为基准 14pt)
    var fontScale: Double = 1.0
    /// 文档所在目录(图片粘贴保存位置)
    var imageDirectory: URL?
    /// 文本变化回调(用于脏标记/实时预览防抖等)
    var onTextChange: (() -> Void)?

    /// 语法高亮全量处理的字符数上限;超过则只高亮可视区域(性能保护)
    private static let fullHighlightLimit = 300_000

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: NSTextView?
        var highlightWork: DispatchWorkItem?
        /// 程序化编辑标记:防止 insertText 再次进入拦截逻辑造成递归
        var isProgrammaticEdit = false

        init(_ parent: MarkdownEditorView) { self.parent = parent }

        // MARK: 文本变化 → 同步绑定 + 防抖高亮

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string {
                parent.text = tv.string
            }
            parent.onTextChange?()
            scheduleHighlight()
        }

        func scheduleHighlight() {
            highlightWork?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.applyHighlight() }
            highlightWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }

        // MARK: 输入拦截:自动配对 / 回车续列表 / Tab 缩进

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString string: String?) -> Bool {
            guard !isProgrammaticEdit, let string, !string.isEmpty else { return true }
            // 输入法组字期间不拦截
            if textView.hasMarkedText() { return true }

            // Tab → 两个空格
            if string == "\t" {
                perform { $0.insertText("  ", replacementRange: range) }
                return false
            }
            // 回车 → 列表续行
            if string == "\n" {
                switch ListContinuation.enterAction(text: textView.string, caret: range.location) {
                case .insert(let insertion):
                    perform {
                        $0.insertText(insertion, replacementRange: range)
                        $0.scrollRangeToVisible($0.selectedRange())
                    }
                    return false
                case .endList(let markerRange):
                    // 删除空标记后走默认换行,即结束列表
                    perform { $0.insertText("", replacementRange: markerRange) }
                    return true
                case .plain:
                    return true
                }
            }
            // 单字符:自动配对 / 包裹 / 跳过闭符号
            if (string as NSString).length == 1,
               let action = AutoPair.action(text: textView.string, selection: range, input: string) {
                perform {
                    $0.insertText(action.replacement, replacementRange: action.range)
                    $0.setSelectedRange(action.selection)
                }
                return false
            }
            return true
        }

        /// 以「可撤销、不递归」的方式执行程序化编辑
        private func perform(_ edit: (NSTextView) -> Void) {
            guard let tv = textView else { return }
            isProgrammaticEdit = true
            edit(tv)
            isProgrammaticEdit = false
        }

        // MARK: 光标事件:当前行高亮 + 打字机模式

        func textViewDidChangeSelection(_ notification: Notification) {
            updateCurrentLineHighlight()
            guard parent.typewriterMode,
                  let tv = textView,
                  tv.selectedRange().length == 0 else { return }
            // 鼠标点击/拖动引起的光标移动不做居中,避免视图跳动
            if let event = NSApp.currentEvent,
               [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .scrollWheel].contains(event.type) { return }
            centerCaret(in: tv)
        }

        /// 打字机模式:把光标所在行滚动到可视区域垂直中心
        private func centerCaret(in tv: NSTextView) {
            guard let layout = tv.layoutManager,
                  let container = tv.textContainer,
                  let scrollView = tv.enclosingScrollView else { return }
            let sel = tv.selectedRange().location
            guard sel <= (tv.string as NSString).length else { return }
            let glyph = layout.glyphIndexForCharacter(at: sel)
            var rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 0),
                                           in: container)
            rect.origin.y += tv.textContainerInset.height
            let visibleHeight = scrollView.contentSize.height
            let targetY = max(0, rect.midY - visibleHeight / 2)
            tv.scroll(NSPoint(x: 0, y: targetY))
        }

        /// 当前行高亮(临时属性,不与语法高亮冲突)
        func updateCurrentLineHighlight() {
            guard let tv = textView, let layout = tv.layoutManager else { return }
            let ns = tv.string as NSString
            layout.removeTemporaryAttribute(.backgroundColor,
                                            forCharacterRange: NSRange(location: 0, length: ns.length))
            guard parent.highlightCurrentLine else { return }
            let caret = min(tv.selectedRange().location, ns.length)
            let paraRange = ns.paragraphRange(for: NSRange(location: caret, length: 0))
            layout.addTemporaryAttribute(.backgroundColor,
                                         value: NSColor.labelColor.withAlphaComponent(0.05),
                                         forCharacterRange: paraRange)
        }

        // MARK: 语法高亮

        /// 上次应用的缩放系数(变化时重新高亮)
        var lastFontScale: Double = 1.0

        func applyHighlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let text = tv.string
            let ns = text as NSString
            guard ns.length > 0 else { return }
            let scale = parent.fontScale
            lastFontScale = scale
            let baseSize = 14 * scale

            // 超出上限只高亮可视区域,避免大文件卡顿
            let targetRange: NSRange
            if ns.length <= MarkdownEditorView.fullHighlightLimit {
                targetRange = NSRange(location: 0, length: ns.length)
            } else {
                let visible = tv.visibleRect
                let glyphRange = tv.layoutManager?.glyphRange(forBoundingRect: visible, in: tv.textContainer ?? NSTextContainer())
                targetRange = tv.layoutManager?.characterRange(forGlyphRange: glyphRange ?? NSRange(location: 0, length: 0), actualGlyphRange: nil)
                    ?? NSRange(location: 0, length: 0)
            }
            guard targetRange.length > 0 else { return }

            // 行级 token 可能跨越可视边界,向上取整到段落边界
            let paraRange = ns.paragraphRange(for: targetRange)
            let tokens = MarkdownHighlighter.tokens(in: ns.substring(with: paraRange))

            storage.beginEditing()
            // 基础样式
            let baseFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular)
            storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: paraRange)
            // 语义 token 样式
            for (range, token) in tokens {
                let absRange = NSRange(location: paraRange.location + range.location, length: range.length)
                guard NSMaxRange(absRange) <= ns.length else { continue }
                switch token {
                case .heading(let level):
                    let size: CGFloat = level == 1 ? 22 * scale : level == 2 ? 18 * scale : level == 3 ? 16 * scale : baseSize
                    storage.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
                        .foregroundColor: NSColor.systemBlue,
                    ], range: absRange)
                case .bold:
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseSize, weight: .bold), range: absRange)
                case .italic:
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular).italic(), range: absRange)
                case .strikethrough:
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ], range: absRange)
                case .codeSpan:
                    storage.addAttributes([
                        .backgroundColor: NSColor.quaternaryLabelColor,
                        .foregroundColor: NSColor.systemPurple,
                    ], range: absRange)
                case .codeBlock:
                    storage.addAttributes([
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.5),
                        .foregroundColor: NSColor.systemPurple,
                    ], range: absRange)
                case .link:
                    storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: absRange)
                case .quote:
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: absRange)
                case .listMarker:
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: absRange)
                case .math:
                    storage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: absRange)
                }
            }
            storage.endEditing()
            tv.typingAttributes = [.font: baseFont, .foregroundColor: NSColor.labelColor]
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MDVTextView()
        textView.imageDirectory = imageDirectory
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // 关闭自动替换,保证 Markdown 源码不被「智能标点」污染
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.delegate = context.coordinator
        textView.string = text
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        box.textView = textView
        context.coordinator.applyHighlight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 仅在外部(加载文档/放弃修改)导致文本不一致时替换,用户输入路径不会触发
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let maxLoc = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, maxLoc), length: 0))
            context.coordinator.applyHighlight()
        }
        // 缩放系数变化(⌘+/⌘-/⌘0)→ 重排字号
        if context.coordinator.lastFontScale != fontScale {
            context.coordinator.applyHighlight()
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.highlightWork?.cancel()
    }
}

// MARK: - NSFont 斜体辅助

private extension NSFont {
    func italic() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}
