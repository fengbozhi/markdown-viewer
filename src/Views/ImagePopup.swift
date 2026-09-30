import AppKit
import WebKit

// MARK: - 图片全屏弹窗(双击图片打开;Esc/单击关闭;捏合缩放;拖动平移)

final class PopupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PopupImageContainer: NSView {
    let imageView = NSImageView()
    var onClose: (() -> Void)?
    private var fitSize: NSSize = .zero
    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var gestureStartScale: CGFloat = 1
    private var gestureStartOffset: CGPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(onMagnify(_:)))
        addGestureRecognizer(magnify)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.buttonMask = 1
        addGestureRecognizer(pan)
        let click = NSClickGestureRecognizer(target: self, action: #selector(onClick))
        click.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        scale = 1
        offset = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        relayoutImage()
    }

    private func relayoutImage() {
        guard let img = imageView.image else { return }
        let margin: CGFloat = 56
        let availW = max(bounds.width - margin * 2, 10)
        let availH = max(bounds.height - margin * 2, 10)
        let isz = img.size
        let s = min(availW / max(isz.width, 1), availH / max(isz.height, 1))
        fitSize = NSSize(width: isz.width * s, height: isz.height * s)
        let size = NSSize(width: fitSize.width * scale, height: fitSize.height * scale)
        let origin = NSPoint(x: bounds.midX + offset.x - size.width / 2,
                             y: bounds.midY - offset.y - size.height / 2)
        imageView.frame = NSRect(origin: origin, size: size)
    }

    @objc private func onMagnify(_ g: NSMagnificationGestureRecognizer) {
        switch g.state {
        case .began:
            gestureStartScale = scale
        case .changed:
            scale = min(max(gestureStartScale * (1 + g.magnification), 1), 12)
        default: break
        }
    }

    @objc private func onPan(_ g: NSPanGestureRecognizer) {
        let t = g.translation(in: self)
        switch g.state {
        case .began:
            gestureStartOffset = offset
        case .changed:
            offset = CGPoint(x: gestureStartOffset.x + t.x, y: gestureStartOffset.y - t.y)
        default: break
        }
    }

    @objc private func onClick() {
        onClose?()
    }
}

final class PopupImageWindowController: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "imagePopup"

    private var window: PopupWindow?
    private var keyMonitor: Any?
    private weak var container: PopupImageContainer?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName, let src = message.body as? String else { return }
        present(resourceString: src)
    }

    private func resolvePath(_ src: String) -> String? {
        if src.hasPrefix("local://") || src.hasPrefix("file://") {
            guard let url = URL(string: src) else { return nil }
            return url.path.removingPercentEncoding ?? url.path
        }
        if src.hasPrefix("/") { return src }
        return nil
    }

    private func present(resourceString src: String) {
        close()
        guard let path = resolvePath(src),
              let image = NSImage(contentsOfFile: path),
              let screen = NSScreen.main else { return }

        let win = PopupWindow(contentRect: screen.frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        win.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1.0)
        let container = PopupImageContainer(frame: screen.frame)
        container.setImage(image)
        container.onClose = { [weak self] in self?.close() }
        win.contentView = container
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        window = win
        self.container = container

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 {  // Esc
                DispatchQueue.main.async { self?.close() }
                return nil
            }
            return ev
        }
    }

    @objc func close() {
        container?.onClose = nil
        container = nil
        window?.orderOut(nil)
        window = nil
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}
