// Sample layouts

// We're going to use global screen coordinates, in pixels (points?), because
// that makes the fewest assumptions about what kind of WM we are writing.
//
// It might be nice to make more; for example, we could use floats as a ratio of
// the screen a window is on, and the framework could then resize the windows for us
// if the screen size changes. But what if we want to stretch a window across
// two screens, or want to respond to a resize differently (by choosing a different
// arrangement instead of just scaling the current one)?
//
// Similarly, it would be nice to use a tree representation at some point. This is
// something we can and probably should do internally (as a data structure we recompute)
// so that we can use it to control border windows and so on. But we have to convert it
// to a flat representation at some point, so we can do that before getting to
// the framework's core react loop.

import Cocoa

public typealias WindowId = Int
public typealias ScreenId = Int

public enum Event {
    case addWindow(id: Int)
    case delWindow(id: Int)
}

public struct State: Equatable {
    var windows: [Window]
}

public struct Window: Equatable {
    var id: WindowId

    // TODO: Should we make these optional so the layout can say it doesn't
    // care about one or both of them? For example, during a window resize
    // we don't want to interfere. We might want to change the frame.
    //
    // Another factor to consider is that you can only set the topLeft using
    // accessibility APIs. We try to hide the fact that these are used in Swindler
    // (especially since it's an inverted coordinate system from the rest of the system
    // APIs), but if we want to expose fine grained control we will have to surface
    // the origin as topLeft (in whatever coordinate system we choose).
    var topLeft: CGPoint
    var size: CGSize

    // This could be too powerful. But it's certainly the case that we want to be able
    // to surface a group of windows on top of another group of windows. We should allow
    // the user to specify that. One way is to allow duplicate indices; this would mean
    // "I don't care about relative order within this index as long as each window in it
    // is above/below windows in other indices".
    //
    // 0 is the top.
    var zIndex: Int?
}

public extension Window {
    init(id: WindowId, invertedFrame frame: CGRect) {
        self.init(id: id, topLeft: frame.origin, size: frame.size)
    }

    // It just seems much more natural to use top-down coordinates in a window manager.
    var invertedFrame: CGRect {
        get { CGRect(origin: topLeft, size: size) }
        set { topLeft = newValue.origin; size = newValue.size }
    }

    func withInvertedFrame(_ frame: CGRect) -> Window {
        Window(id: id, invertedFrame: frame)
    }

    func cgFrame(config _: Config) -> CGRect {
        // Unimplemented
        abort()
    }
}

public struct Config {
    var screens: [Screen]
}

public struct Screen {
    var id: ScreenId
    var frame: CGRect
}

public protocol MultiScreenLayout {
    // State should be replaced with just [Window].
    // I can't think of a principled reason to supply config to getLayout only.
    func setup(state: State, config: Config)
    func onEvent(_ event: Event, state: State, config: Config) -> Bool
    func getLayout(state: State, config: Config) -> State
}

public extension MultiScreenLayout {
    func setup(state _: State, config _: Config) {}
}

public protocol Layout {
    // State should be replaced with just [Window].
    // I can't think of a principled reason to supply config to getLayout only.
    func setup(state: State, frame: CGRect)
    func onEvent(_ event: Event, state: State, frame: CGRect) -> Bool
    func getLayout(state: State, frame: CGRect) -> State
}

public extension Layout {
    func setup(state _: State, frame _: CGRect) {}
}

public class FirstScreenLayout: MultiScreenLayout {
    var layout: Layout

    public init(_ layout: Layout) {
        self.layout = layout
    }

    static func frame(_ config: Config) -> CGRect {
        guard let screen = config.screens.first else {
            fatalError("not supported")
        }
        return screen.frame
    }

    public func setup(state: State, config: Config) {
        layout.setup(state: state, frame: Self.frame(config))
    }

    public func onEvent(_ event: Event, state: State, config: Config) -> Bool {
        layout.onEvent(event, state: state, frame: Self.frame(config))
    }

    public func getLayout(state: State, config: Config) -> State {
        layout.getLayout(state: state, frame: Self.frame(config))
    }
}

class LayoutNoop: Layout {
    // required init(initialState state: State) {}

    func onEvent(_: Event, state _: State, frame _: CGRect) -> Bool {
        false
    }

    func getLayout(state: State, frame _: CGRect) -> State {
        state
    }
}

extension Optional {
    mutating func getOrSet(default defaultVal: Wrapped) -> Wrapped {
        guard let inner = self else {
            self = defaultVal
            return defaultVal
        }
        return inner
    }
}

// "Tall": Main window on the left. Other windows share a column on the right.
public class LayoutTall: Layout {
    // TODO: How do we handle properties about windows that we want to remember
    // across layouts? For instance, whether a window is floating, or whether it
    // is primary.
    var primaryId: WindowId?
    var dividerRatio: CGFloat = 0.35

    public init() {}

    public func onEvent(_ event: Event, state _: State, frame _: CGRect) -> Bool {
        switch event {
        case .addWindow: return true
        case .delWindow: return true
        }
    }

