import SwiftUI

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
