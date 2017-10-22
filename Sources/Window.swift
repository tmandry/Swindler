import AXSwift
import PromiseKit

// MARK: - Window

/// A window.
public final class Window: Equatable {
    internal let delegate: WindowDelegate

    // A Window holds a strong reference to the Application and therefore the ApplicationDelegate.
    // It should not be held internally by delegates, or it would create a reference cycle.
    fileprivate var application_: Application!

    internal init(delegate: WindowDelegate, application: Application) {
        self.delegate = delegate
        application_ = application
    }

    /// This initializer fails only if the ApplicationDelegate is no longer reachable (because the
    /// application terminated, which means this window no longer exists), or the StateDelegate has
    /// been destroyed.
    internal convenience init?(delegate: WindowDelegate) {
        guard let appDelegate = delegate.appDelegate else {
            // The application terminated.
            log.debug("Window for delegate \(delegate) failed to initialize because of unreachable "
                    + "ApplicationDelegate")
            return nil
        }
        guard let app = Application(delegate: appDelegate) else {
            log.debug("Window for delegate \(delegate) failed to initialize because Application "
                    + "failed to initialize")
            return nil
        }
        self.init(delegate: delegate, application: app)
    }

    /// The application the window belongs to.
    public var application: Application { return application_ }

    /// The screen that (most of) the window is on. `nil` if the window is completely off-screen.
    public var screen: Screen? {
        let screenIntersectSizes =
            application.swindlerState.screens.lazy
            .map { screen in (screen, screen.frame.intersection(self.rect)) }
            .filter { _, intersect in !intersect.isNull }
            .map { screen, intersect in (screen, intersect.size.width * intersect.size.height) }
        let bestScreen = screenIntersectSizes.max { lhs, rhs in lhs.1 < rhs.1 }?.0
        return bestScreen
    }
    fileprivate var rect: CGRect { return CGRect(origin: position.value, size: size.value) }

    /// Whether or not the window referred to by this type remains valid. Windows usually become
    /// invalid because they are destroyed (in which case a WindowDestroyedEvent will be emitted).
    /// They can also become invalid because they do not have all the required properties, or
    /// because the application that owns them is otherwise not giving a well-behaved response.
    public var isValid: Bool { return delegate.isValid }

    /// The position of the top-left corner of the window in screen coordinates.
    public var position: WriteableProperty<OfType<CGPoint>> { return delegate.position }
    /// The size of the window in screen coordinates.
    public var size: WriteableProperty<OfType<CGSize>> { return delegate.size }

    /// The window title.
    public var title: Property<OfType<String>> { return delegate.title }

    /// Whether the window is minimized.
    public var isMinimized: WriteableProperty<OfType<Bool>> { return delegate.isMinimized }

    /// Whether the window is fullscreen or not.
    public var isFullscreen: WriteableProperty<OfType<Bool>> { return delegate.isFullscreen }
}
public func ==(lhs: Window, rhs: Window) -> Bool {
    return lhs.delegate.equalTo(rhs.delegate)
}

protocol WindowDelegate: class {
    var isValid: Bool { get }

    // Optional because a WindowDelegate shouldn't hold a strong reference to its parent
    // ApplicationDelegate.
    var appDelegate: ApplicationDelegate? { get }

    var position: WriteableProperty<OfType<CGPoint>>! { get }
    var size: WriteableProperty<OfType<CGSize>>! { get }
    var title: Property<OfType<String>>! { get }
    var isMinimized: WriteableProperty<OfType<Bool>>! { get }
    var isFullscreen: WriteableProperty<OfType<Bool>>! { get }

    func equalTo(_ other: WindowDelegate) -> Bool
}

// MARK: - OSXWindowDelegate

/// Implements WindowDelegate using the AXUIElement API.
final class OSXWindowDelegate<
    UIElement, ApplicationElement: ApplicationElementType, Observer: ObserverType
