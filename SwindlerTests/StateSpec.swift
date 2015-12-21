import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class StubApplicationObserver: ApplicationObserverType {
  var frontmostApplicationPID: pid_t? { return nil }
  func onFrontmostApplicationChanged(handler: () -> ()) {}
  func makeApplicationFrontmost(pid: pid_t) throws {}
}

class FakeApplicationObserver: ApplicationObserverType {
  private var frontmost_: pid_t? = nil
  var frontmostApplicationPID: pid_t? { return frontmost_ }

  var handlers: [() -> ()] = []
  func onFrontmostApplicationChanged(handler: () -> ()) {
    handlers.append(handler)
  }

  func makeApplicationFrontmost(pid: pid_t) throws {
    setFrontmost(pid)
  }

  private func setFrontmost(pid: pid_t?) {
    frontmost_ = pid
    handlers.forEach{ handler in handler() }
  }
}

class OSXStateSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplicationElement.allApps = [] }
    beforeEach { FakeObserver.observers = [] }

    context("during initialization") {

      func initialize(
        appObserver: ApplicationObserverType = StubApplicationObserver()
      ) -> OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver> {
        return OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver>(appObserver: appObserver)
      }

      func initializeWithObserver<Obs: ObserverType>(elementObserver: Obs.Type)
          -> OSXStateDelegate<TestUIElement, TestApplicationElement, Obs> {
        return OSXStateDelegate<TestUIElement, TestApplicationElement, Obs>(appObserver: StubApplicationObserver())
      }

      it("observes all applications") {
        class MyTestObserver: TestObserver {
          static var numObservers: Int = 0
          required init(processID: pid_t, callback: Callback) throws {
            MyTestObserver.numObservers++
            try super.init(processID: processID, callback: callback)
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement(), TestApplicationElement()]
        let _ = initializeWithObserver(MyTestObserver.self)

        expect(MyTestObserver.numObservers).to(equal(2), description: "should be 2 observers")
      }

      it("handles applications that cannot be watched") {
        class MyTestObserver: TestObserver {
          override private func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {
            throw AXSwift.Error.CannotComplete
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement()]
        let _ = initializeWithObserver(MyTestObserver.self)
        // test that it doesn't crash
      }

      it("doesn't leak memory") {
        weak var state = initialize()
        expect(state).toEventually(beNil())
      }

      context("when there is an application") {
        it("doesn't leak memory") {
          TestApplicationElement.allApps = [TestApplicationElement()]
          weak var state = initialize()

          // For some reason when `state` is captured in an autoclosure, it prevents the object from
          // being freed until the closure is freed. This explicit closure avoids that issue.
          func isNil() -> Bool {
            return state == nil
          }
          expect(isNil()).toEventually(beTrue())
        }
      }

      describe("frontmostApplication") {

        context("when there is no frontmost application") {
          it("is nil") { () -> Promise<Void> in
            let state = initialize()
            return state.frontmostApplication.initialized.then {
              expect(state.frontmostApplication.value).to(beNil())
            }
          }
        }

        context("when there is a frontmost application") {
          class MyApplicationObserver: StubApplicationObserver {
            override var frontmostApplicationPID: pid_t? { return 1234 as pid_t }
          }

          func getElement(app: Swindler.Application?) -> TestUIElement? {
            typealias AppDelegate = OSXApplicationDelegate<TestUIElement, TestApplicationElement, TestObserver>
            return (app?.delegate as! AppDelegate?)?.axElement
          }

          it("contains the frontmost application") { () -> Promise<Void> in
            let appElement = TestApplicationElement()
            appElement.processID = 1234
            TestApplicationElement.allApps = [appElement]

            let state = initialize(MyApplicationObserver())
            return state.frontmostApplication.initialized.then {
              expect(getElement(state.frontmostApplication.value)).to(equal(appElement))
            }
          }

        }
      }

    }

    context("after initialization") {
      // Set up a state with a single application containing a single window.
      var appElement: TestApplicationElement!
      var windowElement: TestWindowElement!
      var observer: FakeObserver!
      var appObserver: FakeApplicationObserver!
      var state: State!
      beforeEach {
        appElement = TestApplicationElement()
        windowElement = TestWindowElement(forApp: appElement)
        windowElement.attrs[.Position] = CGPoint(x: 5, y: 5)
        appElement.attrs[.Windows] = [windowElement as TestUIElement]
        appElement.attrs[.MainWindow] = windowElement
        TestApplicationElement.allApps = [appElement]

        appObserver = FakeApplicationObserver()
        state = State(delegate: OSXStateDelegate<TestUIElement, TestApplicationElement, FakeObserver>(
          appObserver: appObserver))
        observer = FakeObserver.observers.first!
        observer.emit(.WindowCreated, forElement: windowElement)
        expect(state.knownWindows.count).toEventually(equal(1))
      }
      afterEach {
        TestApplicationElement.allApps = []
      }

      // Some of these are higher level versions of unit tests on their respective objects.
      // TODO: put higher-level tests in their own spec.

      it("creates an application object in runningApplications") {
        expect(state.runningApplications).toEventually(haveCount(1))
      }

      context("when a window is created") {
        beforeEach {
          waitUntil(state.knownWindows.count == 1)
        }

        it("adds the window to knownWindows") {
          expect(state.knownWindows).to(haveCount(1))
        }

        it("has an application property equal to the application of the window") {
          waitUntil(state.runningApplications.count == 1)
          expect(state.knownWindows.first!.application).to(equal(state.runningApplications.first!))
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

      describe("frontmostApplication") {
        context("when the frontmost application changes") {

          func getElement(app: Swindler.Application?) -> TestUIElement? {
            typealias AppDelegate = OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>
            return (app?.delegate as! AppDelegate?)?.axElement
          }

          it("updates") {
            expect(state.delegate.frontmostApplication.value).to(beNil())
            appObserver.setFrontmost(appElement.processID)
            expect(getElement(state.delegate.frontmostApplication.value)).toEventually(equal(appElement))
          }

        }

        context("when set to an application") {

          it("makes that application frontmost") {
            expect(state.delegate.frontmostApplication.value).to(beNil())
            state.delegate.frontmostApplication.set(state.runningApplications.first!)
            expect(appObserver.frontmostApplicationPID).toEventually(equal(appElement.processID))
          }

          context("when the system complies") {
            it("returns the app in the promise") { () -> Promise<Void> in
              return state.delegate.frontmostApplication.set(state.runningApplications.first!).then { app in
                expect(app).to(equal(state.runningApplications.first!))
              }
            }
          }

//          context("when the system does not change the frontmost application") {
//            it("returns the old value in the promise") { () -> Promise<Void> in
//
//            }
//          }

        }
      }

    }

  }
}
