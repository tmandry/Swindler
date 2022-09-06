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

@MainActor
public class Reactor {
    let swindler: Swindler.State
    var winIds: IdMapper<Swindler.Window> = IdMapper()
    var screenIds: IdMapper<Swindler.Screen> = IdMapper()
    var spaceId: Int?

    var layout: Layout?

    public convenience init() async throws {
        self.init(swindler: try await adapt(Swindler.initialize()))
    }

    init(swindler: Swindler.State) {
        self.swindler = swindler
        swindler.on { (event: WindowCreatedEvent) in
            Task {
                try! await self.handleEvent(Event.addWindow(id: self.winIds[event.window]))
            }
        }
        swindler.on { (event: WindowDestroyedEvent) in
            Task {
                try! await self.handleEvent(Event.delWindow(id: self.winIds[event.window]))
            }
        }
        print("Reactor: initialized")
    }

    public func setLayout(_ layout: Layout) {
        self.layout = layout
    }

    public func setup() async throws {
        // TODO spaces support
        spaceId = swindler.mainScreen?.spaceId
        try await updateState(nil)
    }

    func handleEvent(_ event: Event) async throws {
        // TODO spaces support
        guard let curSpace = swindler.mainScreen?.spaceId else { return }
        if curSpace != spaceId! { return }

        guard let state = getState() else { return }
        if layout?.onEvent(event, state: state) ?? false {
            try await updateState(state)
        }
    }

    func getState() -> State? {
        guard let maxY = globalMaxY() else { return nil }
        // TODO: current screen only (needs swindler support)
        let windows = swindler.knownWindows
            .filter { !$0.isMinimized.value }
            .map {
                Window(id: winIds[$0], invertedFrame: invert($0.frame.value, maxY))
            }
        return State(windows: windows)
    }

    func updateState(_ state: State?) async throws {
        guard let layout = layout else { return }
        guard let maxY = globalMaxY() else { return }
        let screens = swindler.screens.map {
            Screen(id: screenIds[$0], frame: invert($0.applicationFrame, maxY))
        }
        guard let state = state ?? getState() else { return }
        let desired = layout.getLayout(
            state: state,
            config: Config(screens: screens)
        )
        let promises = desired.windows.compactMap { win -> Promise<Void>? in
            guard let window = winIds[win.id] else {
                print("Unknown window id \(win.id) received from layout")
                return nil
            }
            let frame = invert(win.invertedFrame, maxY)
            return window.frame.set(frame).asVoid()
        }
        // TODO: handle errors?
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
