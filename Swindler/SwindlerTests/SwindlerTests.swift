import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class TestUIElement: UIElementType, Hashable {
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
}
func ==(lhs: TestUIElement, rhs: TestUIElement) -> Bool {
  return lhs === rhs
}

class BaseTestApplication: TestUIElement {
  typealias UIElementType = TestUIElement
  var toElement: TestUIElement { return self }

  override init() {
    super.init()
    processID = Int32(id)
    attrs[.Role]    = AXSwift.Role.Application
    attrs[.Windows] = Array<TestUIElement>()
  }
}
final class TestApplication: BaseTestApplication, ApplicationType {
  static var allApps: [TestApplication] = []
  static func all() -> [TestApplication] { return TestApplication.allApps }
}

class TestWindow: TestUIElement {
  var app: BaseTestApplication
  init(forApp app: BaseTestApplication) {
    self.app = app
    super.init()
    processID = app.processID
    attrs[.Role]     = AXSwift.Role.Window
    attrs[.Position] = CGPoint(x: 0, y: 0)
    attrs[.Size]     = CGSize(width: 0, height: 0)
    attrs[.Title]    = "Window \(id)"
  }
}

class TestObserver: ObserverType {
  typealias Callback = (observer: TestObserver, element: TestUIElement, notification: AXSwift.Notification) -> ()

  required init(processID: pid_t, callback: Callback) throws { }
  init() { }

  func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {}
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

  func emit(notification: AXSwift.Notification, forElement window: TestWindow) {
    if notification == .WindowCreated {
      doEmit(notification, watchedElement: window.app, passedElement: window)
    } else {
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


class OSXDriverSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplication.allApps = [] }
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

        TestApplication.allApps = [TestApplication(), TestApplication()]
        let _ = OSXState<TestUIElement, TestApplication, MyTestObserver>()

        expect(MyTestObserver.numObservers).to(equal(2), description: "should be 2 observers")
      }

      it("handles applications that cannot be watched") {
        class MyTestObserver: TestObserver {
          override private func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {
            throw AXSwift.Error.CannotComplete
          }
        }

        TestApplication.allApps = [TestApplication()]
        let _ = OSXState<TestUIElement, TestApplication, MyTestObserver>()
        // test that it doesn't crash
      }

    }

    context("after initialization") {
      // Set up a state with a single application containing a single window.
      var app: TestApplication!
      var windowElement: TestWindow!
      var observer: FakeObserver!
      var state: OSXState<TestUIElement, TestApplication, FakeObserver>!
      var window: WindowType!
      beforeEach {
        app = TestApplication()
        windowElement = TestWindow(forApp: app)
        windowElement.attrs[.Position] = CGPoint(x: 5, y: 5)
        TestApplication.allApps = [app]
        state = OSXState<TestUIElement, TestApplication, FakeObserver>()
        observer = FakeObserver.observers.first!
        observer.emit(.WindowCreated, forElement: windowElement)
        expect(state.visibleWindows.count).toEventually(equal(1))
        window = state.visibleWindows.first!
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

          let window = TestWindow(forApp: app)
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
        // TODO: We depend on window.pos.refresh() here to ensure that an event has finished
        // its own async refresh before checking conditions. This is necessary when testing that
        // callbacks doesn't change. We are probably testing this at the wrong level of abstraction.

        it("emits a ChangedEvent") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
        }

        it("includes the correct oldVal and newVal in the event") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.oldVal).to(equal(CGPoint(x: 5, y: 5)))
            expect(event.newVal).to(equal(CGPoint(x: 100, y: 100)))
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
        }

        it("property value equals event.newVal") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.window.pos.value).to(equal(event.newVal))
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          return window.pos.refresh()
        }

        it("marks the event as external") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.external).to(beTrue())
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          return window.pos.refresh()
        }

        context("when the event fires but the value is not changed") {

          it("does not emit a ChangedEvent", closure: {
            var callbacks = 0
            state.on { (event: WindowPosChangedEvent) in
              callbacks++
            }
            observer.emit(.Moved, forElement: windowElement)
            return window.pos.refresh().then { _ in
              expect(callbacks).to(equal(0), description: "callback should not be called")
            }
          } as () -> Promise<Void>)

        }
      }

      it("calls multiple event handlers", closure: {
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
        return window.pos.refresh().then({ _ in
          expect(callbacks1).toEventually(equal(1), description: "callback1 should be called once")
          expect(callbacks2).toEventually(equal(1), description: "callback2 should be called once")
        } as (CGPoint) -> ())
      } as () -> Promise<Void>)

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

    typealias Window = OSXWindow<TestUIElement, TestApplication, TestObserver>

    beforeEach { TestApplication.allApps = [] }

    describe("initialize") {
      fcontext("when called with a window that is missing attributes") {
        it("returns an error") { () -> Promise<Void> in
          let windowElement = TestWindow(forApp: TestApplication())
          windowElement.attrs.removeValueForKey(.Position)

          let promise = Window.initialize(notifier: TestNotifier(), axElement: windowElement, observer: TestObserver())
          return promise.asVoid().then({
            fail("Expected to fail")
          }).recover { (error: ErrorType) -> () in
            expect(error is OSXDriverError).to(beTrue(), description: "expected OSXDriverError, got \(error)")
            expect(error as? OSXDriverError).to(equal(OSXDriverError.MissingAttribute))
          }
        }
      }
    }

  }
}

