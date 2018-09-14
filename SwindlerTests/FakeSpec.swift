import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class FakeSpec: QuickSpec {
    override func spec() {
        describe("FakeWindow") {
            it("sees changes from Swindler") { () -> Promise<Void> in
                return firstly { () -> Promise<FakeWindow> in
                    let state = FakeState()
                    let app = FakeApplication(parent: state)
                    return FakeWindowBuilder(parent: app)
                        .setTitle("I'm a test window")
                        .setPosition(CGPoint(x: 100, y: 100))
                        .build()
                }.then { tw in
                    expect(tw.title).to(equal("I'm a test window"))
                    expect(tw.window.title.value).to(equal("I'm a test window"))
                    //expect(tw.rect).to(equal(CGRect(x: 100, y: 100, width: 600, height: 800)))
                    expect(try? tw.element.attribute(.position)).to(equal(CGPoint(x:
                        100, y: 100)))

                    return tw.window.position.set(CGPoint(x: 99, y: 100)).then { _ in
                        expect(tw.rect.origin).to(equal(CGPoint(x: 99, y: 100)))
                    }
                }
            }

            it("publishes changes to Swindler") {
                var fake: FakeWindow!
                waitUntil { done in
                    firstly { () -> Promise<FakeWindow> in
                        let state = FakeState()
                        let app = FakeApplication(parent: state)
                        return FakeWindowBuilder(parent: app)
                            .setTitle("I'm a test window")
                            .setPosition(CGPoint(x: 100, y: 100))
                            .build()
                    }.then { fw -> () in
                        fake = fw
                        done()
                    }.always {}
                }
                fake.rect.origin = CGPoint(x: 200, y: 200)
                fake.title       = "My title changes"
                expect(fake.window.position.value).toEventually(equal(CGPoint(x: 200, y: 200)))
                expect(fake.window.title.value).toEventually(equal("My title changes"))
            }
        }

        describe("FakeApplication") {
            var fakeApp: FakeApplication!
            var fakeWindow1: FakeWindow!
            var fakeWindow2: FakeWindow!

            beforeEach {
                waitUntil { done in
                    firstly { () -> Promise<(FakeWindow, FakeWindow)> in
                        let state = FakeState()
                        fakeApp = FakeApplication(parent: state)
                        return when(fulfilled:
                            FakeWindowBuilder(parent: fakeApp).build(),
                            FakeWindowBuilder(parent: fakeApp).build()
                        )
                    }.then { (fw1, fw2) -> () in
                        fakeWindow1 = fw1
                        fakeWindow2 = fw2
                        done()
                    }.always {}
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
    }
}
