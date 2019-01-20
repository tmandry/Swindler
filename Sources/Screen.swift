import PromiseKit

// MARK: - Screen

/// A physical display.
public final class Screen: Equatable, CustomDebugStringConvertible {
    private let delegate_: ScreenDelegate
    private let queue_: DispatchQueue

    var delegate: ScreenDelegate {
        dispatchPrecondition(condition: .onQueue(queue_))
        return delegate_
    }

    internal init(delegate: ScreenDelegate) {
        delegate_ = delegate
        queue_ = delegate_.queue
        dispatchPrecondition(condition: .onQueue(queue_))
    }

    public var debugDescription: String { return delegate.debugDescription }

    /// The frame defining the screen boundaries in global coordinates.
    /// -Note: x and y may be negative.
    public var frame: CGRect { return delegate.frame }

    /// The frame defining the screen boundaries in global coordinates, excluding the menu bar and
    /// dock.
    public var applicationFrame: CGRect { return delegate.applicationFrame }
}
public func ==(lhs: Screen, rhs: Screen) -> Bool {
    return lhs.delegate.equalTo(rhs.delegate)
}

protocol SystemScreenDelegate {
    var lock_: NSLock { get }
    var screens_: [ScreenDelegate] { get }

    var maxY: CGFloat { get }

    func onScreenLayoutChanged(_ handler: @escaping (ScreenLayoutChangedEvent) -> Void)
}

extension SystemScreenDelegate {
    var screens: [ScreenDelegate] {
        lock_.lock()
        defer { lock_.unlock() }
        return screens_
    }

    var maxY: CGFloat {
        return calculateMaxY(screens)
    }
}

func calculateMaxY(_ screens: [ScreenDelegate]) -> CGFloat {
    var maxY = 0.0 as CGFloat
    for screen in screens {
        maxY = CGFloat.maximum(screen.frame.maxY, maxY)
    }
    return maxY
}

protocol ScreenDelegate: class, CustomDebugStringConvertible {
    var frame: CGRect { get }
    var applicationFrame: CGRect { get }
    var queue: DispatchQueue { get }

    func equalTo(_ other: ScreenDelegate) -> Bool
}

struct FakeSystemScreenDelegate: SystemScreenDelegate {
    typealias Delegate = FakeScreenDelegate

    var lock_: NSLock
    var screens_: [ScreenDelegate]

    func onScreenLayoutChanged(_ handler: @escaping (ScreenLayoutChangedEvent) -> Void) {}

    var screens: [ScreenDelegate] {
        get {
            lock_.lock()
            defer { lock_.unlock() }
            return screens_
        }
        set {
            lock_.lock()
            defer { lock_.unlock() }
            screens_ = newValue
        }
    }

    init(screens: [ScreenDelegate]) {
        lock_ = NSLock()
        screens_ = screens
    }
}

final class FakeScreenDelegate: ScreenDelegate {
    let frame: CGRect
    let applicationFrame: CGRect
    let queue: DispatchQueue

    init(frame: CGRect, applicationFrame: CGRect, queue: DispatchQueue = DispatchQueue.main) {
        self.frame = frame
        self.applicationFrame = applicationFrame
        self.queue = queue
    }

    func equalTo(_ other: ScreenDelegate) -> Bool { return false }

    var debugDescription: String {
        return "FakeScreen(frame: \(frame), applicationFrame: \(applicationFrame))"
    }
}

// MARK: - OSXScreenDelegate

protocol NSScreenType {
    var frame: CGRect { get }
    var visibleFrame: CGRect { get }
    var deviceDescription: [NSDeviceDescriptionKey: Any] { get }

    var displayName: String { get }
}
extension NSScreen: NSScreenType {
    /// The name for the display (usually, the manufacturer and model number).
    /// -Note: This is expensive to get, and should be cached in a stored property.
    var displayName: String {
        guard let info = infoForCGDisplay(numberForScreen(self as NSScreen),
                                          options: kIODisplayOnlyPreferredName) else {
            return "Unknown screen"
        }
        guard let localizedNames = info[kDisplayProductName] as! NSDictionary? as Dictionary?,
              let name = localizedNames.values.first as! NSString? as String? else {
            return "Unnamed screen"
        }
        return name
    }
}

private func createDelegates(_ queue: DispatchQueue) -> [OSXScreenDelegate<NSScreen>] {
    return NSScreen.screens.map{ OSXScreenDelegate(nsScreen: $0, queue: queue) }
}

class OSXSystemScreenDelegate: SystemScreenDelegate {
    typealias Delegate = OSXScreenDelegate<NSScreen>

    var lock_: NSLock
    var screens_: [ScreenDelegate]
    var delegates: [Delegate]

    private var handler: Optional<(ScreenLayoutChangedEvent) -> Void>

    let queue: DispatchQueue

    init(queue: DispatchQueue) {
        lock_ = NSLock()
        delegates = createDelegates(queue)
        screens_ = delegates.map{ $0 as ScreenDelegate }
        self.queue = queue

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared,
            queue: OperationQueue.main
        ) { _ in
            self.handleScreenLayoutChange()
        }
    }

    func onScreenLayoutChanged(_ handler: @escaping (ScreenLayoutChangedEvent) -> Void) {
        self.handler = handler
    }

    private func handleScreenLayoutChange() {
        // Make a new screen delegate for every screen, because NSScreen objects can become
        // stale.
        let newScreens = createDelegates(queue)

        let event = handleScreenChange(newScreens: newScreens, oldScreens: delegates)

        do {
            lock_.lock()
            defer { lock_.unlock() }
            delegates = newScreens
            screens_ = newScreens.map{ $0 as ScreenDelegate }
        }

        handler?(event)
    }
}