class TestWindowPropertyNotifier: WindowPropertyNotifier {
  // We must make our own struct because we don't have a window.
  struct Event {
    var type: Any.Type
    var external: Bool
    var oldValue: Any
    var newValue: Any
  }
  var events: [Event] = []
  var stillValid = true

  func notify<EventT: WindowPropertyEventType>(event: EventT.Type, external: Bool, oldValue: EventT.PropertyType, newValue: EventT.PropertyType) {
    events.append(Event(type: event, external: external, oldValue: oldValue, newValue: newValue))
  }
  func notifyInvalid() {
    stillValid = false
  }
}

class AXPropertySpec: QuickSpec {
  override func spec() {

    // Set up a state with a single application containing a single window.
    var property: WriteableProperty<CGPoint>!
    var windowElement: TestWindow!
    var notifier: TestWindowPropertyNotifier!
    beforeEach {
      let position = CGPoint(x: 5, y: 5)
      windowElement = TestWindow(forApp: TestApplication())
      windowElement.attrs[.Position] = position
      let initPromise = Promise<[AXSwift.Attribute: Any]>([.Position: position])
      notifier = TestWindowPropertyNotifier()
      property = WriteableProperty(WindowPosChangedEvent.self, notifier, AXPropertyDelegate(windowElement, .Position, initPromise))
      waitUntil { done in
        property.initialized.then {
          done()
        }
      }
    }

    describe("refresh") {
      // TODO: implement
      context("when the attribute has changed") {

      }
    }

    // TODO: set() promise tests

    describe("when the value is set") {

      it("updates the property value") {
        return property.set(CGPoint(x: 100, y: 100)).then({ _ in
          expect(property.value).toEventually(equal(CGPoint(x: 100, y: 100)))
        })
      }

      it("changes the property on the UIElement") {
        return property.set(CGPoint(x: 100, y: 100)).then({ _ in
          expect(windowElement.attrs[.Position]! is CGPoint).to(beTrue())
          expect(windowElement.attrs[.Position]! as? CGPoint).to(equal(CGPoint(x: 100, y: 100)))
        } as (CGPoint) -> ())
      }

      it("emits a ChangedEvent") {
        return property.set(CGPoint(x: 100, y: 100)).then { _ in
          expect(notifier.events.count).to(equal(1))
        }
      }

      it("includes the correct oldVal and newVal in the event") {
        return property.set(CGPoint(x: 100, y: 100)).then({ _ in
          if let event = notifier.events.first {
            expect(event.oldValue as? CGPoint).to(equal(CGPoint(x: 5, y: 5)))
            expect(event.newValue as? CGPoint).to(equal(CGPoint(x: 100, y: 100)))
          }
        } as (CGPoint) -> ())
      }

      it("marks the event as internal") {
        return property.set(CGPoint(x: 100, y: 100)).then({ _ in
          if let event = notifier.events.first {
            expect(event.external).to(beFalse())
          }
        } as (CGPoint) -> ())
      }

      context("when the new value is the same as the old value") {
        it("does not emit a ChangedEvent") {
          return property.set(CGPoint(x: 5, y: 5)).then { _ in
            expect(notifier.events.count).to(equal(0))
          }
        }
      }

      context("when the window element becomes invalid") {
        beforeEach {
          windowElement.throwInvalid = true
        }

        it("returns an error", failOnError: false) {
          return property.set(CGPoint(x: 100, y: 100)).then { _ in
            fail("expected to return an error")
          }
        }

        it("calls notifier.notifyInvalid()", failOnError: false) {
          return property.set(CGPoint(x: 100, y: 100)).always {
            expect(notifier.stillValid).to(beFalse())
          }
        }

        it("does not update the property value, but still allows reading", failOnError: false) {
          return property.set(CGPoint(x: 100, y: 100)).always {
            expect(property.value).to(equal(CGPoint(x: 5, y: 5)))
          }
        }

        it("does not emit a ChangedEvent", failOnError: false) {
          return property.set(CGPoint(x: 100, y: 100)).always {
            expect(notifier.events.count).to(equal(0))
          }
        }

      }
    }

  }
}
