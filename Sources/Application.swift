import AXSwift
import PromiseKit

// MARK: - Application

/// A running application.
public final class Application {
    internal let delegate: ApplicationDelegate

    // An Application holds a strong reference to the State (and therefore the StateDelegate).
    // It should not be held internally by delegates, or it would create a reference cycle.
    internal var state_: State!

    internal init(delegate: ApplicationDelegate, stateDelegate: StateDelegate) {
        self.delegate = delegate
        state_ = State(delegate: stateDelegate)
    }

    /// This initializer only fails if the StateDelegate has been destroyed.
    internal convenience init?(delegate: ApplicationDelegate) {
        guard let stateDelegate = delegate.stateDelegate else {
            log.debug("Application for delegate \(delegate) failed to initialize because of "
                    + "unreachable StateDelegate")
            return nil
        }
        self.init(delegate: delegate, stateDelegate: stateDelegate)
    }

    public var processIdentifier: pid_t { return delegate.processIdentifier }
    public var bundleIdentifier: String? { return delegate.bundleIdentifier }

    /// The global Swindler state.
    public var swindlerState: State { return state_ }

    /// The known windows of the application. Windows on spaces that we haven't seen yet aren't
    /// included.
    public var knownWindows: [Window] {
        return delegate.knownWindows.compactMap({ Window(delegate: $0) })
    }

    /// The main window of the application.
    /// -Note: Setting this will bring the window forward to just below the main window of the
    ///        frontmost application.
    public var mainWindow: WriteableProperty<OfOptionalType<Window>> { return delegate.mainWindow }

    /// The focused (or key) window of the application, the one currently accepting keyboard input.
    /// Usually the same as the main window, or one of its helper windows such as a file open
    /// dialog.
    ///
    /// -Note: Sometimes the focused "window" is a sheet and not a window (i.e. it has no title bar
    ///        and cannot be moved by the user). In that case the value will be nil.
    public var focusedWindow: Property<OfOptionalType<Window>> { return delegate.focusedWindow }

    /// Whether the application is hidden.
    public var isHidden: WriteableProperty<OfType<Bool>> { return delegate.isHidden }
}

public func ==(lhs: Application, rhs: Application) -> Bool {
    return lhs.delegate.equalTo(rhs.delegate)
}
extension Application: Equatable {}

extension Application: CustomStringConvertible {
    public var description: String {
        return "Application(\(String(describing: delegate)))"
    }
}

public protocol ApplicationDelegate: class {
    var processIdentifier: pid_t! { get }
    var bundleIdentifier: String? { get }

    var stateDelegate: StateDelegate? { get }

    var knownWindows: [WindowDelegate] { get }

    var mainWindow: WriteableProperty<OfOptionalType<Window>>! { get }
    var focusedWindow: Property<OfOptionalType<Window>>! { get }
    var isHidden: WriteableProperty<OfType<Bool>>! { get }

    func equalTo(_ other: ApplicationDelegate) -> Bool
}

// MARK: - OSXApplicationDelegate

/// Implements ApplicationDelegate using the AXUIElement API.
final class OSXApplicationDelegate<
    UIElement,
    ApplicationElement: ApplicationElementType,
    Observer: ObserverType
