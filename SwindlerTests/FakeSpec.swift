import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class FakeSpec: QuickSpec {
    override func spec() {
        describe("FakeWindow") {
            var fake: FakeWindow!

            beforeEach {
                waitUntil { done in
                    FakeState.initialize().then { state -> Promise<FakeWindow> in
                        let app = FakeApplication(parent: state)
                        return FakeWindowBuilder(parent: app)
                            .setTitle("I'm a test window")
                            .setPosition(CGPoint(x: 100, y: 100))
                            .build()
                    }.done { fw -> () in
                        fake = fw
                        done()
                    }.cauterize()
                }
            }

            it("builds with the requested properties") {
                expect(fake.title).to(equal("I'm a test window"))
                expect(fake.frame.origin).to(equal(CGPoint(x: 100, y: 100)))
                expect(fake.window.title.value).to(equal("I'm a test window"))
                expect(fake.window.frame.value.origin).to(equal(CGPoint(x: 100, y: 100)))

                expect(fake.isMinimized).to(beFalse())
                expect(fake.isFullscreen).to(beFalse())
            }

            it("sees changes from Swindler") {
                fake.window.frame.value.origin = CGPoint(x: 99, y: 100)
                expect(fake.frame.origin).toEventually(equal(CGPoint(x: 99, y: 100)))

                fake.window.size.value = CGSize(width: 1111, height: 2222)
                expect(fake.frame.size).toEventually(equal(CGSize(width: 1111, height: 2222)))

                fake.window.isMinimized.value = true
                expect(fake.isMinimized).toEventually(beTrue())
                fake.window.isMinimized.value = false
                expect(fake.isMinimized).toEventually(beFalse())

                fake.window.isFullscreen.value = true
                expect(fake.isFullscreen).toEventually(beTrue())
            }

            it("publishes changes to Swindler") {
                fake.title = "My title changes"
                expect(fake.window.title.value).toEventually(equal("My title changes"))

                fake.frame.origin = CGPoint(x: 200, y: 200)
                expect(fake.window.frame.value.origin).toEventually(equal(CGPoint(x: 200, y: 200)))

                fake.frame.size = CGSize(width: 3333, height: 4444)
                expect(fake.window.size.value).toEventually(equal(CGSize(width: 3333, height: 4444)))

                fake.isMinimized = true
                expect(fake.window.isMinimized.value).toEventually(beTrue())
                fake.isMinimized = false
                expect(fake.window.isMinimized.value).toEventually(beFalse())

                fake.isFullscreen = true
                expect(fake.window.isFullscreen.value).toEventually(beTrue())
            }
        }

        describe("FakeApplication") {
            var fakeApp: FakeApplication!
            var fakeWindow1: FakeWindow!
            var fakeWindow2: FakeWindow!

            beforeEach {
                waitUntil { done in
                    FakeState.initialize().then { state -> Promise<(FakeWindow, FakeWindow)> in
                        fakeApp = FakeApplication(parent: state)
                        return when(fulfilled:
                            FakeWindowBuilder(parent: fakeApp).build(),
                            FakeWindowBuilder(parent: fakeApp).build()
                        )
                    }.done { (fw1, fw2) in
                        fakeWindow1 = fw1
                        fakeWindow2 = fw2
                        done()
                    }.cauterize()
                }
            }

            it("sees changes from Swindler") {
                fakeApp.application.mainWindow.value = fakeWindow1.window
                expect(fakeApp.mainWindow).toEventually(equal(fakeWindow1))
                fakeApp.application.mainWindow.value = fakeWindow2.window
                expect(fakeApp.mainWindow).toEventually(equal(fakeWindow2))

                assert(fakeApp.isHidden == false)
                fakeApp.application.isHidden.value = true
                expect(fakeApp.isHidden).toEventually(equal(true))
            }

            it("publishes changes to Swindler") {
                fakeApp.mainWindow = fakeWindow1
                expect(fakeApp.application.mainWindow.value).toEventually(equal(fakeWindow1.window))
                fakeApp.mainWindow = fakeWindow2
                expect(fakeApp.application.mainWindow.value).toEventually(equal(fakeWindow2.window))

                fakeApp.focusedWindow = fakeWindow1
                expect(
                    fakeApp.application.focusedWindow.value
                ).toEventually(equal(fakeWindow1.window))
                fakeApp.focusedWindow = fakeWindow2
                expect(
                    fakeApp.application.focusedWindow.value
                ).toEventually(equal(fakeWindow2.window))

                assert(fakeApp.application.isHidden.value == false)
                fakeApp.isHidden = true
                expect(fakeApp.application.isHidden.value).toEventually(equal(true))
            }
        }

        describe("FakeState") {
            var fakeState: FakeState!
            var fakeApp1: FakeApplication!
            var fakeApp2: FakeApplication!

            beforeEach {
                waitUntil { done in
                    FakeState.initialize().done { fs in
                        fakeState = fs
                        fakeApp1 = FakeApplication(parent: fakeState)
                        fakeApp2 = FakeApplication(parent: fakeState)
                        done()
                    }.cauterize()
                }
            }

            it("sees changes from Swindler") {
                fakeState.state.frontmostApplication.value = fakeApp1.application
                expect(fakeState.frontmostApplication).toEventually(equal(fakeApp1))
                fakeState.state.frontmostApplication.value = fakeApp2.application
                expect(fakeState.frontmostApplication).toEventually(equal(fakeApp2))
            }

            it("publishes changes to Swindler") {
                fakeState.frontmostApplication = fakeApp1
                expect(fakeState.state.frontmostApplication.value).toEventually(
                    equal(fakeApp1.application))
                fakeState.frontmostApplication = fakeApp2
                expect(fakeState.state.frontmostApplication.value).toEventually(
                    equal(fakeApp2.application))
            }
        }
    }
}
