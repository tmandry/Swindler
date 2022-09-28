import AXSwift
import Cocoa
import PromiseKit

/// Initializes a new Swindler state and returns it in a Promise.
public func initialize() -> Promise<State> {
    return try! Initializer(nil).promise
}

/// Initializes a new Swindler state and returns it in a Promise.
///
/// When supplied with a decoder in a correctly configured app environment (TODO),
/// Swindler remembers space IDs across restarts of the application and
/// operating system.
public func initialize(restoringFrom data: Data) throws -> Promise<State> {
    return try Initializer.restore(data).promise
}

typealias RealStateDelegate = OSXStateDelegate<
    AXSwift.UIElement,
    AXSwift.Application,
    AXSwift.Observer,
    ApplicationObserver
>

private class Initializer: Decodable {
    let promise: Promise<State>

    static func restore(_ recoveryData: Data) throws -> Initializer {
        let decoder = JSONDecoder()
        let initializer = try decoder.decode(Initializer.self, from: recoveryData)
        return initializer
    }

    required convenience init(from decoder: Decoder) throws {
        try self.init(decoder)
    }

    init(_ decoder: Decoder? = nil) throws {
        let notifier = EventNotifier()
        let ssd = OSXSystemScreenDelegate(notifier)
        var spaces: OSXSpaceObserver
        if let decoder = decoder {
            spaces = try OSXSpaceObserver(from: decoder, notifier, ssd, OSXSystemSpaceTracker())
        } else {
            spaces = OSXSpaceObserver(notifier, ssd, OSXSystemSpaceTracker())
        }
        promise = RealStateDelegate.initialize(notifier, ApplicationObserver(), ssd, spaces).map { delegate in
            State(delegate: delegate)
        }
    }
}

// TODO: Support AppKit automatic restoration
// - Don't initialize spaces until after application finishes launching by scheduling that on the dispatch queue (run loop won't start until restoration is complete, I think).. or finding a suitable event
// - During automatic restoration, save each tracker into a global list
// - Check the list before initializing space on startup
//
// This simplifies everything.

extension State {
    public func recoveryData() throws -> Data? {
        guard let delegate = delegate as? RealStateDelegate else { return nil }
        let encoder = JSONEncoder()
        return try encoder.encode(delegate.spaceObserver)
    }
}

// MARK: - State

/// The state represents the entire state of the OS, including all known windows, applications, and
/// spaces.
public final class State {
    let delegate: StateDelegate
    init(delegate: StateDelegate) {
        self.delegate = delegate
    }

    /// The currently running applications.
    public var runningApplications: [Application] {
        return delegate.runningApplications.map {Application(delegate: $0, stateDelegate: delegate)}
    }

    /// The frontmost application.
    public var frontmostApplication: WriteableProperty<OfOptionalType<Application>> {
        return delegate.frontmostApplication
    }

    /// All windows that we know about. Windows on spaces that we haven't seen yet aren't included.
    public var knownWindows: [Window] {
        return delegate.knownWindows.compactMap {Window(delegate: $0)}
    }

    /// The physical screens in the current display configuration.
    public var screens: [Screen] {
        return delegate.systemScreens.screens.map {Screen(delegate: $0)}
    }

    /// The main screen, if any.
    public var mainScreen: Screen? {
        return delegate.systemScreens.main.map {Screen(delegate: $0)}
    }

    /// Calls `handler` when the specified `Event` occurs.
    public func on<Event: EventType>(_ handler: @escaping (Event) -> Void) {
        delegate.notifier.on(handler)
    }
}

// All public classes in Swindler are implemented with an internal delegate. This decoupling aids in
// testing and hides implementation details from the API.
//
// Our delegates differ from most Apple API delegates in that they are internal and are critical to
// the functioning of the class, so they are not held with weak references.
protocol StateDelegate: AnyObject {
    var runningApplications: [ApplicationDelegate] { get }
    var frontmostApplication: WriteableProperty<OfOptionalType<Application>>! { get }
    var knownWindows: [WindowDelegate] { get }
    var systemScreens: SystemScreenDelegate { get }

    var notifier: EventNotifier { get }
}

// MARK: - OSXStateDelegate

/// Wraps behavior needed to track the frontmost applications.
protocol ApplicationObserverType {
    var frontmostApplicationPID: pid_t? { get }
    func onFrontmostApplicationChanged(_ handler: @escaping () -> Void)
    func onApplicationLaunched(_ handler: @escaping (pid_t) -> Void)
    func onApplicationTerminated(_ handler: @escaping (pid_t) -> Void)