>: ApplicationDelegate
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement {
    typealias Object = Application
    typealias WinDelegate = OSXWindowDelegate<UIElement, ApplicationElement, Observer>

    weak var stateDelegate: StateDelegate?
    fileprivate weak var notifier: EventNotifier?

    public let axElement: UIElement // internal for testing only
    internal var observer: Observer! // internal for testing only
    fileprivate var windows: [WinDelegate] = []

    // Used internally for deferring code until an OSXWindowDelegate has been initialized for a
    // given UIElement.
    fileprivate var newWindowHandler = NewWindowHandler<UIElement>()

    fileprivate var initialized: Promise<Void>!

    var mainWindow: WriteableProperty<OfOptionalType<Window>>!
    var focusedWindow: Property<OfOptionalType<Window>>!
    var isHidden: WriteableProperty<OfType<Bool>>!

    var processIdentifier: pid_t!
    lazy var runningApplication: NSRunningApplication =
        NSRunningApplication(processIdentifier: self.processIdentifier)!
    lazy var bundleIdentifier: String? =
        self.runningApplication.bundleIdentifier

    var knownWindows: [WindowDelegate] {
        return windows.map({ $0 as WindowDelegate })
    }

    /// Initializes the object and returns it as a Promise that resolves once it's ready.
    static func initialize(
        axElement: ApplicationElement,
        stateDelegate: StateDelegate,
        notifier: EventNotifier
    ) -> Promise<OSXApplicationDelegate> {
        return firstly { () -> Promise<OSXApplicationDelegate> in // capture thrown errors in promise chain
            let appDelegate = try OSXApplicationDelegate(axElement, stateDelegate, notifier)
            return appDelegate.initialized.map { appDelegate }
        }
    }

    init(_ axElement: ApplicationElement,
         _ stateDelegate: StateDelegate,
         _ notifier: EventNotifier) throws {
        // TODO: filter out applications by activation policy
        self.axElement = axElement.toElement
        self.stateDelegate = stateDelegate
        self.notifier = notifier
        processIdentifier = try axElement.pid()

        let notifications: [AXNotification] = [
            .windowCreated,
            .mainWindowChanged,
            .focusedWindowChanged,
            .applicationHidden,
            .applicationShown
        ]

        // Watch for notifications on app asynchronously.
        let appWatched = watchApplicationElement(notifications)
        // Get the list of windows asynchronously (after notifications are subscribed so we can't
        // miss one).
        let windowsFetched = fetchWindows(after: appWatched)

        // Create a promise for the attribute dictionary we'll get from fetchAttributes.
        let (attrsFetched, attrsSeal) = Promise<[AXSwift.Attribute: Any]>.pending()

        // Some properties can't initialize until we fetch the windows. (WindowPropertyAdapter)
        let initProperties =
            PromiseKit.when(fulfilled: attrsFetched, windowsFetched)
            .map { fetchedAttrs, _ in fetchedAttrs }

        // Configure properties.
        mainWindow = WriteableProperty(
            MainWindowPropertyDelegate(axElement,
                                       windowFinder: self,
                                       windowDelegate: WinDelegate.self,
                                       initProperties),
            withEvent: ApplicationMainWindowChangedEvent.self,
            receivingObject: Application.self,
            notifier: self)
        focusedWindow = Property(
            WindowPropertyAdapter(AXPropertyDelegate(axElement, .focusedWindow, initProperties),
                                  windowFinder: self,
                                  windowDelegate: WinDelegate.self),
            withEvent: ApplicationFocusedWindowChangedEvent.self,
            receivingObject: Application.self,
            notifier: self)
        isHidden = WriteableProperty(
            AXPropertyDelegate(axElement, .hidden, initProperties),
            withEvent: ApplicationIsHiddenChangedEvent.self,
            receivingObject: Application.self,
            notifier: self)

        let properties: [PropertyType] = [
            mainWindow,
            focusedWindow,
            isHidden
        ]
        let attributes: [Attribute] = [
            .mainWindow,
            .focusedWindow,
            .hidden
        ]

        // Fetch attribute values, after subscribing to notifications so there are no gaps.
        fetchAttributes(attributes,
                        forElement: axElement,
                        after: appWatched,
                        seal: attrsSeal)

        initialized = initializeProperties(properties).asVoid()
    }

    /// Called during initialization to set up an observer on the application element.
    fileprivate func watchApplicationElement(_ notifications: [AXNotification]) -> Promise<Void> {
        do {
            weak var weakSelf = self
            observer = try Observer(processID: processIdentifier, callback: { o, e, n in
                weakSelf?.handleEvent(observer: o, element: e, notification: n)
            })
        } catch {
            return Promise(error: error)
        }

        return Promise.value(()).done(on: .global()) {
            for notification in notifications {
                try traceRequest(self.axElement, "addNotification", notification) {
                    try self.observer.addNotification(notification, forElement: self.axElement)
                }
            }
        }
    }

    /// Called during initialization to fetch a list of window elements and initialize window
    /// delegates for them.
    fileprivate func fetchWindows(after promise: Promise<Void>) -> Promise<Void> {
        return promise.map(on: .global()) { () -> [UIElement]? in
            // Fetch the list of window elements.
            try traceRequest(self.axElement, "arrayAttribute", AXSwift.Attribute.windows) {
                return try self.axElement.arrayAttribute(.windows)
            }
        }.then { maybeWindowElements -> Promise<Void> in
            guard let windowElements = maybeWindowElements else {
                throw OSXDriverError.missingAttribute(attribute: .windows,
                                                      onElement: self.axElement)
            }

            // Initialize OSXWindowDelegates from the window elements.
            let windowPromises = windowElements.map({ windowElement in
                self.createWindowForElementIfNotExists(windowElement)
            })

            return successes(windowPromises, onError: { index, error in
                // Log any errors we encounter, but don't fail.
                let windowElement = windowElements[index]
                log.debug({
                    let description: String =
                        (try? windowElement.attribute(.description) ?? "") ?? ""
                    return "Couldn't initialize window for element \(windowElement) "
                         + "(\(description)) of \(self): \(error)"
                }())
            }).asVoid()
        }
    }

    /// Initializes an OSXWindowDelegate for the given axElement and adds it to `windows`, then
    /// calls newWindowHandler handlers for that window, if any. If the window has already been
    /// added, does nothing, and the returned promise resolves to nil.
    fileprivate func createWindowForElementIfNotExists(_ axElement: UIElement)
    -> Promise<WinDelegate?> {
        guard let systemScreens = stateDelegate?.systemScreens else {
            return .value(nil)
        }
        return WinDelegate.initialize(
            appDelegate: self, notifier: notifier, axElement: axElement, observer: observer,
            systemScreens: systemScreens
        ).map { windowDelegate in
            // This check needs to happen here, because it's possible (though rare) to call this
            // method from two different places (fetchWindows and onWindowCreated) before
            // initialization of either one is complete.
            if self.windows.contains(where: { $0.axElement == axElement }) {
                return nil
            }

            self.windows.append(windowDelegate)
            self.newWindowHandler.windowCreated(axElement)

            return windowDelegate
        }.recover { error -> Promise<WinDelegate?> in
            // If this initialization of WinDelegate failed, the window is somehow invalid and we
            // won't be seeing it again. Here we assume that if there were other initializations
            // requested, they won't succeed either.
            self.newWindowHandler.removeAllForUIElement(axElement)
            throw error
        }
    }

    func equalTo(_ rhs: ApplicationDelegate) -> Bool {
        if let other = rhs as? OSXApplicationDelegate {
            return axElement == other.axElement
        } else {
            return false
        }
    }
}

