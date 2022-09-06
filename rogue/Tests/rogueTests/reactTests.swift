@testable import rogue
import Swindler
import XCTest

@MainActor
final class reactTests: XCTestCase {
    func setup(windows windowFrames: [CGRect]) async throws
        -> (Swindler.FakeState, [FakeWindow])
    {
        try await setup(screens: [FakeScreen()], windows: windowFrames)
    }

    func setup(screens: [FakeScreen],
               windows windowFrames: [CGRect]) async throws
        -> (Swindler.FakeState, [FakeWindow])
    {
        let swindler = try await adapt(Swindler.FakeState.initialize(screens: screens))
        let app = try await adapt(FakeApplicationBuilder(parent: swindler).build())
        var windows: [FakeWindow] = []
        for frame in windowFrames {
            windows.append(try await adapt(app.createWindow().setFrame(frame).build()))
        }
        return (swindler, windows)
    }

    func testReactorWithScreensButNoWindows() async throws {
        let (swindler, _) = try await setup(windows: [])

        class Mock: Layout {
            func onEvent(_: Event, state _: rogue.State) -> Bool {
                XCTAssert(false, "Unexpected event")
                return false
            }

            var getLayoutCalled = false
            func getLayout(state: rogue.State, config: Config) -> rogue.State {
                getLayoutCalled = true
                XCTAssertEqual(state.windows.count, 0)
                XCTAssertEqual(config.screens.count, 1)
                return state
            }
        }

        let reactor = Reactor(swindler: swindler.state)
        let layout = Mock()
        reactor.setLayout(layout)
        try await reactor.setup()
        XCTAssert(layout.getLayoutCalled)
    }

    func testReactorWithWindowsButNoScreens() async throws {
        let (swindler, _) = try await setup(screens: [], windows: [CGRect(x: 100, y: 100, width: 100, height: 100)])

        class Mock: Layout {
            func onEvent(_: Event, state _: rogue.State) -> Bool {
                XCTAssert(false, "Unexpected event")
                return false
            }

            func getLayout(state: rogue.State, config: Config) -> rogue.State {
                XCTAssertEqual(config.screens.count, 0)
                return state
            }
        }

        let reactor = Reactor(swindler: swindler.state)
        let layout = Mock()
        reactor.setLayout(layout)
        try await reactor.setup()
    }

    func testReactorInvertsFrames() async throws {
        let (swindler, windows) = try await setup(screens: [FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            menuBarHeight: 100,
            dockHeight: 100
        )], windows: [
            CGRect(x: 10, y: 100, width: 500, height: 500),
            CGRect(x: 20, y: 200, width: 500, height: 500),
        ])

        class Mock: Layout {
            func onEvent(_: Event, state _: rogue.State) -> Bool {
                XCTAssert(false, "Unexpected event")
                return false
            }

            func getLayout(state: rogue.State, config: Config) -> rogue.State {
                XCTAssertEqual(
                    config.screens.first?.frame,
                    CGRect(x: 0, y: 0, width: 1000, height: 800)
                )
                let windows = state.windows.sorted(by: { $0.topLeft.x < $1.topLeft.x })
                XCTAssertEqual(
                    windows.first?.invertedFrame,
                    CGRect(x: 10, y: 300, width: 500, height: 500),
                    "Window 0 should have correctly inverted coordinates"
                )
                XCTAssertEqual(
                    windows.last?.invertedFrame,
                    CGRect(x: 20, y: 200, width: 500, height: 500),
                    "Window 1 should have correctly inverted coordinates"
                )
                return rogue.State(windows: [
                    windows[0]
                        .withInvertedFrame(CGRect(x: 0, y: 0, width: 1000, height: 400)),
                    windows[1]
                        .withInvertedFrame(CGRect(x: 0, y: 400, width: 1000,
                                                  height: 400)),
                ])
            }
        }

        let reactor = Reactor(swindler: swindler.state)
        reactor.setLayout(Mock())
        try await reactor.setup()

        XCTAssertEqual(
            windows[0].frame,
            CGRect(x: 0, y: 500, width: 1000, height: 400)
        )
        XCTAssertEqual(
            windows[1].frame,
            CGRect(x: 0, y: 100, width: 1000, height: 400)
        )
    }

    // TODO: testHiddenWindowsFilteredOut
    // (minimized, hidden, different space once supported)
}
