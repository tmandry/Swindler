import Cocoa
import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

/// Tests that integrate the whole OS X driver instead of testing just one piece.
class OSXDriverSpec: QuickSpec {
    override func spec() {

        // Set up a state with a single application containing a single window.
        var appElement: EmittingTestApplicationElement!
        var windowElement: EmittingTestWindowElement!
        var appObserver: FakeApplicationObserver!
        var state: State!
        beforeEach {
            appElement = EmittingTestApplicationElement()
            windowElement = EmittingTestWindowElement(forApp: appElement)
            windowElement.attrs[.position] = CGPoint(x: 5, y: 5)
            appElement.attrs[.windows] = [windowElement as TestUIElement]
            appElement.attrs[.mainWindow] = windowElement
            appObserver = FakeApplicationObserver()
            appObserver.allApps = [appElement]

            let notifier = EventNotifier()
            let screenDel = FakeSystemScreenDelegate(screens: [FakeScreen().delegate])
            let spaces = OSXSpaceObserver(notifier, screenDel, FakeSystemSpaceTracker())
            state = State(delegate: OSXStateDelegate<
                TestUIElement, EmittingTestApplicationElement, FakeObserver, FakeApplicationObserver
            >(notifier, appObserver, screenDel, spaces))
            appElement.addWindow(windowElement)
            expect(state.knownWindows.count).toEventually(equal(1))
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
                expect(state.knownWindows.first!.application)
                    .to(equal(state.runningApplications.first!))
            }

            it("emits WindowCreatedEvent") {
                var callbacks = 0
                state.on { (_: WindowCreatedEvent) in
                    callbacks += 1
                }
                let window = EmittingTestWindowElement(forApp: appElement)
                appElement.addWindow(window)
                expect(state.knownWindows).toEventually(haveCount(2))
                expect(callbacks).to(equal(1), description: "callback should be called once")
            }

        }

        context("when a window is destroyed") {

            it("emits WindowDestroyedEvent") {
                var callbacks = 0
                state.on { (_: WindowDestroyedEvent) in
                    callbacks += 1
                }
                windowElement.destroy()
                expect(callbacks)
                    .toEventually(equal(1), description: "callback should be called once")
            }

            it("removes the window from knownWindows") {
                windowElement.destroy()
                expect(state.knownWindows).toEventually(haveCount(0))
            }

        }

        context("when a window property changes") {

            it("emits a ChangedEvent") {
                var callbacks = 0
                state.on { (_: WindowFrameChangedEvent) in
                    callbacks += 1
                }
                try! windowElement.setAttribute(.position, value: CGPoint(x: 100, y: 100))
                expect(callbacks)
                    .toEventually(equal(1), description: "callback should be called once")
            }

            it("calls multiple event handlers") {
                var callbacks1 = 0
                var callbacks2 = 0
                state.on { (_: WindowFrameChangedEvent) in
                    callbacks1 += 1
                }
                state.on { (_: WindowFrameChangedEvent) in
                    callbacks2 += 1
                }
                try! windowElement.setAttribute(.position, value: CGPoint(x: 100, y: 100))
                expect(callbacks1)
                    .toEventually(equal(1), description: "callback1 should be called once")
                expect(callbacks2)
                    .toEventually(equal(1), description: "callback2 should be called once")
            }

        }

    }
}