>: WindowDelegate, PropertyNotifier
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement {
    typealias Object = Window

    fileprivate weak var notifier: EventNotifier?
    fileprivate var initialized: Promise<Void>!

    let axElement: UIElement

    fileprivate(set) var isValid: Bool = true

    fileprivate var axProperties: [PropertyType]!
    fileprivate var watchedAxProperties: [AXSwift.AXNotification: [PropertyType]]!

    weak var appDelegate: ApplicationDelegate?

    var position: WriteableProperty<OfType<CGPoint>>!
    var size: WriteableProperty<OfType<CGSize>>!
    var title: Property<OfType<String>>!
    var isMinimized: WriteableProperty<OfType<Bool>>!
    var isFullscreen: WriteableProperty<OfType<Bool>>!

    fileprivate init(appDelegate: ApplicationDelegate,
                     notifier: EventNotifier?,
                     axElement: UIElement,
                     observer: Observer) throws {
        self.appDelegate = appDelegate
        self.notifier = notifier
        self.axElement = axElement

        // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
        let (initPromise, fulfill, reject) = Promise<[AXSwift.Attribute: Any]>.pending()

        // Initialize all properties.
        position = WriteableProperty(
            AXPropertyDelegate(axElement, .position, initPromise),
            withEvent: WindowPosChangedEvent.self,
            receivingObject: Window.self,
            notifier: self)
        size = WriteableProperty(
            AXPropertyDelegate(axElement, .size, initPromise),
            withEvent: WindowSizeChangedEvent.self,
            receivingObject: Window.self,
            notifier: self)
        title = Property(
            AXPropertyDelegate(axElement, .title, initPromise),
            withEvent: WindowTitleChangedEvent.self,
            receivingObject: Window.self,
            notifier: self)
        isMinimized = WriteableProperty(
            AXPropertyDelegate(axElement, .minimized, initPromise),
            withEvent: WindowMinimizedChangedEvent.self,
            receivingObject: Window.self,
            notifier: self)
        isFullscreen = WriteableProperty(
            AXPropertyDelegate(axElement, .fullScreen, initPromise),
            notifier: self)

        axProperties = [
            position,
            size,
            title,
            isMinimized,
            isFullscreen
        ]

        // Map notifications on this element to the corresponding property.
        watchedAxProperties = [
            .moved: [position],
            .resized: [size, isFullscreen],
            .titleChanged: [title],
            .windowMiniaturized: [isMinimized],
            .windowDeminiaturized: [isMinimized]
        ]

        // Start watching for notifications.
        let notifications = watchedAxProperties.keys + [
            .uiElementDestroyed
        ]
        let watched = watchWindowElement(axElement,
                                         observer: observer,
                                         notifications: notifications)

        // Fetch attribute values.
        let attributes = axProperties.map {($0.delegate as! AXPropertyDelegateType).attribute} + [
            .subrole
        ]
        fetchAttributes(
            attributes, forElement: axElement, after: watched, fulfill: fulfill, reject: reject
        )

        // Ignore windows with the "AXUnknown" role. This (undocumented) role shows up in several
        // places, including Chrome tooltips and OS X fullscreen transitions.
        let subroleChecked = initPromise.then { attributeValues -> Void in
            if attributeValues[.subrole] as! String? == "AXUnknown" {
                log.debug("Window \(axElement) has subrole AXUnknown, unwatching")
                self.unwatchWindowElement(
                    axElement, observer: observer, notifications: notifications
                ).catch { error in
                    log.warn("Error while unwatching ignored window \(axElement): \(error)")
                }
                throw OSXDriverError.windowIgnored(element: axElement)
            }
        }

        initialized =
            when(fulfilled: initializeProperties(axProperties, ofElement: axElement).asVoid(),
                 subroleChecked)
    }

    fileprivate func watchWindowElement(_ element: UIElement,
                                        observer: Observer,
                                        notifications: [AXNotification]) -> Promise<Void> {
        return Promise<Void>(value: ()).then(on: .global()) { () -> Void in
            for notification in notifications {
                try traceRequest(self.axElement, "addNotification", notification) {
                    try observer.addNotification(notification, forElement: self.axElement)
                }
            }
        }
    }

    fileprivate func unwatchWindowElement(_ element: UIElement,
                                          observer: Observer,
                                          notifications: [AXNotification]) -> Promise<Void> {
        return Promise<Void>(value: ()).then(on: .global()) { () -> Void in
            for notification in notifications {
                try traceRequest(self.axElement, "removeNotification", notification) {
                    try observer.removeNotification(notification, forElement: self.axElement)
                }
            }
        }
    }

    // Initializes the window and returns it as a Promise once it's ready.
    static func initialize(
        appDelegate: ApplicationDelegate,
        notifier: EventNotifier?,
        axElement: UIElement,
        observer: Observer
    ) -> Promise<OSXWindowDelegate> {
        return firstly { // capture thrown errors in promise
            let window = try OSXWindowDelegate(
                appDelegate: appDelegate, notifier: notifier, axElement: axElement,
                observer: observer
            )
            return window.initialized.then { window }
        }
    }

    func handleEvent(_ event: AXSwift.AXNotification, observer: Observer) {
        switch event {
        case .uiElementDestroyed:
            isValid = false
        default:
            if let properties = watchedAxProperties[event] {
                properties.forEach { $0.refresh() }
            } else {
                log.debug("Unknown event on \(self): \(event)")
            }
        }
    }

    func notify<Event: PropertyEventType>(
        _ event: Event.Type,
        external: Bool,
        oldValue: Event.PropertyType,
        newValue: Event.PropertyType
    ) where Event.Object == Window {
        guard let window = Window(delegate: self) else {
            // Application terminated already; shouldn't send events.
            return
        }
        notifier?.notify(
            Event(external: external, object: window, oldValue: oldValue, newValue: newValue)
        )
    }

    func notifyInvalid() {
        isValid = false
    }

    func equalTo(_ rhs: WindowDelegate) -> Bool {
        if let other = rhs as? OSXWindowDelegate {
            return axElement == other.axElement
        } else {
            return false
        }
    }
}
