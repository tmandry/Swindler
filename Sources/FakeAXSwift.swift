/// Fake implementations of AXSwift functionality.
///
/// This gets used both in the public testing harness and in Swindler's own tests.

// TODO: Rename TestXyz classes to FakeXyz.

import AXSwift

class TestUIElement: UIElementType, Hashable {
    static var globalMessagingTimeout: Float = 0

    static var elementCount: Int = 0

    var id: Int
    var processID: pid_t = 0
    var attrs: [Attribute: Any] = [:]

    var throwInvalid: Bool = false

    init() {
        TestUIElement.elementCount += 1
        id = TestUIElement.elementCount
    }
    var hashValue: Int { return id }

    func pid() throws -> pid_t { return processID }
    func attribute<T>(_ attribute: Attribute) throws -> T? {
        if throwInvalid { throw AXSwift.AXError.invalidUIElement }
        if let value = attrs[attribute] {
            return (value as! T)
        }
        return nil
    }
    func arrayAttribute<T>(_ attribute: Attribute) throws -> [T]? {
        if throwInvalid { throw AXSwift.AXError.invalidUIElement }
        guard let value = attrs[attribute] else {
            return nil
        }
        return (value as! [T])
    }
    func getMultipleAttributes(_ attributes: [AXSwift.Attribute]) throws -> [Attribute: Any] {
        if throwInvalid { throw AXSwift.AXError.invalidUIElement }
        var result: [Attribute: Any] = [:]
        for attribute in attributes {
            result[attribute] = attrs[attribute]
        }
        return result
    }
    func setAttribute(_ attribute: Attribute, value: Any) throws {
        if throwInvalid { throw AXSwift.AXError.invalidUIElement }
        attrs[attribute] = value
    }

    func addObserver(_: FakeObserver) { }

    var inspect: String {
        let role = attrs[.role] ?? "UIElement"
        return "\(role) (id \(id))"
    }
}
func ==(lhs: TestUIElement, rhs: TestUIElement) -> Bool {
    return lhs.id == rhs.id
}

class TestApplicationElementBase: TestUIElement {
    typealias UIElementType = TestUIElement
    var toElement: TestUIElement { return self }

    init(processID: pid_t?) {
        super.init()
        self.processID = processID ?? Int32(id)
        attrs[.role] = AXSwift.Role.application.rawValue
        attrs[.windows] = Array<TestUIElement>()
        attrs[.frontmost] = false
        attrs[.hidden] = false
    }

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        // Synchronize .mainWindow with .main on the window.
        if attribute == .mainWindow {
            if let oldWindowElement = attrs[.mainWindow] as! TestWindowElement? {
                oldWindowElement.attrs[.main] = false
            }
            let newWindowElement = value as! TestWindowElement
            newWindowElement.attrs[.main] = true
        }

        try super.setAttribute(attribute, value: value)
    }

    internal var windows: [TestUIElement] {
        get { return attrs[.windows]! as! [TestUIElement] }
        set { attrs[.windows] = newValue }
    }
}

// ApplicationElementType requires static func all() -> [Self], which must be handled in each
// (final) leaf class.
final class TestApplicationElement: TestApplicationElementBase, ApplicationElementType {
    init() { super.init(processID: nil) }
    init?(forProcessID processID: pid_t) {
        guard let _ = TestApplicationElement.all().first(where: {$0.processID == processID}) else {
            return nil
        }
        super.init(processID: processID)
    }
    static var allApps: [TestApplicationElement] = []
    static func all() -> [TestApplicationElement] { return TestApplicationElement.allApps }
}

final class EmittingTestApplicationElement: TestApplicationElementBase, ApplicationElementType {
    init() {
        observers = []
        super.init(processID: nil)
    }
    init?(forProcessID processID: pid_t) {
        observers = []
        let apps = EmittingTestApplicationElement.all()
        guard let _ = apps.first(where: {$0.processID == processID}) else {
            return nil
        }
        super.init(processID: processID)
    }
    static var allApps: [EmittingTestApplicationElement] = []
    static func all() -> [EmittingTestApplicationElement] {
        return EmittingTestApplicationElement.allApps
    }

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        try super.setAttribute(attribute, value: value)
        let notification = { () -> AXNotification? in
            switch attribute {
            case .mainWindow:
                return .mainWindowChanged
            case .focusedWindow:
                return .focusedWindowChanged
            case .hidden:
                return (value as? Bool == true) ? .applicationHidden : .applicationShown
            default:
                return nil
            }
        }()
        if let notification = notification {
            for observer in observers {
                observer.unbox?.emit(notification, forElement: self)
            }
        }
    }

    private var observers: [WeakBox<FakeObserver>]

    override func addObserver(_ observer: FakeObserver) {
        observers.append(WeakBox(observer))
    }

    // Useful hack to store companion objects (like FakeWindow).
    weak var companion: AnyObject?
}

