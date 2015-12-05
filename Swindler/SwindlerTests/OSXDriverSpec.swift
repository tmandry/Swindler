import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

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
      }
      afterEach {
        TestApplicationElement.allApps = []
      }

      // Some of these are higher level versions of unit tests on their respective objects.

      context("when a window is created") {
        beforeEach {
          expect(state.visibleWindows.count).toEventually(equal(1))
        }

        it("adds the window to visibleWindows") {
          expect(state.visibleWindows.count).to(equal(1))
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

        it("emits WindowDestroyedEvent") {
          var callbacks = 0
          state.on { (event: WindowDestroyedEvent) in
            callbacks++
          }
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
        }

        it("removes the window from visibleWindows") {
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(state.visibleWindows.count).toEventually(equal(0))
        }

      }

      context("when a window property changes") {

        it("emits a ChangedEvent") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
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
    }

  }
}

class TestNotifier: EventNotifier {
  var events: [EventType] = []
  func notify<Event: EventType>(event: Event) {
    events.append(event)
  }

  func getEventsOfType<T: EventType>(type: T.Type) -> [T] {
    return events.flatMap({ $0 as? T })
  }
  func getEventOfType<T: EventType>(type: T.Type) -> T? {
    return getEventsOfType(type).first
  }

  func expectEvent<T: EventType>(type: T.Type, file: String = __FILE__, line: UInt = __LINE__) -> T? {
    expect(self.getEventOfType(type), file: file, line: line).toEventuallyNot(beNil(), description: "expected event of type \(type)")
    return self.getEventOfType(type)
  }

  func waitUntilEvent<T: EventType>(type: T.Type, file: String = __FILE__, line: UInt = __LINE__) -> T? {
    var event: T?
    func getEvent() -> Bool {
      event = getEventOfType(type)
      return (event != nil)
    }
    waitUntil(getEvent(), file: file, line: line)
    return event
  }
}

class OSXApplicationDelegateSpec: QuickSpec {
  override func spec() {

    var app: Swindler.Application!
    var appDelegate: OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>!
    var appElement: TestApplicationElement!
    var notifier: TestNotifier!
    var observer: FakeObserver!

    func initializeApp() {
      waitUntil { done in
        OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>.initialize(
          axElement: appElement, notifier: notifier).then { applicationDelegate -> () in
            appDelegate = applicationDelegate
            observer = appDelegate.observer
            app = Swindler.Application(delegate: appDelegate)
            done()
        }
      }
    }

    beforeEach {
      notifier = TestNotifier()
      appElement = TestApplicationElement()
      initializeApp()
    }

    func createWindow() -> TestWindowElement {
      let windowElement = TestWindowElement(forApp: appElement)
      appElement.windows.append(windowElement)
      observer.emit(.WindowCreated, forElement: windowElement)
      return windowElement
    }

    func getWindowElement(window: Window?) -> TestUIElement? {
      typealias WinDelegate = OSXWindowDelegate<TestUIElement, TestApplicationElement, FakeObserver>
      return ((window?.delegate) as! WinDelegate?)?.axElement
    }

    // mainWindow is quite a bit more complicated than other properties, so we explicitly test it
    // here.
    describe("mainWindow") {
      context("when there is no initial main window") {
        it("initially equals nil") {
          expect(appElement.attrs[.MainWindow]).to(beNil())
          expect(app.mainWindow.value).to(beNil())
        }
      }

      context("when there is an initial main window") {
        it("equals the main window") {
          let windowElement = createWindow()
          windowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow] = windowElement
          initializeApp()

          expect(getWindowElement(app.mainWindow.value)).to(equal(windowElement))
        }
      }

      context("when a window becomes main") {
        func makeWindowMain(windowElement: TestWindowElement) {
          windowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow] = windowElement
          observer.emit(.MainWindowChanged, forElement: windowElement)
        }

        var windowElement: TestWindowElement!
        beforeEach {
          windowElement = createWindow()
          makeWindowMain(windowElement)
        }

        it("updates the value") {
          expect(getWindowElement(app.mainWindow.value)).toEventually(equal(windowElement))
        }

        it("emits an ApplicationMainWindowChangedEvent with correct values") {
          if let event = notifier.expectEvent(ApplicationMainWindowChangedEvent.self) {
            // expect(event.application).to(equal(app))
            expect(event.external).to(beTrue())
            expect(event.oldVal).to(beNil())
            expect(getWindowElement(event.newVal)).to(equal(windowElement))
          }
        }

      }

    }

    context("when a window is created") {
      var windowElement: TestWindowElement!
      beforeEach {
        windowElement = createWindow()
      }

      it("watches for events on the window") {
        notifier.waitUntilEvent(WindowCreatedEvent.self)
        expect(observer.watchedElements[windowElement]).toNot(beNil())
      }

//      it("adds the window to visibleWindows") {
//        expect(app.visibleWindows.count).to(equal(1))
//      }

      it("emits WindowCreatedEvent") {
        if let event = notifier.expectEvent(WindowCreatedEvent.self) {
          expect(getWindowElement(event.window)).to(equal(windowElement))
        }
      }

      it("marks the WindowCreatedEvent as external") {
        if let event = notifier.waitUntilEvent(WindowCreatedEvent.self) {
          expect(event.external).to(beTrue())
        }
      }

    }

    context("when a window is destroyed") {
      var windowElement: TestWindowElement!
      beforeEach {
        windowElement = createWindow()
        notifier.waitUntilEvent(WindowCreatedEvent.self)
        observer.emit(.UIElementDestroyed, forElement: windowElement)
      }

//      it("removes the window from visibleWindows") {
//        expect(app.visibleWindows.count).to(equal(0))
//      }

      it("emits WindowDestroyedEvent") {
        if let event = notifier.expectEvent(WindowDestroyedEvent.self) {
          expect(getWindowElement(event.window)).to(equal(windowElement))
        }
      }

      it("marks the WindowDestroyedEvent as external") {
        if let event = notifier.waitUntilEvent(WindowDestroyedEvent.self) {
          expect(event.external).to(beTrue())
        }
      }

    }

  }
}