    func makeApplicationFrontmost(_ pid: pid_t) throws

    associatedtype ApplicationElement: ApplicationElementType
    func allApplications() -> [ApplicationElement]
    func appElement(forProcessID processID: pid_t) -> ApplicationElement?
}

/// Simple pubsub.
class EventNotifier {
    private typealias EventHandler = (EventType) -> Void
    private var eventHandlers: [String: [EventHandler]] = [:]

    func on<Event: EventType>(_ handler: @escaping (Event) -> Void) {
        let notification = Event.typeName
        if eventHandlers[notification] == nil {
            eventHandlers[notification] = []
        }
        // Wrap in a casting closure to preserve type information that gets erased in the
        // dictionary.
        eventHandlers[notification]!.append({ handler($0 as! Event) })
    }

    func notify<Event: EventType>(_ event: Event) {
        assert(Thread.current.isMainThread)
        if let handlers = eventHandlers[Event.typeName] {
            for handler in handlers {
                handler(event)
            }
        }
    }
}

struct ApplicationObserver: ApplicationObserverType {
    var frontmostApplicationPID: pid_t? {
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func onFrontmostApplicationChanged(_ handler: @escaping () -> Void) {
        let sharedWorkspace = NSWorkspace.shared
        let notificationCenter = sharedWorkspace.notificationCenter

        // Err on the side of updating too often; watch both activate and deactivate notifications.
        notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: sharedWorkspace,
            queue: nil
        ) { _ in
            handler()
        }
        notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: sharedWorkspace,
            queue: nil
        ) { _ in
            handler()
        }
    }

    func onApplicationLaunched(_ handler: @escaping (pid_t) -> Void) {
        let sharedWorkspace = NSWorkspace.shared
        let notificationCenter = sharedWorkspace.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: sharedWorkspace,
            queue: nil
        ) { note in
            guard let userInfo = note.userInfo else {
                log.warn("Missing notification info on NSWorkspaceDidLaunchApplication")
                return
            }
            let runningApp = userInfo[NSWorkspace.applicationUserInfoKey] as! NSRunningApplication
            handler(runningApp.processIdentifier)
        }
    }

    func onApplicationTerminated(_ handler: @escaping (pid_t) -> Void) {
        let sharedWorkspace = NSWorkspace.shared
        let notificationCenter = sharedWorkspace.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: sharedWorkspace,
            queue: nil
        ) { note in
            guard let userInfo = note.userInfo else {
                log.warn("Missing notification info on NSWorkspaceDidTerminateApplication")
                return
            }
            let runningApp = userInfo[NSWorkspace.applicationUserInfoKey] as! NSRunningApplication
            handler(runningApp.processIdentifier)
        }
    }

    func makeApplicationFrontmost(_ pid: pid_t) throws {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            log.info("Could not find requested application to make frontmost with pid \(pid)")
            throw OSXDriverError.runningApplicationNotFound(processID: pid)
        }
        let success = try traceRequest(app, "activate", "") {
            app.activate(options: [NSApplication.ActivationOptions.activateIgnoringOtherApps])
        }
        if !success {
            log.debug("Failed to activate application \(app), it probably quit")
        }
    }

    typealias ApplicationElement = AXSwift.Application

    func allApplications() -> [ApplicationElement] {
        AXSwift.Application.all()
    }

    func appElement(forProcessID processID: pid_t) -> ApplicationElement? {
        return AXSwift.Application(forProcessID: processID)
    }
}

/// Implements StateDelegate using the AXUIElement API.
final class OSXStateDelegate<
    UIElement,
    ApplicationElement,
    Observer: ObserverType,
    ApplicationObserver: ApplicationObserverType