class TestWindowElement: TestUIElement {
    var app: TestApplicationElementBase
    init(forApp app: TestApplicationElementBase) {
        self.app = app
        super.init()
        processID = app.processID
        attrs[.role] = AXSwift.Role.window.rawValue
        attrs[.position] = CGPoint(x: 0, y: 0)
        attrs[.size] = CGSize(width: 100, height: 100)
        attrs[.title] = "Window \(id)"
        attrs[.minimized] = false
        attrs[.main] = true
        attrs[.focused] = true
        attrs[.fullScreen] = false
    }

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        // Synchronize .main with .mainWindow on the application.
        if attribute == .main {
            // Setting .main to false does nothing.
            guard value as! Bool == true else { return }
            try app.setAttribute(.mainWindow, value: self)
        }

        try super.setAttribute(attribute, value: value)
    }
}

extension TestWindowElement: CustomDebugStringConvertible {
    var debugDescription: String {
        let title = self.attrs[.title].map{"\"\($0)\""}
        return "TestWindowElement(\(title ?? "<none>"))"
    }
}

class EmittingTestWindowElement: TestWindowElement {
    override init(forApp app: TestApplicationElementBase) {
        observers = []
        super.init(forApp: app)
    }

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        try super.setAttribute(attribute, value: value)
        let notification = { () -> AXNotification? in
            switch attribute {
            case .position:   return .moved
            case .size:       return .resized
            case .fullScreen: return .resized
            case .title:      return .titleChanged
            case .minimized:
                return (value as? Bool == true) ? .windowDeminiaturized : .windowMiniaturized
            default:
                return nil
            }
        }()
        if let notification = notification {
            for observer in observers {
                observer.unbox?.emit(notification, forElement: self)
            }
        }
    }

    private var observers: [WeakBox<FakeObserver>]

    override func addObserver(_ observer: FakeObserver) {
        observers.append(WeakBox(observer))
    }

    // Useful hack to store companion objects (like FakeWindow).
    weak var companion: AnyObject?
}

class FakeObserver: ObserverType {
    typealias Context = FakeObserver
    typealias UIElement = TestUIElement
    static var observers: [Context] = []
    var callback: Callback!
    var lock: NSLock = NSLock()
    var watchedElements: [TestUIElement: [AXNotification]] = [:]

    //static var observers: [FakeObserverBase] = []

    required init(processID: pid_t, callback: @escaping Callback) throws {
        self.callback = callback
        //try ObserverType.init(processID: processID, callback: callback)
        FakeObserver.observers.append(self)
    }

    func addNotification(_ notification: AXNotification, forElement element: TestUIElement) throws {
        lock.lock()
        defer { lock.unlock() }

        if watchedElements[element] == nil {
            watchedElements[element] = []
            element.addObserver(self)
        }
        watchedElements[element]!.append(notification)
    }

    func removeNotification(_ notification: AXNotification,
                            forElement element: TestUIElement) throws {
        lock.lock()
        defer { lock.unlock() }

        if let watchedNotifications = watchedElements[element] {
            watchedElements[element] = watchedNotifications.filter { $0 != notification }
        }
    }

    func emit(_ notification: AXNotification, forElement element: TestUIElement) {
        // These notifications usually happen on a window element, but are observed on the
        // application element.
        switch notification {
        case .windowCreated, .mainWindowChanged, .focusedWindowChanged:
            if let window = element as? TestWindowElement {
                doEmit(notification, watchedElement: window.app, passedElement: element)
            } else {
                doEmit(notification, watchedElement: element, passedElement: element)
            }
        default:
            doEmit(notification, watchedElement: element, passedElement: element)
        }
    }

    func doEmit(_ notification: AXNotification,
                watchedElement: TestUIElement,
                passedElement: TestUIElement) {
        let watched = watchedElements[watchedElement] ?? []
        if watched.contains(notification) {
            performOnMainThread {
                callback(self, passedElement, notification)
            }
        }
    }
}

// This component is not actually part of AXSwift.
class FakeApplicationObserver: ApplicationObserverType {
    private var frontmost_: pid_t?
    var frontmostApplicationPID: pid_t? { return frontmost_ }

    private var frontmostHandlers: [() -> Void] = []
    func onFrontmostApplicationChanged(_ handler: @escaping () -> Void) {
        frontmostHandlers.append(handler)
    }

    private var launchHandlers: [(pid_t) -> Void] = []
    func onApplicationLaunched(_ handler: @escaping (pid_t) -> Void) {
        launchHandlers.append(handler)
    }

    private var terminateHandlers: [(pid_t) -> Void] = []
    func onApplicationTerminated(_ handler: @escaping (pid_t) -> Void) {
        terminateHandlers.append(handler)
    }

    func makeApplicationFrontmost(_ pid: pid_t) throws {
        setFrontmost(pid)
    }

    fileprivate func setFrontmost(_ pid: pid_t?) {
        frontmost_ = pid
        frontmostHandlers.forEach { $0() }
    }
    fileprivate func launch(_ pid: pid_t) {
        launchHandlers.forEach { $0(pid) }
    }
    fileprivate func terminate(_ pid: pid_t) {
        terminateHandlers.forEach { $0(pid) }
    }
}

final private class WeakBox<A: AnyObject> {
    weak var unbox: A?
    init(_ value: A) {
        unbox = value
    }
}

/// Performs the given action on the main thread, synchronously, regardless of the current thread.
private func performOnMainThread(_ action: () -> Void) {
    if Thread.current.isMainThread {
        action()
    } else {
        DispatchQueue.main.sync {
            action()
        }
    }
}
