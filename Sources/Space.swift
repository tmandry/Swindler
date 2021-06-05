import Cocoa

protocol SpaceObserver {
    /// Registers a handler to be called on a space change.
    ///
    /// The handler is called with an array of unique integers identifying the
    /// active space on each screen. The handler is called immediately upon
    /// registration with the current space id.
    func onSpaceChanged(_ handler: @escaping ([Int]) -> Void)
}

class FakeSpaceObserver: SpaceObserver {
    var handlers: [([Int]) -> Void] = []
    var spaceId: [Int] = [1] {
        didSet {
            newSpaceId = max(newSpaceId, spaceId.max() ?? 0 + 1)
            for handler in handlers {
                handler(spaceId)
            }
        }
    }
    var newSpaceId: Int = 2
    func onSpaceChanged(_ handler: @escaping ([Int]) -> Void) {
        handler(spaceId)
        handlers.append(handler)
    }
}

class OSXSpaceObserver: NSObject, NSWindowDelegate, SpaceObserver {
    private var windows: [Int: NSWindow] = [:]

    override init() {
        super.init()
        for screen in NSScreen.screens {
            makeWindow(screen)
        }
        // TODO: Detect screen configuration changes
    }

    /// Create an invisible window for tracking the current space.
    ///
    /// This helps us identify the space when we return to it in the future.
    /// It also helps us detect when a space is closed and merged into another.
    /// Without the window events we wouldn't have a way of noticing when this
    /// happened.
    @discardableResult
    private func makeWindow(_ screen: NSScreen) -> Int {
        //win = NSWindow(contentViewController: NSViewController(nibName: nil, bundle: nil))
        // Size must be non-zero to receive occlusion state events.
        let rect = /*NSRect.zero */NSRect(x: 0, y: 0, width: 1, height: 1)
        let win = NSWindow(contentRect: rect, styleMask: .borderless/*[.titled, .resizable, .miniaturizable]*/, backing: .buffered, defer: true, screen: screen)
        win.delegate = self
        //win.title = "test"
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.animationBehavior = .none
        win.backgroundColor = NSColor.clear
        win.level = .floating
        win.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        if #available(macOS 10.11, *) {
            win.collectionBehavior.update(with: .fullScreenDisallowsTiling)
        }
        win.makeKeyAndOrderFront(nil)
        log.debug("new window windowNumber=\(win.windowNumber)")
        windows[win.windowNumber] = win
        return win.windowNumber
    }

    func windowDidChangeScreen(_ notification: Notification) {
        let win = notification.object as! NSWindow
        log.debug("window \(win.windowNumber) changed screen; active=\(win.isOnActiveSpace)")
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        let win = notification.object as! NSWindow
        log.debug("window \(win.windowNumber) occstchanged; occVis=\(win.occlusionState.contains(NSWindow.OcclusionState.visible)), vis=\(win.isVisible), activeSpace=\(win.isOnActiveSpace)")
        let visible = (NSWindow.windowNumbers(options: []) ?? []) as! [Int]
        log.debug("visible=\(visible)")
        // TODO: Use this event to detect space merges.
    }

    /// Installs a handler to be called when the current space changes.
    func onSpaceChanged(_ handler: @escaping ([Int]) -> Void) {
        let sharedWorkspace = NSWorkspace.shared
        let notificationCenter = sharedWorkspace.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: sharedWorkspace,
            queue: nil
        ) { _ in self.spaceChanged(handler) }
        spaceChanged(handler)
    }

    private func spaceChanged(_ handler: @escaping ([Int]) -> Void) {
        let visible = (NSWindow.windowNumbers(options: []) ?? []) as! [Int]
        log.debug("spaceChanged: visible=\(visible)")

        var visibleByScreen: [NSScreen: [Int]] = [:]
        for id in visible {
            guard let screen = windows[id]?.screen else {
                log.info("Window id \(id) not associated with any screen")
                continue
            }
            if !visibleByScreen.keys.contains(screen) {
                visibleByScreen[screen] = []
            }
            visibleByScreen[screen]!.append(id)
        }

        var visiblePerScreen: [Int] = []
        for screen in NSScreen.screens {
            // TODO: Break ties deterministically (and test)
            if let id = visibleByScreen[screen]?.first {
                visiblePerScreen.append(id)
            } else {
                visiblePerScreen.append(makeWindow(screen))
            }
        }
        handler(visiblePerScreen)
    }
}
