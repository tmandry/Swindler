import AXSwift
import PromiseKit

public class TestState {
    var delegate: TestStateDelegate
    var state: State

    init() {
        delegate = TestStateDelegate()
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

private var _curId: Int = 0
private func nextId() -> Int {
    _curId += 1
    return _curId
}

public class TestApplication {
    let parent: TestState

    public var application: Application {
        get { return Application(delegate: delegate!)! }
    }

    fileprivate(set) var processid: pid_t
    fileprivate(set) var bundleid: String?
    fileprivate(set) var hidden: Bool
    var mainWindow: TestWindow?
    var focusedWindow: TestWindow?

    var delegate: ApplicationDelegate!

    private(set) internal var id: Int

    init(parent: TestState) {
        self.parent = parent
        id = nextId()
        processid = 0
        hidden = false
        delegate = TestApplicationDelegate(self, stateDelegate: parent.delegate)
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
        let initialized = TestWindowDelegate.initialize(
            appDelegate: w.parent.delegate, notifier: nil, testWindow: w)
        return initialized.then { delegate -> TestWindow in
            self.w.delegate = delegate
            return self.w
        }
    }
}

public class TestWindow: TestObject {
    public let parent: TestApplication
    public var window: Window {
        get { return Window(delegate: delegate!)! }
    }

    public var rect: CGRect {
        didSet {
            delegate?.position.refresh()
            delegate?.size.refresh()
        }
    }
    public var title: String {
        didSet { delegate?.title.refresh() }
    }
    public var isMinimized: Bool {
        didSet { delegate?.isMinimized.refresh() }
    }
    public var isFullscreen: Bool {
        didSet { delegate?.isFullscreen.refresh() }
    }

    var delegate: TestWindowDelegate?

    private(set) internal var id: Int

    // TODO public?
    var isValid: Bool

    // TODO: Control whether a window accepts incoming changes from Swindler.
    // This can be used to simulate non-resizable windows, or windows (like terminals)
    // that snap to certain sizes, for instance.

    init(parent: TestApplication) {
        id = nextId()
        self.parent = parent
        self.rect = CGRect(x: 300, y: 300, width: 600, height: 800)
        self.title = "TestWindow"
        self.isMinimized = false
        self.isFullscreen = false

        isValid = true
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
