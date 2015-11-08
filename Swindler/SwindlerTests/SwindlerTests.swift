import Quick
import Nimble

@testable import Swindler
import AXSwift

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

  var callback: Callback!

  required init(processID: pid_t, callback: Callback) throws {
    self.callback = callback
  }
  func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {}
}

// A more elaborate TestObserver that actually tracks which elements and notifications are being
// observed and supports emitting notifications.
class FakeObserver: TestObserver {
  static var observers: [FakeObserver] = []
  required init(processID: pid_t, callback: Callback) throws {
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
      var state: OSXState<TestUIElement, TestApplication, FakeObserver>!
      var observer: FakeObserver!
      beforeEach {
        app = TestApplication()
        windowElement = TestWindow(forApp: app)
        windowElement.attrs[.Position] = CGPoint(x: 5, y: 5)
        TestApplication.allApps = [app]
        state = OSXState<TestUIElement, TestApplication, FakeObserver>()
        observer = FakeObserver.observers.first!
        observer.emit(.WindowCreated, forElement: windowElement)
      }

      context("when a window is created") {

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
          expect(state.visibleWindows.first!.pos).to(equal(CGPoint(x: 5, y: 5)))
        }

        it("emits WindowCreatedEvent") {
          var callbacks = 0
          state.on { (event: WindowCreatedEvent) in
            callbacks++
          }

          let window = TestWindow(forApp: app)
          observer.emit(.WindowCreated, forElement: window)
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

      }

      context("when a window is destroyed") {
        var window: WindowType!
        beforeEach { window = state.visibleWindows.first! }

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

        it("calls a ChangedEvent callback") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          observer.emit(.WindowCreated, forElement: windowElement)
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks).to(equal(1), description: "callback should be called once")
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
            expect(event.window.pos).to(equal(event.newVal))
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
        }

        it("marks the event as external") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.external).to(beTrue())
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
        }

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
        expect(callbacks1).to(equal(1), description: "callback1 should be called once")
        expect(callbacks2).to(equal(1), description: "callback2 should be called once")
      }

      context("when a window property is set") {
        var window: WindowType!
        beforeEach { window = state.visibleWindows.first! }

        it("updates the property value") {
          window.pos = CGPoint(x: 100, y: 100)
          expect(window.pos).to(equal(CGPoint(x: 100, y: 100)))
        }

        it("changes the property on the UIElement") {
          window.pos = CGPoint(x: 100, y: 100)
          expect(windowElement.attrs[.Position]! is CGPoint).to(beTrue())
          expect(windowElement.attrs[.Position]! as? CGPoint).to(equal(CGPoint(x: 100, y: 100)))
        }

        it("emits a ChangedEvent") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          window.pos = CGPoint(x: 100, y: 100)
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

        it("includes the correct oldVal and newVal in the event") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.oldVal).to(equal(CGPoint(x: 5, y: 5)))
            expect(event.newVal).to(equal(CGPoint(x: 100, y: 100)))
          }
          window.pos = CGPoint(x: 100, y: 100)
        }

        it("marks the event as internal") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.external).to(beFalse())
          }
          window.pos = CGPoint(x: 100, y: 100)
        }

        context("when the window element becomes invalid") {
          beforeEach {
            windowElement.throwInvalid = true
          }

          it("marks the window as invalid") {
            expect(window.valid).to(beTrue())
            window.pos = CGPoint(x: 100, y: 100)
            expect(window.valid).to(beFalse())
          }

          it("does not update the property value, but still allows reading") {
            window.pos = CGPoint(x: 100, y: 100)
            expect(window.pos).to(equal(CGPoint(x: 5, y: 5)))
          }

          it("does not emit a ChangedEvent") {
            var callbacks = 0
            state.on { (event: WindowPosChangedEvent) in
              callbacks++
            }
            window.pos = CGPoint(x: 100, y: 100)
            expect(callbacks).to(equal(0), description: "callback should not be called")
          }

        }
      }
    }

  }
}

class OSXWindowSpec: QuickSpec {
  override func spec() {

    typealias State = OSXState<TestUIElement, TestApplication, FakeObserver>

    var state: State!
    var observer: FakeObserver!
    beforeEach { FakeObserver.observers = [] }
    beforeEach {
      TestApplication.allApps = [TestApplication()]
      state = State()
      observer = FakeObserver.observers.first!
    }

    describe("init") {
      context("when called with a window that is missing attributes") {
        it("throws an error") {
          let windowElement = TestWindow(forApp: TestApplication.allApps.first!)
          windowElement.attrs.removeValueForKey(.Position)

          expect {
            try State.Window(state: state, axElement: windowElement, observer: observer)
          }.to(throwError(OSXDriverError.MissingAttributes))
        }
      }
    }

  }
}
