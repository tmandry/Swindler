import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

// The window delegate holds a weak reference to the app delegate, so we use this singleton to
// ensure it doesn't get destroyed. Same for app -> state. See #3.
private let stubApplicationDelegate = StubApplicationDelegate()

class OSXWindowDelegateInitializeSpec: QuickSpec {
    override func spec() {

        typealias WinDelegate = OSXWindowDelegate<
            TestUIElement, TestApplicationElement, TestObserver
        >

        var windowElement: TestWindowElement!
        beforeEach {
            TestApplicationElement.allApps = []
            windowElement = TestWindowElement(forApp: TestApplicationElement())
        }

        func initializeWithElement(_ winElement: TestWindowElement) -> Promise<WinDelegate> {
            let screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
            let systemScreens = FakeSystemScreenDelegate(screens: [screen.delegate])
            return WinDelegate.initialize(appDelegate: stubApplicationDelegate,
                                          notifier: TestNotifier(),
                                          axElement: winElement,
                                          observer: TestObserver(),
                                          systemScreens: systemScreens)
        }

        func initialize() -> Promise<WinDelegate> {
            return initializeWithElement(windowElement)
        }

        it("doesn't leak memory") {
            weak var windowDelegate: WinDelegate?
            waitUntil { done in
                initialize().done { delegate in
                    windowDelegate = delegate
                    done()
                }.cauterize()
            }
            expect(windowDelegate).to(beNil())
        }

        describe("initialize") {

            it("initializes window properties") { () -> Promise<Void> in
                windowElement.attrs[.position] = CGPoint(x: 5, y: 5)
                windowElement.attrs[.size] = CGSize(width: 100, height: 100)
                windowElement.attrs[.title] = "a window title"
                windowElement.attrs[.minimized] = false
                windowElement.attrs[.fullScreen] = false

                return initialize().done { windowDelegate in
                    // In inverted (AX) coordinates, top-left is (5, 5) and bottom-left is (5, 105)
                    // In Cocoa coordinates, the bottom-left would be (5, 1000 - 105) = (5, 895)
                    expect(windowDelegate.frame.value.origin) == CGPoint(x: 5, y: 895)
                    expect(windowDelegate.frame.value.size) == CGSize(width: 100, height: 100)
                    expect(windowDelegate.size.value) == CGSize(width: 100, height: 100)
                    expect(windowDelegate.title.value) == "a window title"
                    expect(windowDelegate.isMinimized.value).to(beFalse())
                    expect(windowDelegate.isFullscreen.value).to(beFalse())
                }
            }

            it("stores the ApplicationDelegate in appDelegate") { () -> Promise<Void> in
                initialize().done { winDelegate in
                    expect(winDelegate.appDelegate === stubApplicationDelegate).to(beTrue())
                }
            }

            it("marks the window as valid") { () -> Promise<Void> in
                initialize().done { windowDelegate in
                    expect(windowDelegate.isValid).to(beTrue())
                }
            }

            context("when called with a window that is missing attributes") {
                it("returns an error") { () -> Promise<Void> in
                    windowElement.attrs.removeValue(forKey: .frame)

                    // TODO: put the detailed error back, or take out the error class
                    let expectedError = PropertyError.invalidObject(
                        cause: PropertyError.missingValue
                    )
                    return expectToFail(initialize(), with: expectedError)
                }
            }

            context("when called with a window whose subrole is AXUnknown") {
                // AXUnknown is undocumented as a subrole, but very important!
                it("returns an error") { () -> Promise<Void> in
                    windowElement.attrs[.subrole] = "AXUnknown"
                    return expectToFail(initialize())
                }
            }

        }

        describe("Window equality") {

            it("returns true for identical WindowDelegates") { () -> Promise<Void> in
                initialize().done { windowDelegate in
                    expect(Window(delegate: windowDelegate))
                        .to(equal(Window(delegate: windowDelegate)))
                }
            }

            it("returns false for different WindowDelegates") { () -> Promise<Void> in
                initialize().then { windowDelegate1 -> Promise<Void> in
                    let windowElement2 = TestWindowElement(forApp: TestApplicationElement())
                    return initializeWithElement(windowElement2).done { windowDelegate2 in
                        expect(Window(delegate: windowDelegate1))
                            .toNot(equal(Window(delegate: windowDelegate2)))
                    }
                }
            }

        }

    }
}

