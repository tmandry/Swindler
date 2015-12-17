import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class OSXStateSpec: QuickSpec {
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

      it("doesn't leak memory") {
        weak var state = OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver>()
        expect(state).toEventually(beNil())
      }

      context("when there is an application") {
        it("doesn't leak memory") {
          TestApplicationElement.allApps = [TestApplicationElement()]
          weak var state = OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver>()

          // For some reason when `state` is captured in an autoclosure, it prevents the object from
          // being freed until the closure is freed. This explicit closure avoids that issue.
          func isNil() -> Bool {
            return state == nil
          }
          expect(isNil()).toEventually(beTrue())
        }
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
        expect(state.knownWindows.count).toEventually(equal(1))
      }
      afterEach {
        TestApplicationElement.allApps = []
      }

      // Some of these are higher level versions of unit tests on their respective objects.

      context("when a window is created") {
        beforeEach {
          expect(state.knownWindows).toEventually(haveCount(1))
        }

        it("adds the window to knownWindows") {
          expect(state.knownWindows).to(haveCount(1))
        }

        it("emits WindowCreatedEvent") {
          var callbacks = 0
          state.on { (event: WindowCreatedEvent) in
            callbacks++
          }
          let window = TestWindowElement(forApp: appElement)
          observer.emit(.WindowCreated, forElement: window)
          expect(state.knownWindows).toEventually(haveCount(2))
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

        it("removes the window from knownWindows") {
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(state.knownWindows).toEventually(haveCount(0))
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

      describe("runningApplications") {
        context("on initialization") {
          it("contains the running applications") {
            expect(state.runningApplications).toEventually(haveCount(1))
          }
        }
      }

    }

  }
}
