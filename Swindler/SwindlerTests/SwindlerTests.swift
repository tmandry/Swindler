import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

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

class TestPropertyDelegate<T: Equatable>: PropertyDelegate {
  var systemValue: T?

  init(value: T?) {
    systemValue = value
  }
  func initialize() -> Promise<T?> {
    return Promise(systemValue)
  }
  func readValue() throws -> T? {
    return systemValue
  }
  func writeValue(newValue: T) throws {
    systemValue = newValue
  }
}


class OSXDriverSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplicationElement.allApps = [] }
    beforeEach { FakeObserver.observers = [] }

    context("during initialization") {

      it("observes all applications") {
        class MyTestObserver: TestObserver {
          static var numObservers: Int = 0
          required init(processID: pid_t, callback: Callback) throws {
            MyTestObserver.numObservers++
            try super.init(processID: processID, callback: callback)
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement(), TestApplicationElement()]
        let _ = OSXStateDelegate<TestUIElement, TestApplicationElement, MyTestObserver>()

        expect(MyTestObserver.numObservers).to(equal(2), description: "should be 2 observers")
      }

      it("handles applications that cannot be watched") {
        class MyTestObserver: TestObserver {
          override private func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {
            throw AXSwift.Error.CannotComplete
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement()]
        let _ = OSXStateDelegate<TestUIElement, TestApplicationElement, MyTestObserver>()
        // test that it doesn't crash
      }

    }

    context("after initialization") {
      // Set up a state with a single application containing a single window.
      var appElement: TestApplicationElement!
      var windowElement: TestWindowElement!
      var observer: FakeObserver!
      var state: State!
      var window: Window!
      var app: Swindler.Application!
      beforeEach {
        appElement = TestApplicationElement()
        windowElement = TestWindowElement(forApp: appElement)
        windowElement.attrs[.Position] = CGPoint(x: 5, y: 5)
        appElement.attrs[.Windows] = [windowElement as TestUIElement]
        appElement.attrs[.MainWindow] = windowElement
        TestApplicationElement.allApps = [appElement]

        state = State(delegate: OSXStateDelegate<TestUIElement, TestApplicationElement, FakeObserver>())
        observer = FakeObserver.observers.first!
        observer.emit(.WindowCreated, forElement: windowElement)
        expect(state.visibleWindows.count).toEventually(equal(1))
        app = state.runningApplications.first!
        window = state.visibleWindows.first!
      }
      afterEach {
        TestApplicationElement.allApps = []
      }

      it("initializes mainWindow") {
        waitUntil { done in
          app.mainWindow.initialized.then {
            done()
          }
        }
        expect(app.mainWindow.value).to(equal(window))
      }

      context("when a window is created") {
        beforeEach {
          expect(state.visibleWindows.count).toEventually(equal(1))
        }

        it("watches for events on the window") {
          expect(observer.watchedElements[windowElement]).toNot(beNil())
        }

        it("adds the window to visibleWindows") {
          expect(state.visibleWindows.count).to(equal(1))
        }

        it("is marked as valid") {
          expect(state.visibleWindows.first!.valid).to(beTrue())
        }

        it("reads the window's properties into the state") {
          expect(state.visibleWindows.first!.pos.value).to(equal(CGPoint(x: 5, y: 5)))
        }

        it("emits WindowCreatedEvent") {
          var callbacks = 0
          state.on { (event: WindowCreatedEvent) in
            callbacks++
          }

          let window = TestWindowElement(forApp: appElement)
          observer.emit(.WindowCreated, forElement: window)
          expect(state.visibleWindows.count).toEventually(equal(2))
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

      }

      context("when a window is destroyed") {

        it("is marked as invalid") {
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(window.valid).to(beFalse())
        }

        it("emits WindowDestroyedEvent") {
          var callbacks = 0
          state.on { (event: WindowDestroyedEvent) in
            callbacks++
          }
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

        it("is marked as invalid in the WindowDestroyedEvent") {
          state.on { (event: WindowDestroyedEvent) in
            expect(event.window.valid).to(beFalse())
          }
          observer.emit(.UIElementDestroyed, forElement: windowElement)
        }

        it("marks the WindowDestroyedEvent as external") {
          state.on { (event: WindowDestroyedEvent) in
            expect(event.external).to(beTrue())
          }
          observer.emit(.UIElementDestroyed, forElement: windowElement)
        }

      }

      context("when a window property changes") {
        // See `PropertySpec` for property unit tests.

        it("emits a ChangedEvent") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
        }

        it("marks the event as external") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.external).to(beTrue())
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          return window.pos.refresh()
        }

        it("calls multiple event handlers") {
          var callbacks1 = 0
          var callbacks2 = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks1++
          }
          state.on { (event: WindowPosChangedEvent) in
            callbacks2++
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks1).toEventually(equal(1), description: "callback1 should be called once")
          expect(callbacks2).toEventually(equal(1), description: "callback2 should be called once")
        }

      }

      context("when the main window of an application changes") {
        var newWindowElement: TestWindowElement!
        var newWindow: Window!
        beforeEach {
          waitUntil { done in
            app.mainWindow.initialized.then {
              done()
            }
          }

          newWindowElement = TestWindowElement(forApp: appElement)
          newWindowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          newWindow = state.visibleWindows.last!
          observer.emit(.WindowCreated, forElement: newWindowElement)
        }

        it("emits an ApplicationMainWindowChangedEvent") {
          var callbacks = 0
          state.on { (event: ApplicationMainWindowChangedEvent) in
            callbacks++
          }
          appElement.attrs[.MainWindow] = newWindowElement
          observer.emit(.MainWindowChanged, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
        }

        it("sets the mainWindow property to the new main window") {
          appElement.attrs[.MainWindow] = newWindowElement
          observer.emit(.MainWindowChanged, forElement: windowElement)
          expect(app.mainWindow.value).toEventually(equal(newWindow))
        }

      }
    }

  }
}

