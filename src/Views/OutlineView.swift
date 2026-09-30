import SwiftUI

// MARK: - 大纲面板(支持当前章节滚动同步高亮)

struct OutlineView: View {
    let headings: [Heading]
    @Binding var scrollTarget: Int?
    /// 当前可视章节序号(-1 表示文首,尚未进入任何标题)
    @Binding var activeHeading: Int

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
                            .foregroundColor(heading.id == activeHeading ? .accentColor : .primary)
                            .fontWeight(heading.id == activeHeading ? .semibold : (heading.level <= 2 ? .medium : .regular))
                            .lineLimit(1)
                            .help(heading.text)
                            .padding(.leading, CGFloat(heading.level - 1) * 12)
                            .contentShape(Rectangle())
                            .id(heading.id)
                            .onTapGesture { scrollTarget = heading.id }
                    }
                    .listStyle(.plain)
                    .onChange(of: activeHeading) { idx in
                        guard idx >= 0, headings.contains(where: { $0.id == idx }) else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 150, idealWidth: 200)
    }
}
