// Markdown 阅读器 - 原生 macOS Markdown 阅读 + 编辑工具
// 三栏:文档列表(可收起) / 大纲(滚动同步高亮) / 正文(预览 ⌘1 · 分屏 ⌘2 · 编辑 ⌘3)
// 阅读:KaTeX / Mermaid / Callout / Emoji 短代码 / Front Matter / [TOC] / 脚注 / 代码复制
// 编辑:语法高亮 / 智能输入 / 图片粘贴 / 打字机模式 / 当前行高亮 / 三道数据安全防线
// 效率:⌘P 快速打开 / 任务复选框点击回写 / 文件自动重载 / 导出 HTML / 导出 PDF

import SwiftUI
import AppKit

extension Notification.Name {
    /// 菜单栏「保存」命令转发给 ContentView
    static let mdvSaveRequest = Notification.Name("MDVSaveRequest")
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
        .commands {
            // 菜单栏「文件 → 保存」⌘S
            CommandGroup(replacing: .saveItem) {
                Button("保存") {
                    NotificationCenter.default.post(name: .mdvSaveRequest, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}
