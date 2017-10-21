import Quick
import Nimble

@testable import Swindler

struct StubNSScreen: NSScreenType {
    var frame: CGRect
    var visibleFrame: CGRect { return frame }
    var deviceDescription: [NSDeviceDescriptionKey: Any] {
        return [
            NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: number as Int32)
        ]
    }

    var displayName: String

    fileprivate var number: Int32

    init(_ number: Int32 = 1) {
        frame = CGRect(x: Int((number - 1) * 1024), y: 0, width: 1024, height: 768)
        self.number = number
        displayName = "StubNSScreen\(number)"
    }
}

public func ==<NSScreenT>(lhs: OSXScreenDelegate<NSScreenT>, rhs: OSXScreenDelegate<NSScreenT>)
-> Bool {
    return lhs.equalTo(rhs)
}
extension OSXScreenDelegate: Equatable {}

class OSXScreenDelegateSpec: QuickSpec {
    override func spec() {

        describe("handleScreenChange") {

            var nsScreen1: StubNSScreen!
            var nsScreen2: StubNSScreen!
            var screenDelegate1: OSXScreenDelegate<StubNSScreen>!
            var screenDelegate2: OSXScreenDelegate<StubNSScreen>!
            beforeEach {
                nsScreen1 = StubNSScreen(1)
                nsScreen2 = StubNSScreen(2)
                screenDelegate1 = OSXScreenDelegate(nsScreen: nsScreen1)
                screenDelegate2 = OSXScreenDelegate(nsScreen: nsScreen2)
            }

            context("when nothing changes") {
                it("is handled") {
                    let state = State(delegate: StubStateDelegate())
                    let (screens, event) = OSXScreenDelegate<StubNSScreen>.handleScreenChange(
                        newScreens: [nsScreen1],
                        oldScreens: [screenDelegate1],
                        state: state
                    )
                    expect(screens).to(haveCount(1))
                    expect(screens.first).to(equal(screenDelegate1))
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(0))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.unchangedScreens.first)
                        .to(equal(Screen(delegate: screenDelegate1)))
                }
            }

            context("when a screen is added") {
                it("is handled") {
                    let state = State(delegate: StubStateDelegate())
                    let (screens, event) = OSXScreenDelegate<StubNSScreen>.handleScreenChange(
                        newScreens: [nsScreen1, nsScreen2],
                        oldScreens: [screenDelegate1],
                        state: state
                    )
                    expect(screens).to(haveCount(2))
                    expect(screens.filter { $0.equalTo(screenDelegate2) }).to(haveCount(1))
                    expect(event.addedScreens).to(haveCount(1))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(0))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.addedScreens.first).to(equal(Screen(delegate: screenDelegate2)))
                }
            }

            context("when a screen is removed") {
                it("is handled") {
                    let state = State(delegate: StubStateDelegate())
                    let (screens, event) = OSXScreenDelegate<StubNSScreen>.handleScreenChange(
                        newScreens: [nsScreen1],
                        oldScreens: [screenDelegate1, screenDelegate2],
                        state: state
                    )
                    expect(screens).to(haveCount(1))
                    expect(screens.first).to(equal(screenDelegate1))
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(1))
                    expect(event.changedScreens).to(haveCount(0))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.removedScreens.first).to(equal(Screen(delegate: screenDelegate2)))
                }
            }

            context("when a screen is resized") {
                it("is marked as changed") {
                    let state = State(delegate: StubStateDelegate())
                    var oldNSScreen = StubNSScreen(1)
                    oldNSScreen.frame = CGRect(x: 0, y: 0, width: 1280, height: 1080)
                    let (screens, event) = OSXScreenDelegate<StubNSScreen>.handleScreenChange(
                        newScreens: [nsScreen1],
                        oldScreens: [OSXScreenDelegate(nsScreen: oldNSScreen)],
                        state: state
                    )
                    expect(screens).to(haveCount(1))
                    expect(screens.first).to(equal(screenDelegate1))
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(1))
                    expect(event.unchangedScreens).to(haveCount(0))
                    expect(event.changedScreens.first).to(equal(Screen(delegate: screenDelegate1)))
                }
            }

            context("when a screen is moved") {
                it("is marked as changed") {
                    let state = State(delegate: StubStateDelegate())
                    var oldNSScreen1 = StubNSScreen(1)
                    oldNSScreen1.frame = CGRect(x: 0, y: -100, width: 1024, height: 768)
                    let (screens, event) = OSXScreenDelegate<StubNSScreen>.handleScreenChange(
                        newScreens: [nsScreen1, nsScreen2],
                        oldScreens: [OSXScreenDelegate(nsScreen: oldNSScreen1), screenDelegate2],
                        state: state
                    )
                    expect(screens).to(haveCount(2))
                    expect(screens.first).to(equal(screenDelegate1))
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(1))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.changedScreens.first).to(equal(Screen(delegate: screenDelegate1)))
                }
            }

        }

    }
}
