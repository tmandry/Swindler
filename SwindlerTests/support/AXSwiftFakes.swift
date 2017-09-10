@testable import Swindler
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

class TestWindowElement: TestUIElement {
    var app: TestApplicationElementBase
    init(forApp app: TestApplicationElementBase) {
        self.app = app
        super.init()
        processID = app.processID
        attrs[.role] = AXSwift.Role.window.rawValue
        attrs[.position] = CGPoint(x: 0, y: 0)
        attrs[.size] = CGSize(width: 0, height: 0)
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

            app.attrs[.mainWindow] = self
        }

        try super.setAttribute(attribute, value: value)
    }
}

class TestObserver: ObserverType {
    typealias UIElement = TestUIElement
    typealias Context = TestObserver
    //typealias Callback = (Context, TestUIElement, AXNotification) -> ()

    required init(processID: pid_t, callback: @escaping Callback) throws {}
    init() {}

    func addNotification(_ notification: AXNotification, forElement: TestUIElement) throws {}
    func removeNotification(_ notification: AXNotification, forElement: TestUIElement) throws {}
}

// A more elaborate TestObserver that actually tracks which elements and notifications are being
// observed and supports emitting notifications.
/*protocol FakeObserverType: ObserverType {
  typealias UIElement = TestUIElement
  static var observers: [Self] { get set }
  var watchedElements: [TestUIElement: [AXNotification]] { get set }
  var callback: Callback! { get set }
  var lock: NSLock { get set }
}
extension FakeObserverType where Context == Self, UIElement == TestUIElement {*/
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
            callback(self, passedElement, notification)
        }
    }
}
/*
final class FakeObserver: FakeObserverType {
  typealias Context = FakeObserver
  typealias UIElement = TestUIElement
  static var observers: [Context] = []
  var callback: Callback!
  var lock: NSLock = NSLock()
  var watchedElements: [TestUIElement: [AXNotification]] = [:]
}
*/
// MARK: - Adversaries

/// Allows defining adversarial actions when a property is observed.
final class AdversaryObserver: FakeObserver {
    static var onNotification: AXNotification?
    static var handler: Optional < (AdversaryObserver) -> Void> = nil

    /// Call this in beforeEach for any tests that use this class.
    static func reset() {
        onNotification = nil
        handler = nil
    }

    /// Defines code that runs on the main thread before returning from addNotification.
    static func onAddNotification(_ notification: AXNotification,
                                  handler: @escaping (AdversaryObserver) -> Void) {
        onNotification = notification
        self.handler = handler
    }

    override func addNotification(
        _ notification: AXNotification, forElement element: TestUIElement) throws {
        try super.addNotification(notification, forElement: element)
        if notification == AdversaryObserver.onNotification {
            performOnMainThread { AdversaryObserver.handler!(self) }
        }
    }
}

/// Allows defining adversarial actions when an attribute is read.
final class AdversaryApplicationElement: TestApplicationElementBase, ApplicationElementType {
    static var allApps: [AdversaryApplicationElement] = []
    static func all() -> [AdversaryApplicationElement] {
      return AdversaryApplicationElement.allApps
    }

    var onRead: Optional < (AdversaryApplicationElement) -> Void> = nil
    var watchAttribute: Attribute?
    var alreadyCalled = false
    var onMainThread = true

    init() { super.init(processID: 0) }
    init?(forProcessID processID: pid_t) { return nil }

    /// Defines code that runs on the main thread before returning the value of the attribute.
    func onFirstAttributeRead(_ attribute: Attribute,
                              onMainThread: Bool = true,
                              handler: @escaping (AdversaryApplicationElement) -> Void) {
        watchAttribute = attribute
        onRead = handler
        alreadyCalled = false
        self.onMainThread = onMainThread
    }

    var lock = NSLock()
    fileprivate func handleAttributeRead() {
        lock.lock()
        defer { lock.unlock() }

        if !self.alreadyCalled {
            if self.onMainThread {
                performOnMainThread { self.onRead?(self) }
            } else {
                self.onRead?(self)
            }

            self.alreadyCalled = true
        }
    }

    override func attribute<T>(_ attribute: Attribute) throws -> T? {
        let result: T? = try super.attribute(attribute)
        if attribute == watchAttribute {
            handleAttributeRead()
        }
        return result
    }
    override func arrayAttribute<T>(_ attribute: Attribute) throws -> [T]? {
        let result: [T]? = try super.arrayAttribute(attribute)
        if attribute == watchAttribute {
            handleAttributeRead()
        }
        return result
    }
    override func getMultipleAttributes(_ attributes: [AXSwift.Attribute])
        throws -> [Attribute: Any] {
        let result: [Attribute: Any] = try super.getMultipleAttributes(attributes)
        if let watchAttribute = watchAttribute, attributes.contains(watchAttribute) {
            handleAttributeRead()
        }
        return result
    }
}

/// Allows defining adversarial actions when an attribute is read.
class AdversaryWindowElement: TestWindowElement {
    var onRead: Optional < () -> Void> = nil
    var watchAttribute: Attribute?
    var alreadyCalled = false

    /// Defines code that runs on the main thread before returning the value of the attribute.
    func onAttributeFirstRead(_ attribute: Attribute, handler: @escaping () -> Void) {
        watchAttribute = attribute
        onRead = handler
        alreadyCalled = false
    }

    override func attribute<T>(_ attribute: Attribute) throws -> T? {
        let result: T? = try super.attribute(attribute)
        if attribute == watchAttribute {
            performOnMainThread {
                if !self.alreadyCalled {
                    self.onRead?()
                    self.alreadyCalled = true
                }
            }
        }
        return result
    }
    override func getMultipleAttributes(_ attributes: [AXSwift.Attribute])
        throws -> [Attribute: Any] {
        let result: [Attribute: Any] = try super.getMultipleAttributes(attributes)
        if let watchAttribute = watchAttribute, attributes.contains(watchAttribute) {
            performOnMainThread {
                if !self.alreadyCalled {
                    self.onRead?()
                    self.alreadyCalled = true
                }
            }
        }
        return result
    }
}

/// Performs the given action on the main thread, synchronously, regardless of the current thread.
func performOnMainThread(_ action: () -> Void) {
    if Thread.current.isMainThread {
        action()
    } else {
        DispatchQueue.main.sync {
            action()
        }
    }
}