class OSXWindowDelegateSpec: QuickSpec {
  override func spec() {
    typealias OSXWindow = OSXWindowDelegate<TestUIElement, TestApplicationElement, TestObserver>
    func initializeWithElement(windowElement: TestUIElement) -> Promise<OSXWindow> {
      return OSXWindow.initialize(
        notifier: TestNotifier(), axElement: windowElement, observer: TestObserver())
    }

    beforeEach { TestApplicationElement.allApps = [] }

    describe("initialize") {

      it("initializes window properties") { () -> Promise<Void> in
        let windowElement = TestWindowElement(forApp: TestApplicationElement())
        windowElement.attrs[.Position]  = CGPoint(x: 5, y: 5)
        windowElement.attrs[.Size]      = CGSize(width: 100, height: 100)
        windowElement.attrs[.Title]     = "a window title"
        windowElement.attrs[.Minimized] = false

        return initializeWithElement(windowElement).then { windowDelegate -> () in
          expect(windowDelegate.pos.value).to(equal(CGPoint(x: 5, y: 5)))
          expect(windowDelegate.size.value).to(equal(CGSize(width: 100, height: 100)))
          expect(windowDelegate.title.value).to(equal("a window title"))
          expect(windowDelegate.minimized.value).to(beFalse())
        }
      }

      it("marks the window as valid") { () -> Promise<Void> in
        let windowElement = TestWindowElement(forApp: TestApplicationElement())
        return initializeWithElement(windowElement).then { windowDelegate -> () in
          expect(windowDelegate.valid).to(beTrue())
        }
      }

      context("when called with a window that is missing attributes") {
        it("returns an error") { () -> Promise<Void> in
          let windowElement = TestWindowElement(forApp: TestApplicationElement())
          windowElement.attrs.removeValueForKey(.Position)

          let expectedError = OSXDriverError.MissingAttribute(attribute: .Position, onElement: windowElement)
          return expectToFail(initializeWithElement(windowElement), with: expectedError)
        }
      }

    }

    context("when a window is destroyed") {
      it("marks the window as invalid") { () -> Promise<Void> in
        let windowElement = TestWindowElement(forApp: TestApplicationElement())
        return initializeWithElement(windowElement).then { windowDelegate -> () in
          windowDelegate.handleEvent(.UIElementDestroyed, observer: TestObserver())
          expect(windowDelegate.valid).toEventually(beFalse())
        }
      }
    }

    context("when the position changes") {
      var notifier: TestNotifier!
      var windowElement: TestWindowElement!
      var windowDelegate: OSXWindow!
      beforeEach {
        notifier = TestNotifier()
        windowElement = TestWindowElement(forApp: TestApplicationElement())
        waitUntil { done in
          return OSXWindow.initialize(
              notifier: notifier, axElement: windowElement, observer: TestObserver()
          ).then { delegate -> () in
            windowDelegate = delegate
            done()
          }
        }

        windowElement.attrs[.Position] = CGPoint(x: 500, y: 500)
        windowDelegate.handleEvent(.Moved, observer: TestObserver())
      }

      func getWindowElement(window: Window?) -> TestUIElement? {
        return ((window?.delegate) as! OSXWindow?)?.axElement
      }

      it("emits a WindowPosChangedEvent") {
        if let event = notifier.expectEvent(WindowPosChangedEvent.self) {
          expect(getWindowElement(event.window)).to(equal(windowElement))
        }
      }

      it("marks the event as external") {
        if let event = notifier.waitUntilEvent(WindowPosChangedEvent.self) {
          expect(event.external).to(beTrue())
        }
      }

    }

  }
}
