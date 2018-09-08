import AXSwift
import PromiseKit

public class TestState {
    typealias Delegate =
        OSXStateDelegate<TestUIElement, TestApplicationElement, FakeObserver>;

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
public struct TestApplicationBuilder {
    private var app: TestApplication

    func setProcessid(_ pid: pid_t) -> TestApplicationBuilder {
        app.processid = pid
        return self
    }
    func setBundleid(_ bundleID: String?) -> TestApplicationBuilder {
        app.bundleid = bundleID
        return self
    }
    func setHidden(_ hidden: Bool) -> TestApplicationBuilder { app.hidden = hidden; return self }

    func build() -> TestApplication {
        // TODO do registration, event firing
        return app
    }
}
 */

public class TestApplication {
    typealias Delegate =
        OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>;

    let parent: TestState

    public var application: Application {
        get { return Application(delegate: delegate!)! }
    }

    fileprivate(set) var processid: pid_t
    fileprivate(set) var bundleid: String?
    fileprivate(set) var hidden: Bool
    var mainWindow: TestWindow?
    var focusedWindow: TestWindow?

    let element: TestApplicationElement

    var delegate: Delegate!

    init(parent: TestState) {
        self.parent = parent
        processid = 0
        hidden = false
        element = TestApplicationElement()
        delegate = try! Delegate(
            axElement: element, stateDelegate: parent.delegate, notifier: parent.delegate)
    }

    public func createWindow() -> TestWindowBuilder {
        return TestWindowBuilder(parent: self)
    }
}

public class TestWindowBuilder {
    private let w: TestWindow

    init(parent: TestApplication) {
        w = TestWindow(parent: parent)
    }

    func setTitle(_ title: String) -> TestWindowBuilder { w.title = title; return self }
    func setRect(_ rect: CGRect) -> TestWindowBuilder { w.rect = rect; return self }
    func setPosition(_ pos: CGPoint) -> TestWindowBuilder { w.rect.origin = pos; return self }
    func setSize(_ size: CGSize) -> TestWindowBuilder { w.rect.size = size; return self }
    func setMinimized(_ isMinimized: Bool = true) -> TestWindowBuilder {
        w.isMinimized = isMinimized
        return self
    }
    func setFullscreen(_ isFullscreen: Bool = true) -> TestWindowBuilder {
        w.isFullscreen = isFullscreen
        return self
    }

    func build() -> Promise<TestWindow> {
        // TODO schedule new window event
        //w.parent.delegate!...
        return w.parent.delegate.addWindowElement(w.element).then { delegate -> TestWindow in
            self.w.delegate = delegate
            return self.w
        }
    }
}

public class TestWindow: TestObject {
    typealias Delegate =
        OSXWindowDelegate<TestUIElement, TestApplicationElement, FakeObserver>

    public let parent: TestApplication
    public var window: Window {
        get { return Window(delegate: delegate!)! }
    }

    let element: TestWindowElement

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

    init(parent: TestApplication) {
        element = TestWindowElement(forApp: parent.element)
        self.parent = parent
        isValid = true

        title = "TestWindow"
        rect = CGRect(x: 300, y: 300, width: 600, height: 800)
        isMinimized = false
        isFullscreen = false
    }
}

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