class OSXWindowDelegateNotificationSpec: QuickSpec {
    override func spec() {

        describe("AXUIElement notifications") {
            beforeEach { AdversaryObserver.reset() }

            // Because observers only have one callback per application, they are owned by the
            // application delegate and window notifications are forwarded on, so to fully test this
            // we have to test the interaction between the two.

            typealias AppDelegate = OSXApplicationDelegate<
                TestUIElement, TestApplicationElement, AdversaryObserver
            >
            typealias WinDelegate = OSXWindowDelegate<
                TestUIElement, TestApplicationElement, AdversaryObserver
            >

            var appElement: TestApplicationElement!
            var windowElement: AdversaryWindowElement!
            beforeEach {
                appElement = TestApplicationElement()
                windowElement = AdversaryWindowElement(forApp: appElement)
                appElement.windows.append(windowElement)
            }

            var observer: AdversaryObserver!
            func initialize() -> Promise<WinDelegate> {
                return AppDelegate
                    .initialize(axElement: appElement,
                                stateDelegate: StubStateDelegate(),
                                notifier: TestNotifier())
                    .map { appDelegate -> WinDelegate in
                        observer = appDelegate.observer
                        guard let winDelegate = appDelegate.knownWindows.first
                                                as! WinDelegate? else {
                            throw TestError("Window delegate was not initialized by application "
                                          + "delegate")
                        }
                        return winDelegate
                    }
            }

            xcontext("when a property value changes right before observing it") {
                it("is read correctly") { () -> Promise<Void> in
                    windowElement.attrs[.minimized] = false

                    AdversaryObserver.onAddNotification(.windowMiniaturized) { _ in
                        windowElement.attrs[.minimized] = true
                    }

                    return initialize().done { winDelegate in
                        expect(winDelegate.isMinimized.value).toEventually(beTrue())
                    }
                }
            }

            xcontext("when a property value changes right after observing it") {
                // The difference between a property changing before or after observing is simply
                // whether an event is emitted or not.
                it("is updated correctly") { () -> Promise<Void> in
                    windowElement.attrs[.minimized] = false

                    AdversaryObserver.onAddNotification(.windowMiniaturized) { observer in
                        observer.emit(.windowMiniaturized, forElement: windowElement)
                        DispatchQueue.main.async() {
                            windowElement.attrs[.minimized] = true
                        }
                    }

                    return initialize().done { winDelegate in
                        expect(winDelegate.isMinimized.value).toEventually(beTrue())
                    }
                }
            }

            xcontext("when a property value changes right after reading it") {
                it("is updated correctly") { () -> Promise<Void> in
                    windowElement.attrs[.minimized] = false

                    var observer: AdversaryObserver?
                    AdversaryObserver.onAddNotification(.windowMiniaturized) { obs in
                        observer = obs
                    }
                    windowElement.onAttributeFirstRead(.minimized) {
                        windowElement.attrs[.minimized] = true
                        observer?.emit(.windowMiniaturized, forElement: windowElement)
                    }

                    return initialize().done { winDelegate in
                        expect(winDelegate.isMinimized.value).toEventually(beTrue())
                    }
                }
            }

        }

    }
}

