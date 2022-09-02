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

public protocol Layout {
    // init(initialState state: State)

    // State should be replaced with just [Window].
    // I can't think of a principled reason to supply config to getLayout only.
    func onEvent(_ event: Event, state: State) -> Bool
    func getLayout(state: State, config: Config) -> State
}

class LayoutNoop: Layout {
    // required init(initialState state: State) {}

    func onEvent(_: Event, state _: State) -> Bool {
        false
    }

    func getLayout(state: State, config _: Config) -> State {
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
    var dividerRatio: CGFloat = 0.5

    public init() {}

    public func onEvent(_ event: Event, state _: State) -> Bool {
        switch event {
        case .addWindow: return true
        case .delWindow: return true
        }
    }

    public func getLayout(state cur: State, config: Config) -> State {
        guard let screen = config.screens.first else { return cur }
        guard let leftmost = cur.windows.min(by: { $0.topLeft.x < $1.topLeft.x })
        else { return cur }
        let primaryId = primaryId.getOrSet(default: leftmost.id)

        let numPrimary = 1
        let numSecondary = cur.windows.count - numPrimary
        let ratio = (numSecondary == 0) ? 1.0 : dividerRatio
        let (primary, secondary) = screen.frame.divided(
            atDistance: ratio * screen.frame.width,
            from: CGRectEdge.minXEdge
        )

        var windows = [Window(id: primaryId, invertedFrame: primary)]
        windows.append(contentsOf: cur.windows
            .filter { $0.id != primaryId }
            .enumerated()
            .map { idx, win -> Window in
                let height = screen.frame.height / CGFloat(numSecondary)
                let top = CGFloat(idx) * height
                let frame = secondary
                    .offsetBy(dx: 0, dy: top)
                    .divided(atDistance: height, from: CGRectEdge.minYEdge).slice
                return Window(id: win.id, invertedFrame: frame)
            })
        return State(windows: windows)
    }
}
