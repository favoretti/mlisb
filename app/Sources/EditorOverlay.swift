import AppKit

/// A pass-through view on the editor's text view that redraws when its text or layout changes.
class EditorOverlay: NSView {
    weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []
    private var signature = CGPoint.zero
    private var wanted = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Called when the text changes, before the redraw.
    func textDidChange() {}

    /// Adds the overlay to the editor's text view in `view`'s window, which appears a moment after the pane.
    func attach(from view: NSView, tries: Int = 0) {
        wanted = true
        guard let textView = view.window?.contentView?.editorTextView() else {
            guard tries < 30 else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                if wanted { attach(from: view, tries: tries + 1) }
            }
            return
        }
        guard superview !== textView else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        self.textView = textView
        frame = textView.bounds
        autoresizingMask = [.width, .height]
        textView.addSubview(self)
        textDidChange()
        observers = [NSText.didChangeNotification, NSView.frameDidChangeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSText.didChangeNotification { self.textDidChange() }
                    self.needsDisplay = true
                    // Layout of the edited text finishes after the notification.
                    DispatchQueue.main.async { self.needsDisplay = true }
                }
            }
        }
    }

    func detach() {
        wanted = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        removeFromSuperview()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil else { return }
        // The engine relays out without telling us (images, folded syntax, a new inset), so poll.
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.superview != nil else { return }
                let now = CGPoint(x: self.textView?.textContainerOrigin.x ?? 0,
                                  y: self.textView?.textLayoutManager?.usageBoundsForTextContainer.height ?? 0)
                if now != self.signature {
                    self.signature = now
                    self.needsDisplay = true
                }
            }
        }
    }
}