class OSXWindowDelegateSpec: QuickSpec {
    override func spec() {

        typealias WinDelegate = OSXWindowDelegate<
            TestUIElement, TestApplicationElement, TestObserver
        >

        var windowElement: TestWindowElement!
        var windowDelegate: WinDelegate!
        var notifier: TestNotifier!
        beforeEach {
            windowElement = TestWindowElement(forApp: TestApplicationElement())
            windowElement.attrs[.position] = CGPoint(x: 0, y: 0)
            windowElement.attrs[.size]     = CGSize(width: 100, height: 100)
            windowElement.attrs[.title]    = "a window"

            notifier = TestNotifier()
            waitUntil { done in
                let screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
                let systemScreens = FakeSystemScreenDelegate(screens: [screen.delegate])
                WinDelegate.initialize(
                    appDelegate: stubApplicationDelegate,
                    notifier: notifier,
                    axElement: windowElement,
                    observer: TestObserver(),
                    systemScreens: systemScreens
                ).done { winDelegate in
                    windowDelegate = winDelegate
                    done()
                }.cauterize()
            }
        }

        func getWindowElement(_ window: Window?) -> TestUIElement? {
            return ((window?.delegate) as! WinDelegate?)?.axElement
        }

        context("when a window is destroyed") {
            it("marks the window as invalid") {
                windowDelegate.handleEvent(.uiElementDestroyed, observer: TestObserver())
                expect(windowDelegate.isValid).toEventually(beFalse())
            }
        }

        context("when the position changes") {
            beforeEach {
                windowElement.attrs[.position] = CGPoint(x: 500, y: 500)
                windowDelegate.handleEvent(.moved, observer: TestObserver())
            }

            it("emits a WindowFrameChangedEvent") {
                if let event = notifier.expectEvent(WindowFrameChangedEvent.self) {
                    expect(getWindowElement(event.window)).to(equal(windowElement))
                }
            }

            it("marks the event as external") {
                if let event = notifier.waitUntilEvent(WindowFrameChangedEvent.self) {
                    expect(event.external).to(beTrue())
                }
            }
        }

        context("when the frame is set") {
            func setFrame(_ val: CGRect, inverted: CGPoint) {
                windowDelegate.frame.value = val
                expect(windowElement.attrs[.position] as? CGPoint).toEventually(equal(inverted))
                expect(windowElement.attrs[.size] as? CGSize).toEventually(equal(val.size))
                // Implementation note: sent by the system, but not used.
                windowDelegate.handleEvent(.moved, observer: TestObserver())
                windowDelegate.handleEvent(.resized, observer: TestObserver())
            }

            context("but only the position is changed") {
                beforeEach {
                    setFrame(CGRect(x: 500, y: 500, width: 100, height: 100),
                             inverted: CGPoint(x: 500, y: 400))
                }
                it("emits an internal WindowFrameChangedEvent") {
                    if let event = notifier.expectEvent(WindowFrameChangedEvent.self) {
                        expect(getWindowElement(event.window)).to(equal(windowElement))
                        expect(event.external).to(beFalse())
                    }
                }
            }

            context("but only the size is changed") {
                beforeEach {
                    setFrame(CGRect(x: 0, y: 800, width: 200, height: 200),
                             inverted: CGPoint(x: 0, y: 0))
                }
                it("emits an internal WindowFrameChangedEvent") {
                    if let event = notifier.expectEvent(WindowFrameChangedEvent.self) {
                        expect(getWindowElement(event.window)).to(equal(windowElement))
                        expect(event.external).to(beFalse())
                    }
                }
                it("immediately updates size") {
                    if let event = notifier.expectEvent(WindowFrameChangedEvent.self) {
                        expect(event.window.size.value) == event.window.frame.value.size
                    }
                }
            }

            context("and both position and size are changed") {
                beforeEach {
                    setFrame(CGRect(x: 500, y: 500, width: 200, height: 200),
                             inverted: CGPoint(x: 500, y: 300))
                }
                it("emits an internal WindowFrameChangedEvent") {
                    if let event = notifier.expectEvent(WindowFrameChangedEvent.self) {
                        expect(getWindowElement(event.window)).to(equal(windowElement))
                        expect(event.external).to(beFalse())
                    }
                }
                it("immediately updates size") {
                    if let event = notifier.expectEvent(WindowFrameChangedEvent.self) {
                        expect(event.window.size.value) == event.window.frame.value.size
                    }
                }
            }
        }

        describe("frame and size sync") {
            it("immediately updates size when frame is set") { () -> Promise<Void> in
                return windowDelegate
                    .frame
                    .set(CGRect(x: 500, y: 500, width: 200, height: 200))
                    .done { _ in
                        expect(windowDelegate.size.value) == windowDelegate.frame.value.size
                    }
            }

            it("immediately updates frame when size is set") { () -> Promise<Void> in
                return windowDelegate
                    .size
                    .set(CGSize(width: 200, height: 200))
                    .done { _ in
                        expect(windowDelegate.frame.value.size) == windowDelegate.size.value
                    }
            }
        }

        describe("property updates") {
            describe("title") {
                it("updates when the title changes") {
                    windowElement.attrs[.title] = "updated title"
                    windowDelegate.handleEvent(.titleChanged, observer: TestObserver())
                    expect(windowDelegate.title.value).toEventually(equal("updated title"))
                }
            }

            describe("position") {
                it("updates when the window is moved") {
                    expect(windowDelegate.frame.value.origin).to(equal(CGPoint(x: 0, y: 900)))
                    windowElement.attrs[.position] = CGPoint(x: 1, y: 1)
                    windowDelegate.handleEvent(.moved, observer: TestObserver())
                    expect(windowDelegate.frame.value.origin).toEventually(equal(CGPoint(x: 1, y: 899)))
                }

                it("updates when the window is resized from the top") {
                    windowElement.attrs[.position] = CGPoint(x: 0, y: 25)
                    windowElement.attrs[.size]     = CGSize(width: 100, height: 75)
                    // Somewhat surprisingly, no .moved event is produced when this happens.
                    windowDelegate.handleEvent(.resized, observer: TestObserver())
                    expect(windowDelegate.size.value).toEventually(equal(
                        CGSize(width: 100, height: 75)))
                    expect(windowDelegate.frame.value.origin).toEventually(equal(
                        CGPoint(x: 0, y: 900)))  // no change
                }

                it("updates when the window is resized from the bottom") {
                    windowElement.attrs[.position] = CGPoint(x: 0, y: 0)
                    windowElement.attrs[.size]     = CGSize(width: 100, height: 75)
                    windowDelegate.handleEvent(.resized, observer: TestObserver())
                    expect(windowDelegate.frame.value.origin).toEventually(equal(
                        CGPoint(x: 0, y: 925)))
                    expect(windowDelegate.size.value).toEventually(equal(
                        CGSize(width: 100, height: 75)))
                }
            }

            describe("frame") {
                it("updates when the window is moved") {
                    expect(windowDelegate.frame.value).to(equal(
                        CGRect(x: 0, y: 900, width: 100, height: 100)))
                    windowElement.attrs[.position] = CGPoint(x: 1, y: 1)
                    windowDelegate.handleEvent(.moved, observer: TestObserver())
                    expect(windowDelegate.frame.value).toEventually(equal(
                        CGRect(x: 1, y: 899, width: 100, height: 100)))
                }

                it("updates when the window is resized from the top") {
                    windowElement.attrs[.position] = CGPoint(x: 0, y: 25)
                    windowElement.attrs[.size]     = CGSize(width: 100, height: 75)
                    // Somewhat surprisingly, no .moved event is produced when this happens.
                    windowDelegate.handleEvent(.resized, observer: TestObserver())
                    expect(windowDelegate.frame.value).toEventually(equal(
                        CGRect(x: 0, y: 900, width: 100, height: 75)))
                }

                it("updates when the window is resized from the bottom") {
                    windowElement.attrs[.position] = CGPoint(x: 0, y: 0)
                    windowElement.attrs[.size]     = CGSize(width: 100, height: 75)
                    windowDelegate.handleEvent(.resized, observer: TestObserver())
                    expect(windowDelegate.frame.value).toEventually(equal(
                        CGRect(x: 0, y: 925, width: 100, height: 75)))
                }
            }

            describe("size") {
                it("updates when the window is resized") {
                    windowElement.attrs[.size] = CGSize(width: 123, height: 123)
                    windowDelegate.handleEvent(.resized, observer: TestObserver())
                    expect(windowDelegate.size.value)
                        .toEventually(equal(CGSize(width: 123, height: 123)))
                }
            }

            describe("isFullscreen") {
                it("updates when the window is resized") {
                    windowElement.attrs[.fullScreen] = true
                    windowDelegate.handleEvent(.resized, observer: TestObserver())
                    expect(windowDelegate.isFullscreen.value).toEventually(beTrue())
                }
            }

            describe("isMinimized") {
                it("updates when the window is minimized and restored") {
                    windowElement.attrs[.minimized] = true
                    windowDelegate.handleEvent(.windowMiniaturized, observer: TestObserver())
                    expect(windowDelegate.isMinimized.value).toEventually(beTrue())

                    windowElement.attrs[.minimized] = false
                    windowDelegate.handleEvent(.windowDeminiaturized, observer: TestObserver())
                    expect(windowDelegate.isMinimized.value).toEventually(beFalse())
                }
            }
        }

    }
}