class TestNotifier: EventNotifier {
  var events: [EventType] = []
  func notify<Event: EventType>(event: Event) {
    events.append(event)
  }
}

class OSXWindowSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplicationElement.allApps = [] }

    describe("initialize") {
      context("when called with a window that is missing attributes") {
        it("returns an error") { () -> Promise<Void> in
          let windowElement = TestWindowElement(forApp: TestApplicationElement())
          windowElement.attrs.removeValueForKey(.Position)

          let promise = OSXWindowDelegate<TestUIElement, TestApplicationElement, TestObserver>.initialize(
              notifier: TestNotifier(), axElement: windowElement, observer: TestObserver())
          let expectedError = OSXDriverError.MissingAttribute(attribute: .Position, onElement: windowElement)
          return expectToFail(promise, with: expectedError)
        }
      }
    }

  }
}

class TestWindowPropertyNotifier: PropertyNotifier {
  typealias Object = Window

  // We must make our own struct because we don't have a window.
  struct Event {
    var type: Any.Type
    var external: Bool
    var oldValue: Any
    var newValue: Any
  }
  var events: [Event] = []
  var stillValid = true

  func notify<EventT: PropertyEventTypeInternal where EventT.Object == Window>(event: EventT.Type, external: Bool, oldValue: EventT.PropertyType, newValue: EventT.PropertyType) {
    events.append(Event(type: event, external: external, oldValue: oldValue, newValue: newValue))
  }
  func notifyInvalid() {
    stillValid = false
  }
}

