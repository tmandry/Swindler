@testable import Swindler
import AXSwift

class TestObserver: ObserverType {
    typealias UIElement = TestUIElement
    typealias Context = TestObserver
    //typealias Callback = (Context, TestUIElement, AXNotification) -> ()

    required init(processID: pid_t, callback: @escaping Callback) throws {}
    init() {}

    func addNotification(_ notification: AXNotification, forElement: TestUIElement) throws {}
    func removeNotification(_ notification: AXNotification, forElement: TestUIElement) throws {}
}

// MARK: - Adversaries

/// Allows defining adversarial actions when a property is observed.
final class AdversaryObserver: FakeObserver {
    static var onNotification: AXNotification?
    static var handler: Optional<(AdversaryObserver) -> Void> = nil

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
    var onRead: Optional<() -> Void> = nil
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