func handleScreenChange<NSScreenT: NSScreenType>(newScreens: [OSXScreenDelegate<NSScreenT>],
                                                 oldScreens: [OSXScreenDelegate<NSScreenT>])
-> ScreenLayoutChangedEvent {
    var oldScreensById: [CGDirectDisplayID: OSXScreenDelegate<NSScreenT>] = Dictionary()
    for oldScreen in oldScreens {
        oldScreensById[oldScreen.directDisplayID] = oldScreen
    }

    var addedScreens: [Screen] = []
    var changedScreens: [Screen] = []
    var unchangedScreens: [Screen] = []

    for newScreen in newScreens {
        let newScreenWrapped = Screen(delegate: newScreen)

        guard let oldScreen = oldScreensById[newScreen.directDisplayID] else {
            addedScreens.append(newScreenWrapped)
            continue
        }

        // Remove from dict to signifiy that we've seen it.
        oldScreensById[newScreen.directDisplayID] = nil

        if newScreen.frame != oldScreen.frame
        || newScreen.applicationFrame != oldScreen.applicationFrame {
            changedScreens.append(newScreenWrapped)
        } else {
            unchangedScreens.append(newScreenWrapped)
        }
    }

    // All old screens that match a new screen were removed from oldScreensById.
    let removedScreens = Array(oldScreensById.values.map { Screen(delegate: $0) })

    let event = ScreenLayoutChangedEvent(
        external: false,
        addedScreens: addedScreens,
        removedScreens: removedScreens,
        changedScreens: changedScreens,
        unchangedScreens: unchangedScreens
    )

    return event
}

private let kNSScreenNumber = "NSScreenNumber"

final class OSXScreenDelegate<NSScreenT: NSScreenType>: ScreenDelegate {
    fileprivate let nsScreen: NSScreenT

    // This ID is guaranteed to stay the same for any given display. NSScreen equality checks can
    // fail if the display switches graphics cards.
    fileprivate let directDisplayID: CGDirectDisplayID

    let queue: DispatchQueue

    init(nsScreen: NSScreenT, queue: DispatchQueue) {
        self.nsScreen = nsScreen
        frame = nsScreen.frame
        directDisplayID = numberForScreen(nsScreen)
        self.queue = queue
    }

    func equalTo(_ other: ScreenDelegate) -> Bool {
        guard let other = other as? OSXScreenDelegate else {
            return false
        }
        return other.directDisplayID == directDisplayID
    }

    lazy var displayName: String = { self.nsScreen.displayName }()

    var debugDescription: String {
        return "\"\(displayName)\" \(frame)"
    }

    // The frame won't change during the delegate's lifetime because it gets recreated every time
    // there is a screen configuration change.
    let frame: CGRect

    var applicationFrame: CGRect { return nsScreen.visibleFrame }
}

private func numberForScreen<NSScreenT: NSScreenType>(_ nsScreen: NSScreenT) -> CGDirectDisplayID {
    // Get the direct display ID. This is documented to always exist.
    let screenNumber = nsScreen.deviceDescription[NSDeviceDescriptionKey(kNSScreenNumber)]!
    return CGDirectDisplayID((screenNumber as! NSNumber).intValue)
}

/// Returns the IODisplay info dictionary for the given displayID.
///
/// -Returns: The info dictionary for the first screen with the same vendor and model number as the
///           specified screen.
private func infoForCGDisplay(_ displayID: CGDirectDisplayID, options: Int) -> [AnyHashable: Any]? {
    var iter: io_iterator_t = 0

    // Initialize iterator.
    let services = IOServiceMatching("IODisplayConnect")
    let err = IOServiceGetMatchingServices(kIOMasterPortDefault, services, &iter)
    guard err == KERN_SUCCESS else {
        log.warn("Could not find services for IODisplayConnect, error code \(err)")
        return nil
    }

    // Loop through all screens, looking for a vendor and model ID match.
    var service = IOIteratorNext(iter)
    while service != 0 {
        let info = IODisplayCreateInfoDictionary(service, IOOptionBits(options)).takeRetainedValue()
                   as Dictionary as [AnyHashable: Any]

        guard let cfVendorID = info[kDisplayVendorID] as! CFNumber?,
            let cfProductID = info[kDisplayProductID] as! CFNumber? else {
            log.warn("Missing vendor or product ID encountered when looping through screens")
            continue
        }

        var vendorID: CFIndex = 0, productID: CFIndex = 0
        guard CFNumberGetValue(cfVendorID, .cfIndexType, &vendorID) &&
            CFNumberGetValue(cfProductID, .cfIndexType, &productID) else {
            log.warn("Unexpected failure unwrapping vendor or product ID while looping through "
                   + "screens")
            continue
        }

        if UInt32(vendorID) == CGDisplayVendorNumber(displayID) &&
            UInt32(productID) == CGDisplayModelNumber(displayID) {
            return info
        }

        service = IOIteratorNext(iter)
    }

    return nil
}
