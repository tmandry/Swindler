import Foundation
import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class StubApplicationObserver: ApplicationObserverType {
    var frontmostApplicationPID: pid_t? { return nil }
    func onFrontmostApplicationChanged(_ handler: @escaping () -> Void) {}
    func onApplicationLaunched(_ handler: @escaping (pid_t) -> Void) {}
    func onApplicationTerminated(_ handler: @escaping (pid_t) -> Void) {}
    func makeApplicationFrontmost(_ pid: pid_t) throws {}

    typealias ApplicationElement = TestApplicationElement
    var allApps: [ApplicationElement] = []
    func allApplications() -> [TestApplicationElement] { return allApps }
    func appElement(forProcessID processID: pid_t) -> ApplicationElement? { return nil }
}

class OSXStateDelegateSpec: QuickSpec {
    override func spec() {

        func initialize()
        -> OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver, StubApplicationObserver> {
            initialize(StubApplicationObserver())
        }

        func initialize<AppObserver: ApplicationObserverType>(
            _ appObserver: AppObserver
        ) -> OSXStateDelegate<TestUIElement, AppObserver.ApplicationElement, TestObserver, AppObserver> {
            let notifier = EventNotifier()
            let screenDel = FakeSystemScreenDelegate(screens: [FakeScreen().delegate])
            let spaces = OSXSpaceObserver(notifier, screenDel, FakeSystemSpaceTracker())
            let stateDel = OSXStateDelegate<
                TestUIElement, AppObserver.ApplicationElement, TestObserver, AppObserver
            >(notifier, appObserver, screenDel, spaces)
            waitUntil { done in
                stateDel.frontmostApplication.initialized.done { done() }.cauterize()
            }
            return stateDel
        }

        func initializeWithApp(
            appObserver: FakeApplicationObserver = FakeApplicationObserver()
        ) -> OSXStateDelegate<TestUIElement, EmittingTestApplicationElement, TestObserver, FakeApplicationObserver> {
            let appElement = EmittingTestApplicationElement()
            appElement.processID = 1234
            appObserver.allApps = [appElement]
            let stateDelegate = initialize(appObserver)
            return stateDelegate
        }

        func initializeWithApps(
            _ apps: [EmittingTestApplicationElement],
            appObserver: FakeApplicationObserver = FakeApplicationObserver()
        ) -> OSXStateDelegate<TestUIElement, EmittingTestApplicationElement, TestObserver, FakeApplicationObserver> {
            appObserver.allApps = apps
            return initialize(appObserver)
        }

        context("during initialization") {
            func initializeUsingObserver<Obs: ObserverType>(
                _ elementObserver: Obs.Type,
                apps: [TestApplicationElement]
            )
                -> OSXStateDelegate<TestUIElement, TestApplicationElement, Obs, StubApplicationObserver>
            {
                let notifier = EventNotifier()
                let screenDel = FakeSystemScreenDelegate(screens: [FakeScreen().delegate])
                let observer = StubApplicationObserver()
                let spaces = OSXSpaceObserver(notifier, screenDel, FakeSystemSpaceTracker())
                observer.allApps = apps
                return OSXStateDelegate(notifier, observer, screenDel, spaces)
            }

            it("observes all applications") {
                class MyTestObserver: TestObserver {
                    static var numObservers: Int = 0
                    required init(processID: pid_t, callback: @escaping Callback) throws {
                        MyTestObserver.numObservers += 1
                        try super.init(processID: processID, callback: callback)
                    }
                }

                _ = initializeUsingObserver(
                    MyTestObserver.self,
                    apps: [TestApplicationElement(), TestApplicationElement()])

                expect(MyTestObserver.numObservers)
                    .to(equal(2), description: "should be 2 observers")
            }

            it("handles applications that cannot be watched") {
                class MyTestObserver: TestObserver {
                    fileprivate override func addNotification(_ notification: AXNotification,
                                                              forElement: TestUIElement) throws {
                        throw AXError.cannotComplete
                    }
                }

                _ = initializeUsingObserver(MyTestObserver.self, apps: [TestApplicationElement()])
                // test that it doesn't crash
            }

        }

        xit("doesn't leak memory") {
            weak var stateDelegate = initialize()
            expect(stateDelegate).toEventually(beNil())
        }

        context("when there is an application") {
            xit("doesn't leak memory") {
                weak var stateDelegate = initializeWithApp()

                // For some reason when `stateDelegate` is captured in an autoclosure, it prevents
                // the object from being freed until the closure is freed. This explicit closure
                // avoids that issue.
                func isNil() -> Bool {
                    return stateDelegate == nil
                }
                expect(isNil()).toEventually(beTrue())
            }
        }

        describe("runningApplications") {
            context("after initialization") {
                it("contains the running applications") {
                    let stateDelegate = initializeWithApp()
                    expect(stateDelegate.runningApplications).toEventually(haveCount(1))
                }

                context("when a new application launches") {
                    it("includes the new application") {
                        let appObserver = FakeApplicationObserver()
                        let stateDelegate = initializeWithApp(appObserver: appObserver)
                        waitUntil(stateDelegate.runningApplications.count == 1)

                        let newApp = EmittingTestApplicationElement()
                        appObserver.allApps.append(newApp)
                        appObserver.launch(newApp.processID)

                        expect(stateDelegate.runningApplications).toEventually(haveCount(2))
                    }

                    it("emits an event") {
                        let appObserver = FakeApplicationObserver()
                        let stateDelegate = initializeWithApp(appObserver: appObserver)
                        waitUntil(stateDelegate.runningApplications.count == 1)
                        var count = 0
                        stateDelegate.notifier.on { (_: ApplicationLaunchedEvent) in
                            count += 1
                        }

                        let newApp = EmittingTestApplicationElement()
                        appObserver.allApps.append(newApp)
                        appObserver.launch(newApp.processID)

                        expect(count).toEventually(equal(1))
                    }
                }

                context("when an application terminates") {
                    it("is removed from the list") {
                        let appObserver = FakeApplicationObserver()
                        let stateDelegate = initializeWithApp(appObserver: appObserver)
                        waitUntil(stateDelegate.runningApplications.count == 1)

                        let app = appObserver.allApps[0]
                        appObserver.allApps = []
                        appObserver.terminate(app.processID)

                        expect(stateDelegate.runningApplications).toEventually(haveCount(0))
                    }
                }

                it("emits an event") {
                    let appObserver = FakeApplicationObserver()
                    let stateDelegate = initializeWithApp(appObserver: appObserver)
                    waitUntil(stateDelegate.runningApplications.count == 1)
                    var count = 0
                    stateDelegate.notifier.on { (_: ApplicationTerminatedEvent) in
                        count += 1
                    }

                    let app = appObserver.allApps[0]
                    appObserver.allApps = []
                    appObserver.terminate(app.processID)

                    expect(count).toEventually(equal(1))
                }
            }
        }

        describe("frontmostApplication") {
            func getPID(_ app: Swindler.Application?) -> pid_t? {
                typealias AppDelegate = OSXApplicationDelegate<
                    TestUIElement, EmittingTestApplicationElement, TestObserver
                >
                return (app?.delegate as! AppDelegate?)?.processIdentifier
            }

            context("when there is no frontmost application") {
                it("is nil") { () -> Promise<Void> in
                    let stateDelegate = initialize()
                    return stateDelegate.frontmostApplication.initialized.done {
                        expect(stateDelegate.frontmostApplication.value).to(beNil())
                    }
                }
            }

            context("when there is a frontmost application") {
                it("contains the frontmost application") { () -> Promise<Void> in
                    let appObserver = FakeApplicationObserver()
                    appObserver.setFrontmost(1234)
                    let stateDelegate = initializeWithApp(appObserver: appObserver)
                    return stateDelegate.frontmostApplication.initialized.done {
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
                    expect(getPID(stateDelegate.frontmostApplication.value))
                        .toEventually(equal(1234))
                }
            }

            context("when set to an application") {

                it("makes that application frontmost") {
                    let appObserver = FakeApplicationObserver()
                    let state = State(delegate: initializeWithApp(appObserver: appObserver))
                    expect(state.frontmostApplication.value).to(beNil())
                    state.frontmostApplication.set(state.runningApplications.first!).cauterize()
                    expect(appObserver.frontmostApplicationPID).toEventually(equal(1234))
                }

                context("when the system complies") {

                    it("returns the app in the promise") { () -> Promise<Void> in
                        let state = State(delegate: initializeWithApp())
                        return state.frontmostApplication.set(state.runningApplications.first!)
                            .done { app in
                                expect(app).to(equal(state.runningApplications.first!))
                            }
                    }

                    // pending("emits a FrontmostApplicationChangedEvent") {
                    //     // Need to be able to pass in a TestNotifier to test this (ideally).
                    // }

                }

                context("when the system does not change the frontmost application") {
                    it("returns the old value in the promise") { () -> Promise<Void> in
                        let appObserver = StubApplicationObserver()
                        appObserver.allApps = [TestApplicationElement()]
                        let state = State(delegate: initialize(appObserver))
                        return state.frontmostApplication.set(state.runningApplications.first!)
                            .done { app in
                                expect(app).to(beNil())
                            }
                    }
                }

            }
        }

    }
}
