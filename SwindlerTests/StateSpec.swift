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
}

class FakeApplicationObserver: ApplicationObserverType {
    private var frontmost_: pid_t?
    var frontmostApplicationPID: pid_t? { return frontmost_ }

    private var frontmostHandlers: [() -> Void] = []
    func onFrontmostApplicationChanged(_ handler: @escaping () -> Void) {
        frontmostHandlers.append(handler)
    }

    private var launchHandlers: [(pid_t) -> Void] = []
    func onApplicationLaunched(_ handler: @escaping (pid_t) -> Void) {
        launchHandlers.append(handler)
    }

    private var terminateHandlers: [(pid_t) -> Void] = []
    func onApplicationTerminated(_ handler: @escaping (pid_t) -> Void) {
        terminateHandlers.append(handler)
    }

    func makeApplicationFrontmost(_ pid: pid_t) throws {
        setFrontmost(pid)
    }

    fileprivate func setFrontmost(_ pid: pid_t?) {
        frontmost_ = pid
        frontmostHandlers.forEach { $0() }
    }
    fileprivate func launch(_ pid: pid_t) {
        launchHandlers.forEach { $0(pid) }
    }
    fileprivate func terminate(_ pid: pid_t) {
        terminateHandlers.forEach { $0(pid) }
    }
}

class OSXStateDelegateSpec: QuickSpec {
    override func spec() {

        beforeEach { TestApplicationElement.allApps = [] }
        beforeEach { FakeObserver.observers = [] }

        func initialize(
            _ appObserver: ApplicationObserverType = StubApplicationObserver()
        ) -> OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver> {
            let screenDel = FakeSystemScreenDelegate(screens: [FakeScreen().delegate])
            let stateDel = OSXStateDelegate<
                TestUIElement, TestApplicationElement, TestObserver
            >(appObserver: appObserver, screens: screenDel)
            waitUntil { done in
                stateDel.frontmostApplication.initialized.done { done() }.cauterize()
            }
            return stateDel
        }

        func initializeWithApp(
            appObserver: ApplicationObserverType = FakeApplicationObserver()
        ) -> OSXStateDelegate<TestUIElement, TestApplicationElement, TestObserver> {
            let appElement = TestApplicationElement()
            appElement.processID = 1234
            TestApplicationElement.allApps = [appElement]

            let stateDelegate = initialize(appObserver)
            waitUntil(stateDelegate.runningApplications.count == 1)
            return stateDelegate
        }

        context("during initialization") {
            func initializeUsingObserver<Obs: ObserverType>(_ elementObserver: Obs.Type)
                -> OSXStateDelegate<TestUIElement, TestApplicationElement, Obs> {
                let screenDel = FakeSystemScreenDelegate(screens: [FakeScreen().delegate])
                return OSXStateDelegate<TestUIElement, TestApplicationElement, Obs>(
                    appObserver: StubApplicationObserver(),
                    screens: screenDel
                )
            }

            it("observes all applications") {
                class MyTestObserver: TestObserver {
                    static var numObservers: Int = 0
                    required init(processID: pid_t, callback: @escaping Callback) throws {
                        MyTestObserver.numObservers += 1
                        try super.init(processID: processID, callback: callback)
                    }
                }

                TestApplicationElement.allApps = [TestApplicationElement(),
                                                  TestApplicationElement()]
                _ = initializeUsingObserver(MyTestObserver.self)

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

                TestApplicationElement.allApps = [TestApplicationElement()]
                _ = initializeUsingObserver(MyTestObserver.self)
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
                beforeEach { TestApplicationElement.allApps = [TestApplicationElement()] }

                it("contains the running applications") {
                    let stateDelegate = initialize()
                    expect(stateDelegate.runningApplications).toEventually(haveCount(1))
                }

                context("when a new application launches") {
                    it("includes the new application") {
                        let appObserver = FakeApplicationObserver()
                        let stateDelegate = initializeWithApp(appObserver: appObserver)
                        waitUntil(stateDelegate.runningApplications.count == 1)

                        let newApp = TestApplicationElement()
                        TestApplicationElement.allApps.append(newApp)
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

                        let newApp = TestApplicationElement()
                        TestApplicationElement.allApps.append(newApp)
                        appObserver.launch(newApp.processID)

                        expect(count).toEventually(equal(1))
                    }
                }

                context("when an application terminates") {
                    it("is removed from the list") {
                        let appObserver = FakeApplicationObserver()
                        let stateDelegate = initializeWithApp(appObserver: appObserver)
                        waitUntil(stateDelegate.runningApplications.count == 1)

                        let app = TestApplicationElement.allApps[0]
                        TestApplicationElement.allApps = []
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

                    let app = TestApplicationElement.allApps[0]
                    TestApplicationElement.allApps = []
                    appObserver.terminate(app.processID)

                    expect(count).toEventually(equal(1))
                }
            }
        }

        describe("frontmostApplication") {
            func getPID(_ app: Swindler.Application?) -> pid_t? {
                typealias AppDelegate = OSXApplicationDelegate<
                    TestUIElement, TestApplicationElement, TestObserver
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
                        let state = State(
                            delegate: initializeWithApp(appObserver: StubApplicationObserver())
                        )
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
