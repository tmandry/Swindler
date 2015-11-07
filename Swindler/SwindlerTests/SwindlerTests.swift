import Quick
import Nimble

@testable import Swindler
import AXSwift

class TestUIElement: UIElementType, Hashable {
  static var elementCount: Int = 0

  var id: Int = elementCount++
  var processID: pid_t = 0
  var attrs: [Attribute: Any] = [:]

  init() { }
  var hashValue: Int { return id }

  func pid() throws -> pid_t { return processID }
  func attribute<T>(attribute: Attribute) throws -> T? {
    if let value = attrs[attribute] {
      return (value as! T)
    }
    return nil
  }
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any] {
    var result: [Attribute: Any] = [:]
    for attribute in attributes {
      result[attribute] = attrs[attribute]
    }
    return result
  }
  func setAttribute(attribute: Attribute, value: Any) throws {
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


class OSXStateSpec: QuickSpec {
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

        expect(MyTestObserver.numObservers).to(equal(2), description: "observer count")
      }

    }

    context("after initialization") {
      // Set up a state with a single application containing a single window.
      var app: TestApplication!
      var window: TestWindow!
      var state: OSXState<TestUIElement, TestApplication, FakeObserver>!
      var observer: FakeObserver!
      beforeEach {
        app = TestApplication()
        window = TestWindow(forApp: app)
        window.attrs[.Position] = CGPoint(x: 5, y: 5)
        TestApplication.allApps = [app]
        state = OSXState<TestUIElement, TestApplication, FakeObserver>()
        observer = FakeObserver.observers.first!
        observer.emit(.WindowCreated, forElement: window)
      }

      context("when a window is created") {
        it("watches for events on the window") {
          expect(observer.watchedElements[window]).toNot(beNil())
        }

        it("adds the window to visibleWindows") {
          expect(state.visibleWindows.count).to(equal(1))
        }

        it("reads the window's properties into the state") {
          expect(state.visibleWindows.first!.pos).to(equal(CGPoint(x: 5, y: 5)))
        }

        it("calls WindowCreatedEvent callbacks") {
          var callbacks = 0
          state.on { (event: WindowCreatedEvent) in
            callbacks++
            // expect(event.window).to(equal(window))
          }

          let window = TestWindow(forApp: app)
          observer.emit(.WindowCreated, forElement: window)
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }
      }

      context("when a window property changes") {
        it("calls a ChangedEvent callback") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          observer.emit(.WindowCreated, forElement: window)
          window.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: window)
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

        it("includes the correct oldVal and newVal in the event") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.oldVal).to(equal(CGPoint(x: 5, y: 5)))
            expect(event.newVal).to(equal(CGPoint(x: 100, y: 100)))
          }
          window.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: window)
        }

        it("property value equals event.newVal") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.window.pos).to(equal(event.newVal))
          }
          window.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: window)
        }

        it("marks the event as external") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.external).to(beTrue())
          }
          window.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: window)
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
        window.attrs[.Position] = CGPoint(x: 100, y: 100)
        observer.emit(.Moved, forElement: window)
        expect(callbacks1).to(equal(1), description: "callback1 should be called once")
        expect(callbacks2).to(equal(1), description: "callback2 should be called once")
      }

      context("when a window property is set") {
        var osxWindow: WindowType!
        beforeEach { osxWindow = state.visibleWindows.first! }

        it("changes the property on the UIElement") {
          osxWindow.pos = CGPoint(x: 100, y: 100)
          expect(window.attrs[.Position]! is CGPoint).to(beTrue())
          expect(window.attrs[.Position]! as? CGPoint).to(equal(CGPoint(x: 100, y: 100)))
        }

        it("calls a ChangedEvent callback") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          osxWindow.pos = CGPoint(x: 100, y: 100)
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

        it("includes the correct oldVal and newVal in the event") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.oldVal).to(equal(CGPoint(x: 5, y: 5)))
            expect(event.newVal).to(equal(CGPoint(x: 100, y: 100)))
          }
          osxWindow.pos = CGPoint(x: 100, y: 100)
        }

        it("marks the event as internal") {
          state.on { (event: WindowPosChangedEvent) in
            expect(event.external).to(beFalse())
          }
          osxWindow.pos = CGPoint(x: 100, y: 100)
        }

      }

    }

    // TODO: error handling

  }
}