/// Event handlers
extension OSXApplicationDelegate {
    fileprivate func handleEvent(observer: Observer.Context,
                                 element: UIElement,
                                 notification: AXSwift.AXNotification) {
        assert(Thread.current.isMainThread)
        log.trace("Received \(notification) on \(element)")

        switch notification {
        case .windowCreated:
            onWindowCreated(element)
        case .mainWindowChanged:
            onWindowTypePropertyChanged(mainWindow, element: element)
        case .focusedWindowChanged:
            onWindowTypePropertyChanged(focusedWindow, element: element)
        case .applicationShown, .applicationHidden:
            isHidden.refresh()
        default:
            onWindowLevelEvent(notification, windowElement: element)
        }
    }

    fileprivate func onWindowCreated(_ windowElement: UIElement) {
        addWindowElement(windowElement).catch { error in
            log.debug("Could not watch window element on \(self): \(error)")
        }
    }

    internal func addWindowElement(_ windowElement: UIElement) -> Promise<WinDelegate?> {
        return firstly {
            createWindowForElementIfNotExists(windowElement)
        }.map { windowDelegate in
            guard let windowDelegate = windowDelegate,
                  let window = Window(delegate: windowDelegate)
            else { return nil }

            self.notifier?.notify(WindowCreatedEvent(external: true, window: window))
            return windowDelegate
        }
    }

    /// Does special handling for updating of properties that hold windows (mainWindow,
    /// focusedWindow).
    fileprivate func onWindowTypePropertyChanged(_ property: Property<OfOptionalType<Window>>,
                                                 element: UIElement) {
        if element == axElement {
            // Was passed the application (this means there is no main/focused window); we can
            // refresh immediately.
            property.refresh()
        } else if windows.contains(where: { $0.axElement == element }) {
            // Was passed an already-initialized window; we can refresh immediately.
            property.refresh()
        } else {
            // We don't know about the element that has been passed. Wait until the window is
            // initialized.
            newWindowHandler.performAfterWindowCreatedForElement(element) { property.refresh() }

            // In some cases, the element is actually IS the application element, but equality
            // checks inexplicably return false. (This has been observed for Finder.) In this case
            // we will never see a new window for this element. Asynchronously check the element
            // role to handle this case.
            checkIfWindowPropertyElementIsActuallyApplication(element, property: property)
        }
    }

