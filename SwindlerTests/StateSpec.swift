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

class OSXStateDelegateSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplicationElement.allApps = [] }
    beforeEach { FakeObserver.observers = [] }

    func initialize(
      appObserver: ApplicationObserverType = StubApplicationObserver()
    ) -> OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver> {
      let stateDel = OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver>(appObserver: appObserver)
      waitUntil { done in
        stateDel.frontmostApplication.initialized.then { done() }
      }
      return stateDel
    }

    context("during initialization") {
      func initializeUsingObserver<Obs: ObserverType>(elementObserver: Obs.Type)
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
        let _ = initializeUsingObserver(MyTestObserver.self)

        expect(MyTestObserver.numObservers).to(equal(2), description: "should be 2 observers")
      }

      it("handles applications that cannot be watched") {
        class MyTestObserver: TestObserver {
          override private func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {
            throw AXSwift.Error.CannotComplete
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement()]
        let _ = initializeUsingObserver(MyTestObserver.self)
        // test that it doesn't crash
      }

    }

    xit("doesn't leak memory") {
      weak var stateDelegate = initialize()
      expect(stateDelegate).toEventually(beNil())
    }

    context("when there is an application") {
      beforeEach { TestApplicationElement.allApps = [TestApplicationElement()] }

      xit("doesn't leak memory") {
        weak var stateDelegate = initialize()

        // For some reason when `stateDelegate` is captured in an autoclosure, it prevents the object from
        // being freed until the closure is freed. This explicit closure avoids that issue.
        func isNil() -> Bool {
          return stateDelegate == nil
        }
        expect(isNil()).toEventually(beTrue())
      }
    }

    describe("runningApplications") {
      context("after initialization") {
        beforeEach { TestApplicationElement.allApps = [TestApplicationElement()] }

        it("contains the running applications") {
          let stateDelegate = initialize()
          expect(stateDelegate.runningApplications).toEventually(haveCount(1))
        }
      }
    }

    describe("frontmostApplication") {
      func initializeWithApp(
        appObserver appObserver: ApplicationObserverType = FakeApplicationObserver()
      ) -> OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver> {
        let appElement = TestApplicationElement()
        appElement.processID = 1234
        TestApplicationElement.allApps = [appElement]

        let stateDelegate = initialize(appObserver)
        waitUntil(stateDelegate.runningApplications.count == 1)
        return stateDelegate
      }

      func getPID(app: Swindler.Application?) -> pid_t? {
        typealias AppDelegate = OSXApplicationDelegate<TestUIElement, TestApplicationElement, TestObserver>
        return (app?.delegate as! AppDelegate?)?.processID
      }

      context("when there is no frontmost application") {
        it("is nil") { () -> Promise<Void> in
          let stateDelegate = initialize()
          return stateDelegate.frontmostApplication.initialized.then {
            expect(stateDelegate.frontmostApplication.value).to(beNil())
          }
        }
      }

      context("when there is a frontmost application") {
        it("contains the frontmost application") { () -> Promise<Void> in
          let appObserver = FakeApplicationObserver()
          appObserver.setFrontmost(1234)
          let stateDelegate = initializeWithApp(appObserver: appObserver)
          return stateDelegate.frontmostApplication.initialized.then {
            expect(getPID(stateDelegate.frontmostApplication.value)).to(equal(1234))
          }
        }
      }

      context("when the frontmost application changes") {
        it("updates") {
          let appObserver = FakeApplicationObserver()
          let stateDelegate = initializeWithApp(appObserver: appObserver)
          expect(stateDelegate.frontmostApplication.value).to(beNil())
          appObserver.setFrontmost(1234)
          expect(getPID(stateDelegate.frontmostApplication.value)).toEventually(equal(1234))
        }
      }

      context("when set to an application") {

        it("makes that application frontmost") {
          let appObserver = FakeApplicationObserver()
          let state = State(delegate: initializeWithApp(appObserver: appObserver))
          expect(state.frontmostApplication.value).to(beNil())
          state.frontmostApplication.set(state.runningApplications.first!)
          expect(appObserver.frontmostApplicationPID).toEventually(equal(1234))
        }

        context("when the system complies") {

          it("returns the app in the promise") { () -> Promise<Void> in
            let state = State(delegate: initializeWithApp())
            return state.frontmostApplication.set(state.runningApplications.first!).then { app in
              expect(app).to(equal(state.runningApplications.first!))
            }
          }

//          pending("emits a FrontmostApplicationChangedEvent") {
//            // Need to be able to pass in a TestNotifier to test this (ideally).
//          }

        }

        context("when the system does not change the frontmost application") {
          it("returns the old value in the promise") { () -> Promise<Void> in
            let state = State(delegate: initializeWithApp(appObserver: StubApplicationObserver()))
            return state.frontmostApplication.set(state.runningApplications.first!).then { app in
              expect(app).to(beNil())
            }
          }
        }

      }
    }

  }
}
