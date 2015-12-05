@testable import Swindler
import AXSwift

class TestUIElement: UIElementType, Hashable {
  static var globalMessagingTimeout: Float = 0

  static var elementCount: Int = 0

  var id: Int = elementCount++
  var processID: pid_t = 0
  var attrs: [Attribute: Any] = [:]

  var throwInvalid: Bool = false

  init() { }
  var hashValue: Int { return id }

  func pid() throws -> pid_t { return processID }
  func attribute<T>(attribute: Attribute) throws -> T? {
    if throwInvalid { throw AXSwift.Error.InvalidUIElement }
    if let value = attrs[attribute] {
      return (value as! T)
    }
    return nil
  }
  func arrayAttribute<T>(attribute: Attribute) throws -> [T]? {
    if throwInvalid { throw AXSwift.Error.InvalidUIElement }
    guard let value = attrs[attribute] else  {
      return nil
    }
    return (value as! [T])
  }
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any] {
    if throwInvalid { throw AXSwift.Error.InvalidUIElement }
    var result: [Attribute: Any] = [:]
    for attribute in attributes {
      result[attribute] = attrs[attribute]
    }
    return result
  }
  func setAttribute(attribute: Attribute, value: Any) throws {
    if throwInvalid { throw AXSwift.Error.InvalidUIElement }
    attrs[attribute] = value
  }

  var inspect: String {
    let role = attrs[.Role] ?? "UIElement"
    return "\(role) (id \(id)"
  }
}
func ==(lhs: TestUIElement, rhs: TestUIElement) -> Bool {
  return lhs === rhs
}

class TestApplicationElementBase: TestUIElement {
  typealias UIElementType = TestUIElement
  var toElement: TestUIElement { return self }

  override init() {
    super.init()
    processID = Int32(id)
    attrs[.Role]      = AXSwift.Role.Application
    attrs[.Windows]   = Array<TestUIElement>()
    attrs[.Frontmost] = false
  }

  var windows: [TestUIElement] {
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
    processID         = app.processID
    attrs[.Role]      = AXSwift.Role.Window
    attrs[.Position]  = CGPoint(x: 0, y: 0)
    attrs[.Size]      = CGSize(width: 0, height: 0)
    attrs[.Title]     = "Window \(id)"
    attrs[.Minimized] = false
    attrs[.Main]      = true
  }
}

class TestObserver: ObserverType {
  typealias Callback = (observer: TestObserver, element: TestUIElement, notification: AXSwift.Notification) -> ()

  required init(processID: pid_t, callback: Callback) throws { }
  init() { }

  func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {}
  func processPendingNotifications() { }
}

// A more elaborate TestObserver that actually tracks which elements and notifications are being
// observed and supports emitting notifications.
class FakeObserver: TestObserver {
  static var observers: [FakeObserver] = []
  var callback: Callback!

  required init(processID: pid_t, callback: Callback) throws {
    self.callback = callback
    try super.init(processID: processID, callback: callback)
    FakeObserver.observers.append(self)
  }

  var watchedElements: [TestUIElement: [AXSwift.Notification]] = [:]

  override func addNotification(notification: AXSwift.Notification, forElement element: TestUIElement) throws {
    if watchedElements[element] == nil {
      watchedElements[element] = []
    }
    watchedElements[element]!.append(notification)
  }

  func emit(notification: AXSwift.Notification, forElement window: TestWindowElement) {
    switch notification {
    case .WindowCreated, .MainWindowChanged:
      doEmit(notification, watchedElement: window.app, passedElement: window)
    default:
      doEmit(notification, watchedElement: window, passedElement: window)
    }
  }

  private func doEmit(notification: AXSwift.Notification, watchedElement: TestUIElement, passedElement: TestUIElement) {
    let watched = watchedElements[watchedElement] ?? []
    if watched.contains(notification) {
      callback(observer: self, element: passedElement, notification: notification)
    }
  }
}