>: StateDelegate where
    Observer.UIElement == UIElement,
    ApplicationElement.UIElement == UIElement,
    ApplicationObserver.ApplicationElement == ApplicationElement
{
    typealias WinDelegate = OSXWindowDelegate<UIElement, ApplicationElement, Observer>
    typealias AppDelegate = OSXApplicationDelegate<UIElement, ApplicationElement, Observer>

    private var applicationsByPID: [pid_t: AppDelegate] = [:]

    // This should be the only strong reference to EventNotifier.
    var notifier: EventNotifier

    fileprivate var appObserver: ApplicationObserver
    fileprivate var spaceObserver: OSXSpaceObserver

    // For convenience/readability.
    fileprivate var applications: Dictionary<pid_t, AppDelegate>.Values {
        return applicationsByPID.values
    }

    var runningApplications: [ApplicationDelegate] {
        return applications.map({ $0 as ApplicationDelegate })
    }
    var frontmostApplication: WriteableProperty<OfOptionalType<Application>>!
    var knownWindows: [WindowDelegate] {
        return applications.flatMap({ $0.knownWindows })
    }
    var systemScreens: SystemScreenDelegate

    var spaceIds: [Int]!

    fileprivate var initialized: Promise<Void>!

    // TODO: retry instead of ignoring an app/window when timeouts are encountered during
    // initialization?

    static func initialize<Screens: SystemScreenDelegate>(
        _ notifier: EventNotifier,
        _ appObserver: ApplicationObserver,
        _ screens: Screens,
        _ spaces: OSXSpaceObserver
    ) -> Promise<OSXStateDelegate> {
        return firstly { () -> Promise<OSXStateDelegate> in
            let delegate = OSXStateDelegate(notifier, appObserver, screens, spaces)
            return delegate.initialized.map { delegate }
        }
    }

    // TODO make private
    init<Screens: SystemScreenDelegate>(
        _ notifier: EventNotifier,
        _ appObserver: ApplicationObserver,
        _ screens: Screens,
        _ spaces: OSXSpaceObserver
    ) {
        log.debug("Initializing Swindler")

        self.notifier = notifier
        systemScreens = screens
        self.appObserver = appObserver
        spaceObserver = spaces

        let appPromises = appObserver.allApplications().map { appElement in
            watchApplication(appElement: appElement)
            .asVoid()
            .recover { error -> Void in
                // drop errors
            }
        }

        let (propertyInitPromise, seal) = Promise<Void>.pending()
        frontmostApplication = WriteableProperty(
            FrontmostApplicationPropertyDelegate(
                appFinder: self,
                appObserver: appObserver,
                initPromise: propertyInitPromise),
            withEvent: FrontmostApplicationChangedEvent.self,
            receivingObject: State.self,
            notifier: self)
        let properties: [PropertyType] = [
            frontmostApplication
        ]

        // Must add the observer after configuring frontmostApplication.
        appObserver.onFrontmostApplicationChanged(frontmostApplication.issueRefresh)
        appObserver.onApplicationLaunched(onApplicationLaunch)
        appObserver.onApplicationTerminated(onApplicationTerminate)

        notifier.on { [weak self] (event: SpaceWillChangeEvent) in
            guard let self = self else { return }
            log.info("Space changed: \(event.ids)")
            self.spaceIds = event.ids

            for (idx, screen) in self.systemScreens.screens.enumerated() {
                screen.spaceId = event.ids[idx]
            }

            let updateWindows = self.applications.map { app in app.onSpaceChanged() }
            when(resolved: updateWindows).done { _ in
                // The space may have changed again in the meantime. Make sure
                // we only emit events consistent with the current state.
                // TODO needs a test
                if event.ids == self.spaceIds {
                    log.notice("Known windows updated")
                    self.notifier.notify(SpaceDidChangeEvent(external: true, ids: event.ids))
                }
            }.recover { error in
                log.error("Couldn't update window list after space change: \(error)")
            }
        }
        spaces.emitSpaceWillChangeEvent()

        // Must not allow frontmostApplication to initialize until the observer is in place.
        when(fulfilled: appPromises)
            //.asVoid()
            .done { seal.fulfill(()) }
            .catch(seal.reject)

        frontmostApplication.initialized.catch { error in
            log.error("Caught error initializing frontmostApplication: \(error)")
        }.finally {
            log.debug("Done initializing")
        }

        initialized = initializeProperties(properties).asVoid()
    }

    func watchApplication(appElement: ApplicationElement) -> Promise<AppDelegate> {
        return watchApplication(appElement: appElement, retry: 0)
    }

    func watchApplication(appElement: ApplicationElement, retry: Int) -> Promise<AppDelegate> {
        return AppDelegate.initialize(axElement: appElement, stateDelegate: self, notifier: notifier)
            .map { appDelegate in
                self.applicationsByPID[try appDelegate.axElement.pid()] = appDelegate
                return appDelegate
            }
            //.asVoid()
            .recover { error -> Promise<AppDelegate> in
                if retry < 3 {
                    return self.watchApplication(appElement: appElement, retry: retry + 1)
                }
                throw error
            }
            .recover { error -> Promise<AppDelegate> in
                // Log errors
                let pid = try? appElement.pid()
                let bundleID = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
                    .flatMap { $0.bundleIdentifier }
                let pidString = (pid == nil) ? "??" : String(pid!)
                log.trace("Could not watch application \(bundleID ?? "") (pid=\(pidString)): "
                         + String(describing: error))
                throw error
            }
    }
}