    fileprivate func checkIfWindowPropertyElementIsActuallyApplication(
        _ element: UIElement,
        property: Property<OfOptionalType<Window>>
    ) {
        Promise.value(()).map(on: .global()) { () -> Role? in
            guard let role: String = try element.attribute(.role) else { return nil }
            return Role(rawValue: role)
        }.done { role in
            if role == .application {
                // There is no main window; we can refresh immediately.
                property.refresh()
                // Remove the handler that will never be called.
                self.newWindowHandler.removeAllForUIElement(element)
            }
        }.catch { error in
            switch error {
            case AXSwift.AXError.invalidUIElement:
                // The window is already gone.
                property.refresh()
                self.newWindowHandler.removeAllForUIElement(element)
            default:
                // TODO: Retry on timeout
                // Just refresh and hope for the best. Leave the handler in case the element does
                // show up again.
                property.refresh()
                log.warn("Received MainWindowChanged on unknown element \(element), then \(error) "
                       + "when trying to read its role")
            }
        }

        //  _______________________________
        // < Now that's a long method name >
        //  -------------------------------
        // \                             .       .
        //  \                           / `.   .' "
        //   \                  .---.  <    > <    >  .---.
        //    \                 |    \  \ - ~ ~ - /  /    |
        //          _____          ..-~             ~-..-~
        //         |     |   \~~~\.'                    `./~~~/
        //        ---------   \__/                        \__/
        //       .'  O    \     /               /       \  "
        //      (_____,    `._.'               |         }  \/~~~/
        //       `----.          /       }     |        /    \__/
        //             `-.      |       /      |       /      `. ,~~|
        //                 ~-.__|      /_ - ~ ^|      /- _      `..-'
        //                      |     /        |     /     ~-.     `-. _  _  _
        //                      |_____|        |_____|         ~ - . _ _ _ _ _>
    }

    fileprivate func onWindowLevelEvent(_ notification: AXSwift.AXNotification,
                                        windowElement: UIElement) {
        func handleEvent(_ windowDelegate: WinDelegate) {
            windowDelegate.handleEvent(notification, observer: observer)

            if .uiElementDestroyed == notification {
                // Remove window.
                windows = windows.filter({ !$0.equalTo(windowDelegate) })

                guard let window = Window(delegate: windowDelegate) else { return }
                notifier?.notify(WindowDestroyedEvent(external: true, window: window))
            }
        }

        if let windowDelegate = findWindowDelegateByElement(windowElement) {
            handleEvent(windowDelegate)
        } else {
            log.debug("Notification \(notification) on unknown element \(windowElement), deferring")
            newWindowHandler.performAfterWindowCreatedForElement(windowElement) {
                if let windowDelegate = self.findWindowDelegateByElement(windowElement) {
                    handleEvent(windowDelegate)
                } else {
                    // Window was already destroyed.
                    log.debug("Deferred notification \(notification) on window element "
                            + "\(windowElement) never reached delegate")
                }
            }
        }
    }

    fileprivate func findWindowDelegateByElement(_ axElement: UIElement) -> WinDelegate? {
        return windows.filter({ $0.axElement == axElement }).first
    }
}

extension OSXApplicationDelegate: PropertyNotifier {
    func notify<Event: PropertyEventType>(_ event: Event.Type,
                                          external: Bool,
                                          oldValue: Event.PropertyType,
                                          newValue: Event.PropertyType)
        where Event.Object == Application {
        guard let application = Application(delegate: self) else { return }
        notifier?.notify(
            Event(external: external, object: application, oldValue: oldValue, newValue: newValue)
        )
    }

    func notifyInvalid() {
        log.debug("Application invalidated: \(self)")
        // TODO:
    }
}

extension OSXApplicationDelegate: CustomStringConvertible {
    var description: String {
        do {
            let pid = try self.axElement.pid()
            if let app = NSRunningApplication(processIdentifier: pid),
               let bundle = app.bundleIdentifier {
                return bundle
            }
            return "pid=\(pid)"
        } catch {
            return "Invalid"
        }
    }
}

// MARK: Support

/// Stores internal new window handlers for OSXApplicationDelegate.
private struct NewWindowHandler<UIElement: Equatable> {
    fileprivate var handlers: [HandlerType<UIElement>] = []

    mutating func performAfterWindowCreatedForElement(_ windowElement: UIElement,
                                                      handler: @escaping () -> Void) {
        assert(Thread.current.isMainThread)
        handlers.append(HandlerType(windowElement: windowElement, handler: handler))
    }

    mutating func removeAllForUIElement(_ windowElement: UIElement) {
        assert(Thread.current.isMainThread)
        handlers = handlers.filter({ $0.windowElement != windowElement })
    }

    mutating func windowCreated(_ windowElement: UIElement) {
        assert(Thread.current.isMainThread)
        handlers.filter({ $0.windowElement == windowElement }).forEach { entry in
            entry.handler()
        }
        removeAllForUIElement(windowElement)
    }
}
private struct HandlerType<UIElement> {
    let windowElement: UIElement
    let handler: () -> Void
}