class PropertySpec: QuickSpec {
  override func spec() {

    // Set up a position property on a test AX window.
    var property: WriteableProperty<OfType<CGPoint>>!
    var windowElement: TestWindowElement!
    var notifier: TestWindowPropertyNotifier!
    func setUpWithAttributes(attrs: [AXSwift.Attribute: Any]) {
      windowElement = TestWindowElement(forApp: TestApplicationElement())
      windowElement.attrs = attrs
      let initPromise = Promise<[AXSwift.Attribute: Any]>(attrs)
      notifier = TestWindowPropertyNotifier()
      let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(windowElement, .Position, initPromise)
      property = WriteableProperty(delegate, withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: notifier)
    }
    func finishPropertyInit() {
      waitUntil { done in
        property.initialized.then {
          done()
        }
      }
    }

    let firstPoint  = CGPoint(x: 5, y: 5)
    let secondPoint = CGPoint(x: 100, y: 100)

    beforeEach {
      setUpWithAttributes([.Position: firstPoint])
      finishPropertyInit()
    }

    describe("initialization") {
      context("when a non-optional attribute is missing") {

        it("reports an error") { () -> Promise<Void> in
          setUpWithAttributes([:])
          let expectedError = PropertyError.InvalidObject(cause: PropertyError.MissingValue)
          return expectToFail(property.initialized, with: expectedError)
        }

        it("marks the object as invalid", failOnError: false) { () -> Promise<Void> in
          setUpWithAttributes([:])
          return property.initialized.always {
            expect(notifier.stillValid).to(beFalse())
          }
        }

      }

      context("when an optional attribute is missing") {

        var optProperty: WriteableProperty<OfOptionalType<CGPoint>>!
        beforeEach {
          let initPromise = Promise<[AXSwift.Attribute: Any]>([:])
          let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(windowElement, .Position, initPromise)
          optProperty = WriteableProperty(delegate, notifier: notifier)
        }

        it("reports no error") { () -> Promise<Void> in
          return optProperty.initialized
        }

        it("does not mark the object as invalid") { () -> Promise<Void> in
          return optProperty.initialized.then {
            expect(notifier.stillValid).to(beTrue())
          }
        }

      }
    }

    describe("refresh") {
      context("when the attribute has changed") {
        beforeEach {
          windowElement.attrs[.Position] = secondPoint
        }

        it("resolves to the new value") {
          return property.refresh().then { newValue in
            expect(newValue).to(equal(secondPoint))
          }
        }

        it("emits a ChangedEvent of the correct type") {
          return property.refresh().then { _ -> () in
            expect(notifier.events.count).to(equal(1))
            if let event = notifier.events.first {
              expect(event.type == WindowPosChangedEvent.self).to(beTrue())
            }
          }
        }

        it("includes the correct oldVal and newVal in the event") {
          return property.refresh().then { _ -> () in
            if let event = notifier.events.first {
              expect(event.oldValue as? CGPoint).to(equal(firstPoint))
              expect(event.newValue as? CGPoint).to(equal(secondPoint))
            }
          }
        }

        it("marks the event as external") {
          return property.refresh().then { _ -> () in
            if let event = notifier.events.first {
              expect(event.external).to(beTrue())
            }
          }
        }

      }

      context("when the attribute has not changed") {

        it("resolves to the correct value") {
          return property.refresh().then { newValue in
            expect(newValue).to(equal(firstPoint))
          }
        }

        it("does not emit a ChangedEvent") {
          return property.refresh().then { _ -> () in
            expect(notifier.events.count).to(equal(0))
          }
        }

      }

      context("when a non-optional attribute is missing") {

        it("reports an error") { () -> Promise<Void> in
          windowElement.attrs[.Position] = nil
          let expectedError = PropertyError.InvalidObject(cause: PropertyError.MissingValue)
          return expectToFail(property.refresh(), with: expectedError)
        }

        it("marks the object as invalid", failOnError: false) { () -> Promise<Void> in
          windowElement.attrs[.Position] = nil
          return property.refresh().asVoid().always {
            expect(notifier.stillValid).to(beFalse())
          }
        }

      }

      context("when an optional attribute is missing") {
        var optProperty: WriteableProperty<OfOptionalType<CGPoint>>!
        beforeEach {
          let initPromise = Promise<[AXSwift.Attribute: Any]>([.Position: firstPoint])
          let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(windowElement, .Position, initPromise)
          optProperty = WriteableProperty(delegate, notifier: notifier)
          waitUntil { done in
            optProperty.initialized.then { done() }
          }
        }

        it("reports no error") { () -> Promise<Void> in
          windowElement.attrs[.Position] = nil
          return optProperty.refresh().asVoid()
        }

        it("does not mark the object as invalid") { () -> Promise<Void> in
          return optProperty.initialized.then {
            expect(notifier.stillValid).to(beTrue())
          }
        }

      }

      context("when the window element becomes invalid") {
        beforeEach {
          windowElement.throwInvalid = true
        }

        it("returns an error") {
          return expectToFail(property.refresh(), with: PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement))
        }

        it("calls notifier.notifyInvalid()", failOnError: false) {
          return property.refresh().always {
            expect(notifier.stillValid).to(beFalse())
          }
        }

        it("still allows reading", failOnError: false) {
          return property.refresh().always {
            expect(property.value).to(equal(firstPoint))
          }
        }

        it("does not emit a ChangedEvent", failOnError: false) {
          return property.refresh().always {
            expect(notifier.events.count).to(equal(0))
          }
        }

      }

      context("when called before the property is initialized") {

        var fulfillInitPromise: ([AXSwift.Attribute: Any] -> ())!
        beforeEach {
          let (initPromise, fulfill, _) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()
          fulfillInitPromise = fulfill
          let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(windowElement, .Position, initPromise)
          property = WriteableProperty(delegate, withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: notifier)
        }

        it("doesn't crash") { () -> () in
          property.refresh()
        }

        it("refreshes the property value after initialization is complete") { () -> Promise<Void> in
          let promise = property.refresh().then { newValue -> () in
            expect(newValue).to(equal(secondPoint))
          }
          windowElement.attrs[.Position] = secondPoint
          fulfillInitPromise([.Position: firstPoint])
          return promise
        }

      }
    }