extension OSXStateDelegate {
    fileprivate func onApplicationLaunch(_ pid: pid_t) {
        guard let appElement = appObserver.appElement(forProcessID: pid) else {
            return
        }
        addAppElement(appElement).catch { err in
            log.error("Error while watching new application: \(String(describing: err))")
        }
    }

    // Also used by FakeSwindler.
    internal func addAppElement(_ appElement: ApplicationElement) -> Promise<AppDelegate> {
        watchApplication(appElement: appElement).map { appDelegate in
            self.notifier.notify(ApplicationLaunchedEvent(
                external: true,
                application: Application(delegate: appDelegate, stateDelegate: self)
            ))
            self.frontmostApplication.refresh()
            return appDelegate
        }
    }

    fileprivate func onApplicationTerminate(_ pid: pid_t) {
        guard let appDelegate = self.applicationsByPID[pid] else {
            log.debug("Saw termination for unknown pid \(pid)")
            return
        }
        applicationsByPID.removeValue(forKey: pid)
        notifier.notify(ApplicationTerminatedEvent(
            external: true,
            application: Application(delegate: appDelegate, stateDelegate: self)
        ))
        // TODO: Clean up observers?
    }
}

extension OSXStateDelegate: PropertyNotifier {
    typealias Object = State

    // TODO... can we get rid of this or simplify it?
    func notify<Event: PropertyEventType>(
        _ event: Event.Type,
        external: Bool,
        oldValue: Event.PropertyType,
        newValue: Event.PropertyType
    ) where Event.Object == State {
        notifier.notify(Event(external: external,
                        object: State(delegate: self),
                        oldValue: oldValue,
                        newValue: newValue))
    }

    /// Called when the underlying object has become invalid.
    func notifyInvalid() {
        assertionFailure("State can't become invalid")
    }
}

// MARK: PropertyDelegates

protocol AppFinder: AnyObject {
    func findAppByPID(_ pid: pid_t) -> Application?
}
extension OSXStateDelegate: AppFinder {
    func findAppByPID(_ pid: pid_t) -> Application? {
        guard let appDelegate = applicationsByPID[pid] else { return nil }
        return Application(delegate: appDelegate)
    }
}

private final class FrontmostApplicationPropertyDelegate<
    ApplicationObserver: ApplicationObserverType
>: PropertyDelegate {
    typealias T = Application

    weak var appFinder: AppFinder?
    let appObserver: ApplicationObserver
    let initPromise: Promise<Void>
    init(appFinder: AppFinder, appObserver: ApplicationObserver, initPromise: Promise<Void>) {
        self.appFinder = appFinder
        self.appObserver = appObserver
        self.initPromise = initPromise
    }

    func readValue() -> Application? {
        guard let pid = appObserver.frontmostApplicationPID else { return nil }
        guard let app = findAppByPID(pid) else { return nil }
        return app
    }

    func writeValue(_ newValue: Application) throws {
        let pid = newValue.delegate.processIdentifier
        do {
            try appObserver.makeApplicationFrontmost(pid!)
        } catch {
            log.debug("Failed to make application PID \(pid!) frontmost: \(error)")
            throw PropertyError.invalidObject(cause: error)
        }
    }

    func initialize() -> Promise<Application?> {
        // No need to run in background, the call happens instantly.
        return initPromise.map { self.readValue() }
    }

    fileprivate func findAppByPID(_ pid: pid_t) -> Application? {
        // TODO: extract into runOnMainThread util
        // Avoid using locks by forcing calls out to `windowFinder` to happen on the main thead.
        var app: Application?
        if Thread.current.isMainThread {
            app = appFinder?.findAppByPID(pid)
        } else {
            DispatchQueue.main.sync {
                app = self.appFinder?.findAppByPID(pid)
            }
        }
        return app
    }
}
