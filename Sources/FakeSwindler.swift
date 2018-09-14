import AXSwift
import PromiseKit

public class FakeState {
    typealias Delegate =
        OSXStateDelegate<TestUIElement, EmittingTestApplicationElement, FakeObserver>;

    var delegate: Delegate
    var state: State
    var appObserver: FakeApplicationObserver

    init() {
        appObserver = FakeApplicationObserver()
        delegate = Delegate(appObserver: appObserver)
        state = State(delegate: delegate)
    }
}

/*
public struct FakeApplicationBuilder {
    private var app: FakeApplication

    func setProcessid(_ pid: pid_t) -> FakeApplicationBuilder {
        app.processid = pid
        return self
    }
    func setBundleid(_ bundleID: String?) -> FakeApplicationBuilder {
        app.bundleid = bundleID
        return self
    }
    func setHidden(_ hidden: Bool) -> FakeApplicationBuilder { app.hidden = hidden; return self }

    func build() -> FakeApplication {
        // TODO do registration, event firing
        return app
    }
}
 */

public class FakeApplication {
    typealias Delegate =
        OSXApplicationDelegate<TestUIElement, EmittingTestApplicationElement, FakeObserver>;

    let parent: FakeState

    public var application: Application {
        get { return Application(delegate: delegate!)! }
    }

    fileprivate(set) var processId: pid_t
    fileprivate(set) var bundleId: String?

    public var isHidden: Bool {
        get { return try! element.attribute(.hidden)! }
        set { try! element.setAttribute(.hidden, value: newValue) }
    }
    public var mainWindow: FakeWindow? {
        get {
            guard let windowElement: EmittingTestWindowElement =
                      try! element.attribute(.mainWindow) else {
                return nil
            }
            return (windowElement.companion) as! FakeWindow?
        }
        set {
            try! element.setAttribute(.mainWindow, value: newValue?.element as Any)
        }
    }
    public var focusedWindow: FakeWindow? {
        get {
            guard let windowElement: EmittingTestWindowElement =
                      try! element.attribute(.focusedWindow) else {
                return nil
            }
            return (windowElement.companion) as! FakeWindow?
        }
        set {
            try! element.setAttribute(.focusedWindow, value: newValue?.element as Any)
        }
    }

    let element: EmittingTestApplicationElement

    var delegate: Delegate!

    init(parent: FakeState) {
        self.parent = parent
        processId = 0
        element = EmittingTestApplicationElement()
        isHidden = false
        delegate = try! Delegate(
            axElement: element, stateDelegate: parent.delegate, notifier: parent.delegate)
    }

    public func createWindow() -> FakeWindowBuilder {
        return FakeWindowBuilder(parent: self)
    }
}

public class FakeWindowBuilder {
    private let w: FakeWindow

    init(parent: FakeApplication) {
        w = FakeWindow(parent: parent)
    }

    func setTitle(_ title: String) -> FakeWindowBuilder { w.title = title; return self }
    func setRect(_ rect: CGRect) -> FakeWindowBuilder { w.rect = rect; return self }
    func setPosition(_ pos: CGPoint) -> FakeWindowBuilder { w.rect.origin = pos; return self }
    func setSize(_ size: CGSize) -> FakeWindowBuilder { w.rect.size = size; return self }
    func setMinimized(_ isMinimized: Bool = true) -> FakeWindowBuilder {
        w.isMinimized = isMinimized
        return self
    }
    func setFullscreen(_ isFullscreen: Bool = true) -> FakeWindowBuilder {
        w.isFullscreen = isFullscreen
        return self
    }

    func build() -> Promise<FakeWindow> {
        // TODO schedule new window event
        //w.parent.delegate!...
        return w.parent.delegate.addWindowElement(w.element).then { delegate -> FakeWindow in
            self.w.delegate = delegate
            return self.w
        }
    }
}

public class FakeWindow: TestObject {
    typealias Delegate =
        OSXWindowDelegate<TestUIElement, EmittingTestApplicationElement, FakeObserver>

    public let parent: FakeApplication
    public var window: Window {
        get { return Window(delegate: delegate!)! }
    }

    let element: EmittingTestWindowElement

    public var title: String {
        get { return try! element.attribute(.title)! }
        set { try! element.setAttribute(.title, value: newValue) }
    }
    public var rect: CGRect {
        get {
            return CGRect(origin: try! element.attribute(.position)!,
                          size: try! element.attribute(.size)!)
        }
        set {
            try! element.setAttribute(.position, value: newValue.origin)
            try! element.setAttribute(.size, value: newValue.size)
        }
    }
    public var isMinimized: Bool {
        get { return try! element.attribute(.minimized)! }
        set { try! element.setAttribute(.minimized, value: newValue) }
    }
    public var isFullscreen: Bool {
        get { return try! element.attribute(.fullScreen)! }
        set { try! element.setAttribute(.fullScreen, value: newValue) }
    }

    var delegate: Delegate?

    // TODO public?
    var isValid: Bool

    // TODO: Control whether a window accepts incoming changes from Swindler.
    // This can be used to simulate non-resizable windows, or windows (like terminals)
    // that snap to certain sizes, for instance.

    init(parent: FakeApplication) {
        element = EmittingTestWindowElement(forApp: parent.element)
        self.parent = parent
        isValid = true

        element.companion = self

        title = "FakeWindow"
        rect = CGRect(x: 300, y: 300, width: 600, height: 800)
        isMinimized = false
        isFullscreen = false
    }
}

public func ==(lhs: FakeWindow, rhs: FakeWindow) -> Bool {
    return lhs.element == rhs.element
}
extension FakeWindow: Equatable {}

protocol TestObject: class {
    var isValid: Bool { get }
}

class TestPropertyDelegate<T: Equatable, Object: TestObject>: PropertyDelegate {
    typealias Getter = (Object) -> T
    typealias Setter = (Object, T) -> ()

    weak var object: Object?
    let getter: Getter
    let setter: Setter

    init(_ object: Object, _ getter: @escaping Getter, _ setter: @escaping Setter) {
        self.object = object
        self.getter = getter
        self.setter = setter
    }

    func initialize() -> Promise<T?> {
        guard let object = object, object.isValid else {
            return Promise(value: nil)
        }
        return Promise(value: getter(object))
    }

    func readValue() throws -> T? {
        guard let object = object, object.isValid else {
            // TODO make cause optional
            throw PropertyError.invalidObject(cause: AXSwift.AXError.invalidUIElement)
        }
        return getter(object)
    }

    func writeValue(_ newValue: T) throws {
        guard let object = object, object.isValid else {
            // TODO make cause optional
            throw PropertyError.invalidObject(cause: AXSwift.AXError.invalidUIElement)
        }
        setter(object, newValue)
    }
}
