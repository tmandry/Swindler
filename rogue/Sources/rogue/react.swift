// React loop

import Cocoa
import PromiseKit
import Swindler

func adapt<T>(_ promise: Promise<T>) async throws -> T {
    try await withCheckedThrowingContinuation { cont in
        promise.done { state in
            cont.resume(returning: state)
        }.catch { error in
            cont.resume(throwing: error)
        }
    }
}

public actor Reactor {
    let swindler: Swindler.State
    var winIds: IdMapper<Swindler.Window> = IdMapper()
    var screenIds: IdMapper<Swindler.Screen> = IdMapper()

    var layout: Layout?

    public init() async throws {
        swindler = try await adapt(Swindler.initialize())
        print("Reactor: initialized")
    }

    public func setLayout(_ layout: Layout) {
        self.layout = layout
    }

    public func run() async throws {
        guard let layout = layout else { return }
        guard let maxY = globalMaxY() else { return }
        let screens = swindler.screens.map {
            Screen(id: screenIds[$0], frame: invert($0.applicationFrame, maxY))
        }
        // TODO: visible only (needs swindler support)
        let windows = swindler.knownWindows.map {
            Window(id: winIds[$0], invertedFrame: invert($0.frame.value, maxY))
        }
        print(State(windows: windows))
        let desired = layout.getLayout(
            state: State(windows: windows),
            config: Config(screens: screens)
        )
        print(desired)
        print(winIds)
        let promises = desired.windows.compactMap { win -> Promise<Void>? in
            guard let window = winIds[win.id] else {
                print("Unknown window id \(win.id) received from layout")
                return nil
            }
            let frame = invert(win.invertedFrame, maxY)
            print("Setting \(window) frame to \(frame)")
            return window.frame.set(frame).asVoid()
        }
        try await adapt(when(fulfilled: promises))
    }

    private func globalMaxY() -> CGFloat? {
        swindler.screens.map { $0.applicationFrame.maxY }.max()
    }

    private func invert(_ rect: CGRect, _ globalMaxY: CGFloat) -> CGRect {
        let inverted = CGPoint(x: rect.minX, y: globalMaxY - rect.maxY)
        return CGRect(origin: inverted, size: rect.size)
    }
}

class IdMapper<T: Hashable> {
    var idMap: [T: Int] = [:]
    var valMap: [Int: T] = [:]
    var lastId: Int = 0

    subscript(win: T) -> Int {
        if let id = idMap[win] { return id }
        lastId += 1
        idMap[win] = lastId
        valMap[lastId] = win
        return lastId
    }

    subscript(id: Int) -> T? {
        valMap[id]
    }
}

extension IdMapper: CustomStringConvertible {
    var description: String {
        "\(valMap)"
    }
}