// MARK: PropertyDelegates

/// Used by WindowPropertyAdapter to match a UIElement to a Window object.
protocol WindowFinder: class {
    // This would be more elegantly implemented by passing the list of delegates with every refresh
    // request, but currently we don't have a way of piping that through.
    associatedtype UIElement: UIElementType
    func findWindowByElement(_ element: UIElement) -> Window?
}
extension OSXApplicationDelegate: WindowFinder {
    func findWindowByElement(_ element: UIElement) -> Window? {
        if let windowDelegate = findWindowDelegateByElement(element) {
            return Window(delegate: windowDelegate)
        } else {
            return nil
        }
    }
}

public protocol OSXDelegateType {
    associatedtype UIElement: UIElementType
    var axElement: UIElement { get }
    var isValid: Bool { get }
}
extension OSXWindowDelegate: OSXDelegateType {}

/// Custom PropertyDelegate for the mainWindow property.
private final class MainWindowPropertyDelegate<
    AppElement: ApplicationElementType,
    WinFinder: WindowFinder,
    WinDelegate: OSXDelegateType
>: PropertyDelegate
    where WinFinder.UIElement == WinDelegate.UIElement {
    typealias T = Window
    typealias UIElement = WinFinder.UIElement

    let readDelegate: WindowPropertyAdapter<AXPropertyDelegate<UIElement, AppElement>,
                                            WinFinder, WinDelegate>

    init(_ appElement: AppElement,
         windowFinder: WinFinder,
         windowDelegate: WinDelegate.Type,
         _ initPromise: Promise<[Attribute: Any]>) {
        readDelegate = WindowPropertyAdapter(
            AXPropertyDelegate(appElement, .mainWindow, initPromise),
            windowFinder: windowFinder,
            windowDelegate: windowDelegate)
    }

    func initialize() -> Promise<Window?> {
        return readDelegate.initialize()
    }

    func readValue() throws -> Window? {
        return try readDelegate.readValue()
    }

    func writeValue(_ newValue: Window) throws {
        // Extract the element from the window delegate.
        guard let winDelegate = newValue.delegate as? WinDelegate else {
            throw PropertyError.illegalValue
        }
        // Check early to see if the element is still valid. If it becomes invalid after this check,
        // the same error will get thrown, it will just take longer.
        guard winDelegate.isValid else {
            throw PropertyError.illegalValue
        }

        // Note: This is happening on a background thread, so only properties that don't change
        // should be accessed (the axElement).

        // To set the main window, we have to access the .main attribute of the window element and
        // set it to true.
        let writeDelegate = AXPropertyDelegate<Bool, UIElement>(
            winDelegate.axElement, .main, Promise.value([:])
        )
        try writeDelegate.writeValue(true)
    }
}

/// Converts a UIElement attribute into a readable Window property.
private final class WindowPropertyAdapter<
    Delegate: PropertyDelegate,
    WinFinder: WindowFinder,
    WinDelegate: OSXDelegateType
>: PropertyDelegate
    where Delegate.T == WinFinder.UIElement, WinFinder.UIElement == WinDelegate.UIElement {
    typealias T = Window

    let delegate: Delegate
    weak var windowFinder: WinFinder?

    init(_ delegate: Delegate, windowFinder: WinFinder, windowDelegate: WinDelegate.Type) {
        self.delegate = delegate
        self.windowFinder = windowFinder
    }

    func readValue() throws -> Window? {
        guard let element = try delegate.readValue() else {
            return nil
        }
        let window = findWindowByElement(element)
        if window == nil {
            // This can happen if, for instance, the window was destroyed since the refresh was
            // requested.
            log.debug("While updating property value, could not find window matching element: "
                    + String(describing: element))
        }
        return window
    }

    func writeValue(_ newValue: Window) throws {
        // If we got here, a property is wrongly configured.
        fatalError("Writing directly to an \"object\" property is not supported by the AXUIElement "
                 + "API")
    }

    func initialize() -> Promise<Window?> {
        return delegate.initialize().map { maybeElement in
            guard let element = maybeElement else {
                return nil
            }
            return self.findWindowByElement(element)
        }
    }

    fileprivate func findWindowByElement(_ element: Delegate.T) -> Window? {
        // Avoid using locks by forcing calls out to `windowFinder` to happen on the main thead.
        var window: Window?
        if Thread.current.isMainThread {
            window = windowFinder?.findWindowByElement(element)
        } else {
            DispatchQueue.main.sync {
                window = self.windowFinder?.findWindowByElement(element)
            }
        }
        return window
    }
}
