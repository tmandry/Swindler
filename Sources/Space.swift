import Cocoa

class OSXSpaceObserver: NSObject, NSWindowDelegate, Encodable {
    private var trackers: [Int: SpaceTracker] = [:]
    private weak var ssd: SystemScreenDelegate?
    private var sst: SystemSpaceTracker
    private weak var notifier: EventNotifier?
    private var nextId: Int = 1

    // Maps from NSWindow id back to space id.
    var idMap: [NSNumber: Int] = [:]

    convenience init(_ notifier: EventNotifier?, _ ssd: SystemScreenDelegate, _ sst: SystemSpaceTracker) {
        self.init(notifier, ssd, sst) { this in
            for screen in ssd.screens {
                this.makeWindow(screen)
            }
        }
    }

    private init(_ notifier: EventNotifier?, _ ssd: SystemScreenDelegate, _ sst: SystemSpaceTracker, makeTrackers: (OSXSpaceObserver) throws -> ()) rethrows {
        self.notifier = notifier
        self.ssd = ssd
        self.sst = sst
        super.init()
        // Don't install the event handler until we're done making the initial
        // set of trackers.
        try makeTrackers(self)
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
        let id = nextId
        let win = sst.makeTracker(screen)
        idMap[win.systemId] = id
        nextId += 1
        trackers[id] = win
        log.info("Made tracker \(id) for \(screen)")
        return id
    }

    /// Emits a SpaceWillChangeEvent on the notifier this observer was
    /// constructed with.
    ///
    /// Used during initialization.
    func emitSpaceWillChangeEvent() {
        guard let ssd = ssd else { return }
        let visible = sst.visibleIds().compactMap({ idMap[$0] })
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

    enum CodingKeys: CodingKey {
        case nextSpaceId
        case spaceTrackers
    }

    required convenience init(from decoder: Decoder, _ notifier: EventNotifier?, _ ssd: SystemScreenDelegate, _ sst: SystemSpaceTracker) throws {
        try self.init(notifier, ssd, sst) { this in
            let object = try decoder.container(keyedBy: CodingKeys.self)
            this.nextId = try object.decode(Int.self, forKey: .nextSpaceId)
            this.trackers = try object.decode(
                [Int: OSXSpaceTracker].self,
                forKey: .spaceTrackers)
            for (id, tracker) in this.trackers {
                this.idMap[tracker.systemId] = id
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: CodingKeys.self)
        let trackers = trackers.compactMapValues({ $0 as? OSXSpaceTracker })
        try object.encode(nextId, forKey: .nextSpaceId)
        try object.encode(trackers, forKey: .spaceTrackers)
    }
}

protocol SystemSpaceTracker {
    /// Installs a handler to be called when the current space changes.
    func onSpaceChanged(_ handler: @escaping () -> ())

    /// Creates a tracker for the current space on the given screen.
    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker

    /// Returns the list of IDs of SpaceTrackers whose spaces are currently visible.
    func visibleIds() -> [NSNumber]
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
        let tracker = OSXSpaceTracker(screen)
        return tracker
    }

    func visibleIds() -> [NSNumber] {
        NSWindow.windowNumbers(options: []) ?? []
    }
}

protocol SpaceTracker {
    var systemId: NSNumber { get }
    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate?
}

class OSXSpaceTracker: NSObject, NSWindowDelegate, Codable, SpaceTracker {
    let win: NSWindow

    var systemId: NSNumber { win.windowNumber as NSNumber }

    private init(screen: ScreenDelegate?) {
        //win = NSWindow(contentViewController: NSViewController(nibName: nil, bundle: nil))
        // Size must be non-zero to receive occlusion state events.
        let rect = /*NSRect.zero */NSRect(x: 0, y: 0, width: 1, height: 1)
        win = NSWindow(
            contentRect: rect,
            styleMask: .borderless/*[.titled, .resizable, .miniaturizable]*/,
            backing: .buffered,
            defer: true,
            screen: screen?.native)
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

    convenience init(_ screen: ScreenDelegate) {
        self.init(screen: screen)
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
        //debug()
    }

    private class ArchiverDelegate: NSObject, NSKeyedArchiverDelegate {
        // Make sure we don't try to encode unencodable objects. AppKit does this by
        // defining a custom encoder.
        func archiver(_ archiver: NSKeyedArchiver, willEncode object: Any) -> Any? {
            if object as? NSWindow != nil || object as? NSView != nil {
                return nil
            }
            return object
        }
    }

    func debug() {
        let delegate = ArchiverDelegate()
        let encoder = NSKeyedArchiver(requiringSecureCoding: false)
        encoder.delegate = delegate
        encoder.outputFormat = .xml
        win.encodeRestorableState(with: encoder)
        log.info("::: SpaceTracker \(win.windowNumber) restore state :::")
        log.info(String(decoding: encoder.encodedData, as: UTF8.self))
        log.info(":::")
    }

    func encode(to encoder: Encoder) throws {
        let delegate = ArchiverDelegate()
        let nsEncoder = NSKeyedArchiver()
        nsEncoder.delegate = delegate
        win.encodeRestorableState(with: nsEncoder)
        var object = encoder.singleValueContainer()
        try object.encode(nsEncoder.encodedData)
    }

    required convenience init(from decoder: Decoder) throws {
        let object = try decoder.singleValueContainer()
        let nsDecoder = try NSKeyedUnarchiver(forReadingFrom: object.decode(Data.self))
        self.init(screen: nil)
        win.restoreState(with: nsDecoder)
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
        let tracker = StubSpaceTracker(nextSpaceId as NSNumber, screen)
        visible.append(nextSpaceId)
        trackersMade.append(tracker)
        return tracker
    }

    var nextSpaceId: Int { trackersMade.count + 1 }

    var visible: [Int] = []
    func visibleIds() -> [NSNumber] { visible as [NSNumber] }
}

class StubSpaceTracker: SpaceTracker {
    var screen: ScreenDelegate?
    var systemId: NSNumber
    init(_ id: NSNumber, _ screen: ScreenDelegate?) {
        systemId = id
        self.screen = screen
    }
    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate? { screen }
}
