import SwiftUI
import AppKit

// MARK: - 键盘事件监听(快速打开面板的 ↑↓/回车/Esc 导航)

struct KeyEventMonitor: NSViewRepresentable {
    /// 返回 true 表示消费该事件
    let onKey: (UInt16) -> Bool

    final class Coordinator {
        var monitor: Any?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onKey(event.keyCode) ? nil : event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            coordinator.monitor = nil
        }
    }
}

// MARK: - 快速打开面板(Obsidian Quick Switcher / VS Code ⌘P 风格)

struct QuickOpenView: View {
    let items: [DocItem]
    @Binding var query: String
    @Binding var selection: Int
    let onSubmit: (DocItem) -> Void
    let onClose: () -> Void

    @FocusState private var fieldFocused: Bool

    /// 模糊匹配结果:按打分降序,最多 30 条
    private var results: [DocItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(items.prefix(30)) }
        return items
            .compactMap { item -> (DocItem, Int)? in
                let s = max(FuzzyMatch.score(item.fileName, q),
                            FuzzyMatch.score(item.docTitle, q))
                return s >= 0 ? (item, s) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(30)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("输入文件名或标题,快速跳转…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onSubmit(submitCurrent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()
            if results.isEmpty {
                Text("没有匹配的文档")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                                row(index: idx, item: item)
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { idx in
                        if let item = results[safe: idx] {
                            withAnimation(.easeOut(duration: 0.08)) {
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .background(KeyEventMonitor(onKey: handleKey))
        .onAppear {
            fieldFocused = true
            selection = 0
        }
        .onChange(of: query) { _ in selection = 0 }
    }

    private func row(index: Int, item: DocItem) -> some View {
        Button {
            onSubmit(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !item.docTitle.isEmpty {
                        Text(item.docTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(item.dateLabel)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(index == selection ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
    }

    private func submitCurrent() {
        if let item = results[safe: selection] {
            onSubmit(item)
        }
    }

    /// ↑125 ↓126 ⏎36/76 Esc53
    private func handleKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 125:
            selection = min(selection + 1, max(0, results.count - 1))
            return true
        case 126:
            selection = max(selection - 1, 0)
            return true
        case 36, 76:
            submitCurrent()
            return true
        case 53:
            onClose()
            return true
        default:
            return false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