    describe("set") {

      it("eventually updates the property value") {
        property.set(secondPoint)
        expect(property.value).toEventually(equal(secondPoint))
      }

      it("resolves to the new value") {
        return property.set(secondPoint).then { newValue in
          expect(newValue).to(equal(secondPoint))
        }
      }

      it("sets the attribute on the UIElement") {
        return property.set(secondPoint).then { _ -> () in
          expect(windowElement.attrs[.Position]! is CGPoint).to(beTrue())
          expect(windowElement.attrs[.Position]! as? CGPoint).to(equal(secondPoint))
        }
      }

      it("emits a ChangedEvent of the correct type") {
        return property.set(secondPoint).then { _ -> () in
          expect(notifier.events.count).to(equal(1))
          if let event = notifier.events.first {
            expect(event.type == WindowPosChangedEvent.self).to(beTrue())
          }
        }
      }

      it("includes the correct oldVal and newVal in the event") {
        return property.set(secondPoint).then { _ -> () in
          if let event = notifier.events.first {
            expect(event.oldValue as? CGPoint).to(equal(firstPoint))
            expect(event.newValue as? CGPoint).to(equal(secondPoint))
          }
        }
      }

      it("marks the event as internal") {
        return property.set(secondPoint).then { _ -> () in
          if let event = notifier.events.first {
            expect(event.external).to(beFalse())
          }
        }
      }

      it("updates the property value before emitting the event") {
        return property.set(secondPoint).then { _ -> () in
          expect(property.value).to(equal(secondPoint))
        }
      }

      context("when the new value is the same as the old value") {
        it("does not emit a ChangedEvent") {
          return property.set(firstPoint).then { _ in
            expect(notifier.events.count).to(equal(0))
          }
        }
      }

      context("when the UIElement") {
        class MyPropertyDelegate: TestPropertyDelegate<CGPoint> {
          let setTo: CGPoint?
          init(value: CGPoint, setTo: CGPoint) {
            self.setTo = setTo
            super.init(value: value)
          }
          override func writeValue(newValue: CGPoint?) throws {
            systemValue = setTo
          }
        }

        var delegate: MyPropertyDelegate!
        func initPropertyWithDelegate(delegate_: MyPropertyDelegate) {
          delegate = delegate_
          property = WriteableProperty(delegate, withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: notifier)
          finishPropertyInit()
        }

        context("does not change its value") {
          beforeEach {
            initPropertyWithDelegate(MyPropertyDelegate(value: firstPoint, setTo: firstPoint))
          }

          it("reports the actual value") {
            return property.set(secondPoint).then { newValue -> () in
              expect(newValue).to(equal(firstPoint))
              expect(property.value).to(equal(firstPoint))
            }
          }

          it("does not emit a ChangedEvent") {
            return property.set(secondPoint).then { newValue in
              expect(notifier.events.count).to(equal(0))
            }
          }

        }

        context("changes to a different value than the one requested") {
          let resultingPoint = CGPoint(x: 50, y: 75)
          beforeEach {
            initPropertyWithDelegate(MyPropertyDelegate(value: firstPoint, setTo: resultingPoint))
          }

          it("reports the actual value") {
            return property.set(secondPoint).then { newValue -> () in
              expect(newValue).to(equal(resultingPoint))
              expect(property.value).to(equal(resultingPoint))
            }
          }

          it("emits a ChangedEvent with the actual value") {
            return property.set(secondPoint).then { newValue -> () in
              expect(notifier.events.count).to(equal(1))
              if let event = notifier.events.first {
                expect(event.oldValue as? CGPoint).to(equal(firstPoint))
                expect(event.newValue as? CGPoint).to(equal(resultingPoint))
              }
            }
          }

          it("marks the event as internal") {
            return property.set(secondPoint).then { newValue -> () in
              if let event = notifier.events.first {
                expect(event.external).to(beFalse())
              }
            }
          }

        }
      }

      // This happens, for instance, if the system notification for the change is received first.
      context("when a refresh is requested before reading back the new value") {
        class MyPropertyDelegate<T: Equatable>: TestPropertyDelegate<T> {
          let onWrite: () -> ()
          init(value: T, onWrite: () -> ()) {
            self.onWrite = onWrite
            super.init(value: value)
          }
          override func writeValue(newValue: T?) throws {
            systemValue = newValue
            onWrite()
          }
        }

        var delegate: MyPropertyDelegate<CGPoint>!
        var property: WriteableProperty<OfType<CGPoint>>!
        beforeEach {
          delegate = MyPropertyDelegate(value: firstPoint, onWrite: {
            property.refresh()
          })
          property = WriteableProperty(delegate,
            withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: notifier)
          finishPropertyInit()
        }

        it("only emits one event") {
          return property.set(secondPoint).then { _ -> () in
            expect(notifier.events.count).to(equal(1))
          }
        }

        it("marks the event as internal") {
          return property.set(secondPoint).then { _ -> () in
            if let event = notifier.events.first {
              expect(event.external).to(beFalse())
            }
          }
        }

      }

      context("when the window element becomes invalid") {
        beforeEach {
          windowElement.throwInvalid = true
        }

        it("returns an error") {
          return expectToFail(property.refresh(), with: PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement))
        }

        it("calls notifier.notifyInvalid()", failOnError: false) {
          return property.set(secondPoint).always {
            expect(notifier.stillValid).to(beFalse())
          }
        }

        it("does not update the property value, but still allows reading", failOnError: false) {
          return property.set(secondPoint).always {
            expect(property.value).to(equal(firstPoint))
          }
        }

        it("does not emit a ChangedEvent", failOnError: false) {
          return property.set(secondPoint).always {
            expect(notifier.events.count).to(equal(0))
          }
        }

      }
    }

  }
}
