import Cocoa

class OSXSpaceObserver: NSObject, NSWindowDelegate {
    private var trackers: [Int: SpaceTracker] = [:]
    private weak var ssd: SystemScreenDelegate?
    private var sst: SystemSpaceTracker
    private weak var notifier: EventNotifier?

    init(_ notifier: EventNotifier?, _ ssd: SystemScreenDelegate, _ sst: SystemSpaceTracker) {
        self.notifier = notifier
        self.ssd = ssd
        self.sst = sst
        super.init()
        for screen in ssd.screens {
            makeWindow(screen)
        }
        sst.onSpaceChanged { [weak self] in
            self?.emitSpaceWillChangeEvent()
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
    private func makeWindow(_ screen: ScreenDelegate) -> Int {
        let win = sst.makeTracker(screen)
        trackers[win.id] = win
        return win.id
    }

    /// Emits a SpaceWillChangeEvent on the notifier this observer was
    /// constructed with.
    ///
    /// Used during initialization.
    func emitSpaceWillChangeEvent() {
        guard let ssd = ssd else { return }
        let visible = sst.visibleIds()
        log.debug("spaceChanged: visible=\(visible)")

        let screens = ssd.screens

        var visibleByScreen = [[Int]](repeating: [], count: screens.count)
        for id in visible {
            // This is O(N^2) in the number of screens, but thankfully that
            // never gets large.
            // TODO: Use directDisplayID?
            guard let screen = trackers[id]?.screen(ssd) else {
                log.info("Window id \(id) not associated with any screen")
                continue
            }
            for (idx, scr) in screens.enumerated() {
                if scr.equalTo(screen) {
                    visibleByScreen[idx].append(id)
                    break
                }
            }
        }

        var visiblePerScreen: [Int] = []
        for (idx, visible) in visibleByScreen.enumerated() {
            if let id = visible.min() {
                visiblePerScreen.append(id)
            } else {
                visiblePerScreen.append(makeWindow(screens[idx]))
            }
        }
        notifier?.notify(SpaceWillChangeEvent(external: true, ids: visiblePerScreen))
    }
}

protocol SystemSpaceTracker {
    /// Installs a handler to be called when the current space changes.
    func onSpaceChanged(_ handler: @escaping () -> ())

    /// Creates a tracker for the current space on the given screen.
    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker

    /// Returns the list of IDs of SpaceTrackers whose spaces are currently visible.
    func visibleIds() -> [Int]
}

class OSXSystemSpaceTracker: SystemSpaceTracker {
    func onSpaceChanged(_ handler: @escaping () -> ()) {
        let sharedWorkspace = NSWorkspace.shared
        let notificationCenter = sharedWorkspace.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: sharedWorkspace,
            queue: nil
        ) { _ in handler() }
    }

    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker {
        OSXSpaceTracker(screen)
    }

    func visibleIds() -> [Int] {
        (NSWindow.windowNumbers(options: []) ?? []) as! [Int]
    }
}

protocol SpaceTracker {
    var id: Int { get }
    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate?
}

class OSXSpaceTracker: NSObject, NSWindowDelegate, SpaceTracker {
    let win: NSWindow

    var id: Int { win.windowNumber }

    init(_ screen: ScreenDelegate) {
        //win = NSWindow(contentViewController: NSViewController(nibName: nil, bundle: nil))
        // Size must be non-zero to receive occlusion state events.
        let rect = /*NSRect.zero */NSRect(x: 0, y: 0, width: 1, height: 1)
        win = NSWindow(
            contentRect: rect,
            styleMask: .borderless/*[.titled, .resizable, .miniaturizable]*/,
            backing: .buffered,
            defer: true,
            screen: screen.native)
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

        super.init()
        win.delegate = self

        win.makeKeyAndOrderFront(nil)
        log.debug("new window windowNumber=\(win.windowNumber)")
    }

    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate? {
        guard let screen = win.screen else {
            return nil
        }
        // This class should only be used with a "real" SystemScreenDelegate impl.
        return ssd.delegateForNative(screen: screen)!
    }

    func windowDidChangeScreen(_ notification: Notification) {
        let win = notification.object as! NSWindow
        log.debug("window \(win.windowNumber) changed screen; active=\(win.isOnActiveSpace)")
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        let win = notification.object as! NSWindow
        log.debug("""
            window \(win.windowNumber) occstchanged; \
            occVis=\(win.occlusionState.contains(NSWindow.OcclusionState.visible)), \
            vis=\(win.isVisible), activeSpace=\(win.isOnActiveSpace)
        """)
        let visible = (NSWindow.windowNumbers(options: []) ?? []) as! [Int]
        log.debug("visible=\(visible)")
        // TODO: Use this event to detect space merges.
    }
}

class FakeSystemSpaceTracker: SystemSpaceTracker {
    init() {}

    var spaceChangeHandler: Optional<() -> ()> = nil
    func onSpaceChanged(_ handler: @escaping () -> ()) {
        spaceChangeHandler = handler
    }

    var trackersMade: [StubSpaceTracker] = []
    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker {
        let tracker = StubSpaceTracker(screen, id: nextSpaceId)
        trackersMade.append(tracker)
        visible.append(tracker.id)
        return tracker
    }

    var nextSpaceId: Int { trackersMade.count + 1 }

    var visible: [Int] = []
    func visibleIds() -> [Int] { visible }
}

class StubSpaceTracker: SpaceTracker {
    var screen: ScreenDelegate?
    var id: Int
    init(_ screen: ScreenDelegate?, id: Int) {
        self.screen = screen
        self.id = id
    }
    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate? { screen }
}
