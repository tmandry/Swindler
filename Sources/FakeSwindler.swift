/// Experimental fake implementation of Swindler for testing code that uses
/// Swindler.
///
/// Each Swindler object has (or will have) a corresponding Fake class that
/// allows you to create the objects and control them. Changes made to Fake
/// objects appear to ordinary code as coming from the operating system.
///
/// This is currenty an experimental API, and may change a lot.

// TODO: Document API

import AXSwift
import PromiseKit

fileprivate typealias AppElement = EmittingTestApplicationElement

public class FakeState {
    fileprivate typealias Delegate =
        OSXStateDelegate<TestUIElement, AppElement, FakeObserver>

    public static func initialize(screens: [FakeScreen] = [FakeScreen()]) -> Promise<FakeState> {
        let appObserver = FakeApplicationObserver()
        let screens = FakeSystemScreenDelegate(screens: screens.map{ $0.delegate })
        return firstly {
            Delegate.initialize(appObserver: appObserver, screens: screens)
        }.map { delegate in
            FakeState(delegate, appObserver)
        }
    }

    public var state: State

    public var frontmostApplication: FakeApplication? {
        get {
            guard let pid = appObserver.frontmostApplicationPID else { return nil }
            guard let elem = try! AppElement.all().first(where: { try $0.pid() == pid }) else {
                return nil
            }
            return Optional(elem.companion as! FakeApplication)
        }
        set {
            appObserver.setFrontmost(newValue?.processId)
        }
    }

    fileprivate var delegate: Delegate
    var appObserver: FakeApplicationObserver

    private init(_ delegate: Delegate, _ appObserver: FakeApplicationObserver) {
        self.state = State(delegate: delegate)
        self.delegate = delegate
        self.appObserver = appObserver
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
    fileprivate typealias Delegate =
        OSXApplicationDelegate<TestUIElement, AppElement, FakeObserver>;

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

    fileprivate let element: AppElement

    fileprivate var delegate: Delegate!

    public init(parent: FakeState) {
        self.parent = parent
        element = AppElement()
        processId = element.processID
        isHidden = false
        delegate = try! Delegate(element, parent.delegate, parent.delegate.notifier)

        element.companion = self
        parent.appObserver.launch(processId)
    }

    public func createWindow() -> FakeWindowBuilder {
        return FakeWindowBuilder(parent: self)
    }
}

public func ==(lhs: FakeApplication, rhs: FakeApplication) -> Bool {
    return lhs.element == rhs.element
}
extension FakeApplication: Equatable {}

public class FakeWindowBuilder {
    private let w: FakeWindow

    public init(parent: FakeApplication) {
        w = FakeWindow(parent: parent)
    }

    public func setTitle(_ title: String) -> FakeWindowBuilder { w.title = title; return self }
    public func setFrame(_ frame: CGRect) -> FakeWindowBuilder { w.frame = frame; return self }
    public func setPosition(_ pos: CGPoint) -> FakeWindowBuilder { w.frame = CGRect(origin: pos,
    size: w.frame.size); return self }
    public func setSize(_ size: CGSize) -> FakeWindowBuilder { w.frame.size = size; return self }
    public func setMinimized(_ isMinimized: Bool = true) -> FakeWindowBuilder {
        w.isMinimized = isMinimized
        return self
    }
    public func setFullscreen(_ isFullscreen: Bool = true) -> FakeWindowBuilder {
        w.isFullscreen = isFullscreen
        return self
    }

    public func build() -> Promise<FakeWindow> {
        // TODO schedule new window event
        //w.parent.delegate!...
        return w.parent.delegate.addWindowElement(w.element).map { delegate in
            self.w.delegate = delegate
            return self.w
        }
    }
}

public class FakeWindow: TestObject {
    fileprivate typealias Delegate = OSXWindowDelegate<TestUIElement, AppElement, FakeObserver>

    public let parent: FakeApplication
    public var window: Window {
        get { return Window(delegate: delegate!)! }
    }

    let element: EmittingTestWindowElement

    public var title: String {
        get { return try! element.attribute(.title)! }
        set { try! element.setAttribute(.title, value: newValue) }
    }
    public var frame: CGRect {
        get { return invert(try! element.attribute(.frame)!) }
        set { try! element.setAttribute(.frame, value: invert(newValue)) }
    }
    public var isMinimized: Bool {
        get { return try! element.attribute(.minimized)! }
        set { try! element.setAttribute(.minimized, value: newValue) }
    }
    public var isFullscreen: Bool {
        get { return try! element.attribute(.fullScreen)! }
        set { try! element.setAttribute(.fullScreen, value: newValue) }
    }

    fileprivate var delegate: Delegate?

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
        frame = CGRect(x: 300, y: 300, width: 600, height: 800)
        isMinimized = false
        isFullscreen = false
    }

    private func invert(_ rect: CGRect) -> CGRect {
        let inverted = CGPoint(x: rect.minX,
                               y: parent.parent.delegate.systemScreens.maxY - rect.maxY)
        return CGRect(origin: inverted, size: rect.size)
    }
}

public func ==(lhs: FakeWindow, rhs: FakeWindow) -> Bool {
    return lhs.element == rhs.element
}
extension FakeWindow: Equatable {}

extension FakeWindow: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "FakeWindow(\"\(title.truncate(length: 30))\")"
    }
}

public class FakeScreen {
    public var screen: Screen {
        get {
            return Screen(delegate: delegate)
        }
    }

    public init(frame: CGRect, applicationFrame: CGRect) {
        delegate = FakeScreenDelegate(frame: frame, applicationFrame: applicationFrame)
    }
    public convenience init(frame: CGRect, menuBarHeight: Int, dockHeight: Int) {
        let af = CGRect(x: frame.origin.x,
                        y: frame.origin.y + CGFloat(dockHeight),
                        width: frame.width,
                        height: frame.height - CGFloat(menuBarHeight + dockHeight))
        self.init(frame: frame, applicationFrame: af)
    }
    public convenience init(frame: CGRect) {
        self.init(frame: frame, menuBarHeight: 10, dockHeight: 50)
    }
    public convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    let delegate: FakeScreenDelegate
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
            return .value(nil)
        }
        return .value(getter(object))
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
