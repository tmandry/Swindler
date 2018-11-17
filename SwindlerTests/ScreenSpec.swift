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

class OSXSystemScreenDelegateSpec: QuickSpec {
    override func spec() {

        describe("handleScreenChange") {

            var screen1: OSXScreenDelegate<StubNSScreen>!
            var screen2: OSXScreenDelegate<StubNSScreen>!
            beforeEach {
                screen1 = OSXScreenDelegate(nsScreen: StubNSScreen(1))
                screen2 = OSXScreenDelegate(nsScreen: StubNSScreen(2))
            }

            context("when nothing changes") {
                it("is handled") {
                    let event = handleScreenChange(
                        newScreens: [screen1],
                        oldScreens: [screen1]
                    )
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(0))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.unchangedScreens.first)
                        .to(equal(Screen(delegate: screen1)))
                }
            }

            context("when a screen is added") {
                it("is handled") {
                    let event = handleScreenChange(
                        newScreens: [screen1, screen2],
                        oldScreens: [screen1]
                    )
                    expect(event.addedScreens).to(haveCount(1))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(0))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.addedScreens.first).to(equal(Screen(delegate: screen2)))
                }
            }

            context("when a screen is removed") {
                it("is handled") {
                    let event = handleScreenChange(
                        newScreens: [screen1],
                        oldScreens: [screen1, screen2]
                    )
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(1))
                    expect(event.changedScreens).to(haveCount(0))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.removedScreens.first).to(equal(Screen(delegate: screen2)))
                }
            }

            context("when a screen is resized") {
                it("is marked as changed") {
                    var oldNSScreen = StubNSScreen(1)
                    oldNSScreen.frame = CGRect(x: 0, y: 0, width: 1280, height: 1080)
                    let event = handleScreenChange(
                        newScreens: [screen1],
                        oldScreens: [OSXScreenDelegate(nsScreen: oldNSScreen)]
                    )
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(1))
                    expect(event.unchangedScreens).to(haveCount(0))
                    expect(event.changedScreens.first).to(equal(Screen(delegate: screen1)))
                }
            }

            context("when a screen is moved") {
                it("is marked as changed") {
                    var oldNSScreen1 = StubNSScreen(1)
                    oldNSScreen1.frame = CGRect(x: 0, y: -100, width: 1024, height: 768)
                    let event = handleScreenChange(
                        newScreens: [screen1, screen2],
                        oldScreens: [OSXScreenDelegate(nsScreen: oldNSScreen1), screen2]
                    )
                    expect(event.addedScreens).to(haveCount(0))
                    expect(event.removedScreens).to(haveCount(0))
                    expect(event.changedScreens).to(haveCount(1))
                    expect(event.unchangedScreens).to(haveCount(1))
                    expect(event.changedScreens.first).to(equal(Screen(delegate: screen1)))
                }
            }

        }

    }
}
