import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class FakeSpec: QuickSpec {
    override func spec() {
        describe("FakeWindow") {
            it("works") { () -> Promise<Void> in
                return firstly { () -> Promise<TestWindow> in
                    let state = TestState()
                    let app = TestApplication(parent: state)
                    return TestWindowBuilder(parent: app)
                        .setTitle("I'm a test window")
                        .build()
                }.then { tw in
                    expect(tw.title).to(equal("I'm a test window"))
                    expect(tw.window.title.value).to(equal("I'm a test window"))

                    return tw.window.position.set(CGPoint(x: 99, y: 100)).then { _ in
                        expect(tw.rect.origin).to(equal(CGPoint(x: 99, y: 100)))
                    }
                }
            }
        }

        describe("FakeApplication") {
            it("works") {
                // TODO
            }
        }
    }
}
