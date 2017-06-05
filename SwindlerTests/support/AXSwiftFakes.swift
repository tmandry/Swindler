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
    guard let value = attrs[attribute] else  {
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
    let role = attrs[.Role] ?? "UIElement"
    return "\(role) (id \(id))"
  }
}
func ==(lhs: TestUIElement, rhs: TestUIElement) -> Bool {
  return lhs.id == rhs.id
}

class TestApplicationElementBase: TestUIElement {
  typealias UIElementType = TestUIElement
  var toElement: TestUIElement { return self }

  override init() {
    super.init()
    processID = Int32(id)
    attrs[.Role]      = AXSwift.Role.Application.rawValue
    attrs[.Windows]   = Array<TestUIElement>()
    attrs[.Frontmost] = false
    attrs[.Hidden]    = false
  }

  override func setAttribute(_ attribute: Attribute, value: Any) throws {
    // Synchronize .MainWindow with .Main on the window.
    if attribute == .MainWindow {
      if let oldWindowElement = attrs[.MainWindow] as! TestWindowElement? {
        oldWindowElement.attrs[.Main] = false
      }
      let newWindowElement = value as! TestWindowElement
      newWindowElement.attrs[.Main] = true
    }

    try super.setAttribute(attribute, value: value)
  }

  internal var windows: [TestUIElement] {
    get { return attrs[.Windows]! as! [TestUIElement] }
    set { attrs[.Windows] = newValue }
  }
}
final class TestApplicationElement: TestApplicationElementBase, ApplicationElementType {
  static var allApps: [TestApplicationElement] = []
  static func all() -> [TestApplicationElement] { return TestApplicationElement.allApps }
}

class TestWindowElement: TestUIElement {
  var app: TestApplicationElementBase
  init(forApp app: TestApplicationElementBase) {
    self.app = app
    super.init()
    processID          = app.processID
    attrs[.Role]       = AXSwift.Role.Window.rawValue
    attrs[.Position]   = CGPoint(x: 0, y: 0)
    attrs[.Size]       = CGSize(width: 0, height: 0)
    attrs[.Title]      = "Window \(id)"
    attrs[.Minimized]  = false
    attrs[.Main]       = true
    attrs[.Focused]    = true
    attrs[.FullScreen] = false
  }

  override func setAttribute(_ attribute: Attribute, value: Any) throws {
    // Synchronize .Main with .MainWindow on the application.
    if attribute == .Main {
      // Setting .Main to false does nothing.
      guard value as! Bool == true else { return }

      app.attrs[.MainWindow] = self
    }

    try super.setAttribute(attribute, value: value)
  }
}

class TestObserver: ObserverType {
  typealias UIElement = TestUIElement
  typealias Context = TestObserver
  //typealias Callback = (Context, TestUIElement, AXNotification) -> ()

  required init(processID: pid_t, callback: @escaping Callback) throws { }
  init() { }

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

  func removeNotification(_ notification: AXNotification, forElement element: TestUIElement) throws {
    lock.lock()
    defer { lock.unlock() }

    if let watchedNotifications = watchedElements[element] {
      watchedElements[element] = watchedNotifications.filter{ $0 != notification }
    }
  }

  func emit(_ notification: AXNotification, forElement element: TestUIElement) {
    switch notification {
    // These notifications usually happen on a window element, but are observed on the application element.
    case .WindowCreated, .MainWindowChanged, .FocusedWindowChanged:
      if let window = element as? TestWindowElement {
        doEmit(notification, watchedElement: window.app, passedElement: element)
      } else {
        doEmit(notification, watchedElement: element, passedElement: element)
      }
    default:
      doEmit(notification, watchedElement: element, passedElement: element)
    }
  }

  func doEmit(_ notification: AXNotification, watchedElement: TestUIElement, passedElement: TestUIElement) {
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
  static var onNotification: AXNotification? = nil
  static var handler: Optional<(AdversaryObserver) -> ()> = nil

  /// Call this in beforeEach for any tests that use this class.
  static func reset() {
    onNotification = nil
    handler = nil
  }

  /// Defines code that runs on the main thread before returning from addNotification.
  static func onAddNotification(_ notification: AXNotification, handler: @escaping (AdversaryObserver) -> ()) {
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
  static func all() -> [AdversaryApplicationElement] { return AdversaryApplicationElement.allApps }

  var onRead: Optional<(AdversaryApplicationElement) -> ()> = nil
  var watchAttribute: Attribute? = nil
  var alreadyCalled = false
  var onMainThread = true

  /// Defines code that runs on the main thread before returning the value of the attribute.
  func onFirstAttributeRead(_ attribute: Attribute, onMainThread: Bool = true, handler: @escaping (AdversaryApplicationElement) -> ()) {
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
  override func getMultipleAttributes(_ attributes: [AXSwift.Attribute]) throws -> [Attribute : Any] {
    let result: [Attribute : Any] = try super.getMultipleAttributes(attributes)
    if let watchAttribute = watchAttribute, attributes.contains(watchAttribute) {
      handleAttributeRead()
    }
    return result
  }
}

/// Allows defining adversarial actions when an attribute is read.
class AdversaryWindowElement: TestWindowElement {
  var onRead: Optional<() -> ()> = nil
  var watchAttribute: Attribute? = nil
  var alreadyCalled = false

  /// Defines code that runs on the main thread before returning the value of the attribute.
  func onAttributeFirstRead(_ attribute: Attribute, handler: @escaping () -> ()) {
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
  override func getMultipleAttributes(_ attributes: [AXSwift.Attribute]) throws -> [Attribute : Any] {
    let result: [Attribute : Any] = try super.getMultipleAttributes(attributes)
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
func performOnMainThread(_ action: () -> ()) {
  if Thread.current.isMainThread {
    action()
  } else {
    DispatchQueue.main.sync {
      action()
    }
  }
}
