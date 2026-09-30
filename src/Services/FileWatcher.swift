import Foundation

/// 文件/目录变更监听器(基于 DispatchSource,低开销)
/// 用于实现 Typora 式的「外部修改后自动刷新」
final class FileWatcher {

    /// 变更回调(已在主线程,做了 0.25s 防抖)
    var onEvent: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var path: String?
    private var debounceItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    init(debounceInterval: TimeInterval = 0.25) {
        self.debounceInterval = debounceInterval
    }

    /// 开始监听指定路径;重复调用会先停止旧监听
    func watch(path: String) {
        stop()
        self.path = path
        openSource()
    }

    func stop() {
        debounceItem?.cancel()
        debounceItem = nil
        source?.cancel()
        source = nil
        path = nil
    }

    deinit { stop() }

    private func openSource() {
        source?.cancel()
        source = nil
        guard let path else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main)
        src.setEventHandler { [weak self] in self?.handleEvent() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func handleEvent() {
        guard let source else { return }
        // 编辑器原子保存(先写临时文件再 rename 替换)会使旧 fd 失效,需要重新挂监听
        if source.data.contains(.rename) || source.data.contains(.delete) {
            openSource()
        }
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onEvent?() }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