class WindowSpec: QuickSpec {
    override func spec() {

        var state: State!
        var stateDelegate: StubStateDelegate!
        var window: Window!
        var windowDelegate: StubWindowDelegate!
        beforeEach {
            stateDelegate = StubStateDelegate()
            state = State(delegate: stateDelegate)
            let appDelegate = StubApplicationDelegate()
            let app = Application(delegate: appDelegate, stateDelegate: state.delegate)
            windowDelegate = StubWindowDelegate()
            window = Window(delegate: windowDelegate, application: app)

            stateDelegate.runningApplications = [app.delegate]
            appDelegate.knownWindows = [window.delegate]
        }

        describe("screen") {
            var leftScreen: Screen!
            var rightScreen: Screen!
            beforeEach {
                leftScreen = Screen(delegate: StubScreenDelegate(
                    frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)
                ))
                rightScreen = Screen(delegate: StubScreenDelegate(
                    frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000)
                ))
                stateDelegate.fakeScreens.screens = [leftScreen.delegate, rightScreen.delegate]
            }

            func setWindowRect(_ rect: CGRect) {
                windowDelegate.frame_.value = rect
                waitUntil { done in
                    windowDelegate.frame.refresh()
                        .done { _ in done() }
                        .cauterize()
                }
            }

            context("when the window is entirely on one screen") {
                it("returns that screen") {
                    setWindowRect(CGRect(x: 100, y: 100, width: 100, height: 100))
                    expect(window.screen).to(equal(leftScreen))
                    setWindowRect(CGRect(x: 1200, y: 100, width: 100, height: 100))
                    expect(window.screen).to(equal(rightScreen))
                }
            }

            context("when the window is entirely off screen") {
                it("returns nil") {
                    setWindowRect(CGRect(x: 100, y: 1100, width: 100, height: 100))
                    expect(window.screen).to(beNil())
                }
            }

            context("when the window is partly off screen but intersecting one screen") {
                it("returns that screen") {
                    setWindowRect(CGRect(x: 100, y: -50, width: 100, height: 100))
                    expect(window.screen).to(equal(leftScreen))
                }
            }

            context("when the window is on two screens") {
                it("returns the screen most of the window is on") {
                    setWindowRect(CGRect(x: 900, y: 100, width: 300, height: 100))
                    expect(window.screen).to(equal(rightScreen))
                }
            }
        }

    }
}
