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