    public func getLayout(state cur: State, frame: CGRect) -> State {
        guard let leftmost = cur.windows.min(by: { $0.topLeft.x < $1.topLeft.x })
        else { return cur }
        let primaryId = primaryId.getOrSet(default: leftmost.id)

        let numPrimary = 1
        let numSecondary = cur.windows.count - numPrimary
        let ratio = (numSecondary == 0) ? 1.0 : dividerRatio
        let (primary, secondary) = frame.divided(
            atDistance: ratio * frame.width,
            from: CGRectEdge.minXEdge
        )

        var windows = [Window(id: primaryId, invertedFrame: primary)]
        windows.append(contentsOf: cur.windows
            .filter { $0.id != primaryId }
            .enumerated()
            .map { idx, win -> Window in
                let height = frame.height / CGFloat(numSecondary)
                let top = CGFloat(idx) * height
                let frame = secondary
                    .offsetBy(dx: 0, dy: top)
                    .divided(atDistance: height, from: CGRectEdge.minYEdge).slice
                return Window(id: win.id, invertedFrame: frame)
            })
        return State(windows: windows)
    }
}

public class TallLayout: Layout {
    var layout: Horizontal = Horizontal()
    var secondaryLayout: Horizontal?

    public func setup(state cur: State, frame: CGRect) {
        layout.setup(state: cur, frame: frame)
    }

    public func onEvent(_ event: Event, state: State, frame: CGRect) -> Bool {
        switch event {
        case .addWindow(_):
            if layout.children.count == 0 {
                return layout.onEvent(event, state: state, frame: frame)
            } else {
                if layout.children.count == 1 {
                    secondaryLayout = Horizontal()
                    //layout.addChild(secondaryLayout, frame)
                }
                return secondaryLayout!.onEvent(event, state: state, frame: frame)
            }
        case .delWindow(_):
            if layout.onEvent(event, state: state, frame: frame) {
                if let secondaryLayout = secondaryLayout, layout.children.count < 2 {
                    // Promote the first child
                    let win = secondaryLayout.delChild(at: 0, frame)
                    // TODO insert at index 0
                    layout.addChild(win, frame)
                }
                if secondaryLayout?.children.count == 0 {
                    secondaryLayout = nil
                    layout.delChild(at: 1, frame)
                    return true
                }
            }
        }
        return false
    }

    public func getLayout(state: State, frame: CGRect) -> State {
        layout.getLayout(state: state, frame: frame)
    }
}

enum Child {
    case layout(Layout)
    case window(WindowId)
}

extension Child {
    func windowId() -> WindowId? {
        switch self {
        case let .window(wid): return wid
        default: return nil
        }
    }
}

public class Nested {
    var child: [Child] = []
    //var layout: Layout
}

extension Nested {
    public func setup(state cur: State, frame: CGRect) {
        //layout.setup(state: cur, frame: frame)
    }

    // public func
}

public final class Horizontal {
    var children: [Child] = []
    var dividers: [CGFloat] = []

    public func setup(state cur: State, frame: CGRect) {
        children = cur.windows.lazy
            .sorted(by: { $0.topLeft.x < $1.topLeft.x })
            .map { .window($0.id) }
        dividers = Array(sequence(
            first: 0,
            next: { $0 + frame.width / CGFloat(cur.windows.count) }
        ).prefix(cur.windows.count))
    }

    @discardableResult
    func addChild(_ child: Child, _ frame: CGRect) -> Int {
        let slice = 1.0 / CGFloat(dividers.count + 1)
        for var divider in dividers {
            divider *= (1 - slice)
        }
        dividers.append(frame.width * slice)
        children.append(child)
        return children.count - 1
    }

    @discardableResult
    func delChild(at idx: Int, _ frame: CGRect) -> Child {
        let slice = dividers[idx] / frame.width
        for var divider in dividers {
            divider /= (1 - slice)
        }
        dividers.remove(at: idx)
        return children.remove(at: idx)
    }

    public func onEvent(_ event: Event, state _: State, frame: CGRect) -> Bool {
        switch event {
        case let .addWindow(wid):
            addChild(.window(wid), frame)
            return true
        case let .delWindow(wid):
            let idx = children.firstIndex(where: { $0.windowId() == wid })!
            delChild(at: idx, frame)
            return true
        }
    }

    public func getLayout(state cur: State, frame: CGRect) -> State {
        assert(dividers.count == children.count)
        return State(windows: children.enumerated().flatMap { idx, child -> [Window] in
            let x = (idx == 0) ? 0 : dividers[idx - 1]
            let frame = CGRect(
                x: frame.minX + x,
                y: frame.minY,
                width: dividers[idx] - x,
                height: frame.height
            )
            switch child {
            case let .window(wid): return [Window(id: wid, invertedFrame: frame)]
            case let .layout(layout): return layout
                .getLayout(state: cur, frame: frame).windows
            }
        })
    }
}

protocol BaseView {
    // Transitive window count.
    var count: Int { get }

    var body: View { get }

    func getLayout(frame: CGRect) -> [CGRect]
}

protocol View: BaseView {}

extension View {
    var count: Int { body.count }
    func getLayout(frame: CGRect) -> [CGRect] { body.getLayout(frame: frame) }
}

struct MyView: View {
    var count: Int
    var body: View {
        fatalError()
    }
}

struct VStack: View {
    var children: [View]

    var count: Int {
        children.reduce(0, { $0 + $1.count })
    }
    var body: View {
        self
    }

    func getLayout(frame: CGRect) -> [CGRect] {
        children.flatMap({ $0.getLayout(frame: frame) })
    }
}

struct WindowView: View {
    var count: Int { 1 }
    var body: View { self }
    func getLayout(frame: CGRect) -> [CGRect] { [frame] }
}
