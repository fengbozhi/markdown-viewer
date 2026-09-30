// Markdown 阅读器 - macOS 两栏 Markdown 阅读器(参考 Typora)
// 左栏:文件列表(文件名 + 文档标题,可收起)  中栏:大纲(可收起,滚动同步高亮)  右栏:完整渲染
// 双击图片:弹窗全屏查看,支持捏合缩放与拖动
// 功能亮点:KaTeX 数学公式 / Mermaid / [TOC] 目录 / 脚注 / 代码复制 / 文件变更自动重载 / 导出 HTML / 源码模式

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
