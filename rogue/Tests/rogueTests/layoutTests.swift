@testable import rogue
import XCTest

final class layoutTests: XCTestCase {
    let oneScreen =
        Config(screens: [Screen(id: 10,
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100))])
    let winA = Window(id: 100, invertedFrame: CGRect(x: 10, y: 10, width: 50, height: 50))
    let winB = Window(id: 101, invertedFrame: CGRect(x: 11, y: 10, width: 50, height: 50))
    let winC = Window(id: 102, invertedFrame: CGRect(x: 12, y: 10, width: 50, height: 50))

    func testLayoutTallZeroWindows() throws {
        let layout = LayoutTall()
        XCTAssertEqual(
            State(windows: []),
            layout.getLayout(state: State(windows: []), config: Config(screens: []))
        )
        XCTAssertEqual(
            State(windows: []),
            layout.getLayout(state: State(windows: []), config: oneScreen)
        )
    }

    func testLayoutTallZeroScreens() throws {
        let layout = LayoutTall()
        XCTAssertEqual(
            State(windows: []),
            layout.getLayout(state: State(windows: []), config: Config(screens: []))
        )
        XCTAssertEqual(
            State(windows: [winA]),
            layout.getLayout(state: State(windows: [winA]), config: Config(screens: []))
        )
    }

    func testLayoutTallOneWindow() throws {
        let layout = LayoutTall()
        XCTAssertEqual(
            State(windows: [
                winA.withInvertedFrame(CGRect(x: 0, y: 0, width: 100, height: 100)),
            ]),
            layout.getLayout(state: State(windows: [winA]), config: oneScreen)
        )
    }

    func testLayoutTallTwoWindows() throws {
        let layout = LayoutTall()
        XCTAssertEqual(
            State(windows: [
                winA.withInvertedFrame(CGRect(x: 0, y: 0, width: 50, height: 100)),
                winB.withInvertedFrame(CGRect(x: 50, y: 0, width: 50, height: 100)),
            ]),
            layout.getLayout(state: State(windows: [winA, winB]), config: oneScreen)
        )
    }

    func testLayoutTallThreeWindows() throws {
        let layout = LayoutTall()
        XCTAssertEqual(
            State(windows: [
                winA.withInvertedFrame(CGRect(x: 0, y: 0, width: 50, height: 100)),
                winB.withInvertedFrame(CGRect(x: 50, y: 0, width: 50, height: 50)),
                winC.withInvertedFrame(CGRect(x: 50, y: 50, width: 50, height: 50)),
            ]),
            layout.getLayout(state: State(windows: [winA, winB, winC]), config: oneScreen)
        )
    }
}
