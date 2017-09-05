import AXSwift
import PromiseKit

/// The global Swindler state, lazily initialized.
public var state = State(delegate: OSXStateDelegate<AXSwift.UIElement, AXSwift.Application, AXSwift.Observer>(appObserver: ApplicationObserver()))

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
    return delegate.runningApplications.map{ Application(delegate: $0, stateDelegate: delegate) }
  }

  /// The frontmost application.
  public var frontmostApplication: WriteableProperty<OfOptionalType<Application>> { return delegate.frontmostApplication }

  /// All windows that we know about. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { return delegate.knownWindows.flatMap{ Window(delegate: $0) } }

  /// The physical screens in the current display configuration.
  public var screens: [Screen] { return delegate.screens.map{ Screen(delegate: $0) } }

  /// Calls `handler` when the specified `Event` occurs.
  public func on<Event: EventType>(_ handler: @escaping (Event) -> ()) { delegate.on(handler) }
}

// All public classes in Swindler are implemented with an internal delegate. This decoupling aids in
// testing and hides implementation details from the API.
//
// Our delegates differ from most Apple API delegates in that they are internal and are critical to
// the functioning of the class, so they are not held with weak references.
protocol StateDelegate: class {
  var runningApplications: [ApplicationDelegate] { get }
  var frontmostApplication: WriteableProperty<OfOptionalType<Application>>! { get }
  var knownWindows: [WindowDelegate] { get }
  var screens: [ScreenDelegate] { get }
  func on<Event: EventType>(_ handler: @escaping (Event) -> ())
}

// MARK: - OSXStateDelegate

/// An object responsible for propagating the given event. Used internally by the OSX delegates.
protocol EventNotifier: class {
  func notify<Event: EventType>(_ event: Event)
}

/// Wraps behavior needed to track the frontmost applications.
protocol ApplicationObserverType {
  var frontmostApplicationPID: pid_t? { get }
  func onFrontmostApplicationChanged(_ handler: @escaping () -> ())
  func onApplicationLaunched(_ handler: @escaping (pid_t) -> ())
  func onApplicationTerminated(_ handler: @escaping (pid_t) -> ())
  func makeApplicationFrontmost(_ pid: pid_t) throws
}

struct ApplicationObserver: ApplicationObserverType {
  var frontmostApplicationPID: pid_t? {
    return NSWorkspace.shared().frontmostApplication?.processIdentifier
  }

  func onFrontmostApplicationChanged(_ handler: @escaping () -> ()) {
    let sharedWorkspace    = NSWorkspace.shared()
    let notificationCenter = sharedWorkspace.notificationCenter

    // Err on the side of updating too often; watch both activate and deactivate notifications.
    notificationCenter.addObserver(
      forName: NSNotification.Name.NSWorkspaceDidActivateApplication, object: sharedWorkspace, queue: nil
    ) { _ in
      handler()
    }
    notificationCenter.addObserver(
      forName: NSNotification.Name.NSWorkspaceDidDeactivateApplication, object: sharedWorkspace, queue: nil
    ) { _ in
      handler()
    }
  }

  func onApplicationLaunched(_ handler: @escaping (pid_t) -> ()) {
    let sharedWorkspace    = NSWorkspace.shared()
    let notificationCenter = sharedWorkspace.notificationCenter
    notificationCenter.addObserver(
      forName: NSNotification.Name.NSWorkspaceDidLaunchApplication,
      object:  sharedWorkspace,
      queue:   nil
    ) { note in
      guard let userInfo = note.userInfo else {
        log.warn("Missing notification info on NSWorkspaceDidLaunchApplication")
        return
      }
      let runningApp = userInfo[NSWorkspaceApplicationKey] as! NSRunningApplication
      handler(runningApp.processIdentifier)
    }
  }

  func onApplicationTerminated(_ handler: @escaping (pid_t) -> ()) {
    let sharedWorkspace    = NSWorkspace.shared()
    let notificationCenter = sharedWorkspace.notificationCenter
    notificationCenter.addObserver(
      forName: NSNotification.Name.NSWorkspaceDidTerminateApplication,
      object:  sharedWorkspace,
      queue:   nil
    ) { note in
      guard let userInfo = note.userInfo else {
        log.warn("Missing notification info on NSWorkspaceDidTerminateApplication")
        return
      }
      let runningApp = userInfo[NSWorkspaceApplicationKey] as! NSRunningApplication
      handler(runningApp.processIdentifier)
    }
  }

  func makeApplicationFrontmost(_ pid: pid_t) throws {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
      throw OSXDriverError.runningApplicationNotFound(processID: pid)
    }
    app.activate(options: [])
  }
}

/// Wraps behavior needed to track screen layout changes.
protocol ScreenObserverType {
  func onScreenLayoutChanged(_ handler: @escaping () -> ())
  func allScreens() -> [NSScreen]?
}

struct ScreenObserver: ScreenObserverType {
  func onScreenLayoutChanged(_ handler: @escaping () -> ()) {
    let sharedApplication  = NSApplication.shared()
    let notificationCenter = NSWorkspace.shared().notificationCenter

    notificationCenter.addObserver(
      forName: NSNotification.Name.NSApplicationDidChangeScreenParameters, object: sharedApplication, queue: nil
    ) { _ in
      handler()
    }
  }

  func allScreens() -> [NSScreen]? {
    return NSScreen.screens()
  }
}

/// Implements StateDelegate using the AXUIElement API.
final class OSXStateDelegate<
    UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
  >: StateDelegate, EventNotifier
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
 {
  typealias WinDelegate = OSXWindowDelegate<UIElement, ApplicationElement, Observer>
  typealias AppDelegate = OSXApplicationDelegate<UIElement, ApplicationElement, Observer>
  fileprivate typealias EventHandler = (EventType) -> ()

  fileprivate var applicationsByPID: [pid_t: AppDelegate] = [:]
  fileprivate var eventHandlers: [String: [EventHandler]] = [:]

  // For convenience/readability.
  fileprivate var applications: LazyMapCollection<[pid_t: AppDelegate], AppDelegate> { return applicationsByPID.values }

  var runningApplications: [ApplicationDelegate] { return applications.map({ $0 as ApplicationDelegate }) }
  var frontmostApplication: WriteableProperty<OfOptionalType<Application>>!
  var knownWindows: [WindowDelegate] { return applications.flatMap({ $0.knownWindows }) }
  var screens: [ScreenDelegate]

  // TODO: retry instead of ignoring an app/window when timeouts are encountered during initialization?

  init(appObserver: ApplicationObserverType) {
    log.debug("Initializing Swindler")

    guard let nsScreens = NSScreen.screens() else {
      // TODO fail
      screens = []
      log.error("Could not initialize Swindler: NSScreen could not obtain screen information")
      return
    }
    screens = nsScreens.map{ OSXScreenDelegate(nsScreen: $0) }

//    screenObserver.onScreenLayoutChanged {
//      let (screens, event) = OSXScreenDelegate<NSScreen>.handleScreenChange(
//        newScreens: screenObserver.allScreens()!,
//        oldScreens: self.screens.map{ $0 as! OSXScreenDelegate<NSScreen> },
//        state: State(delegate: self)
//      )
//      self.screens = screens
//      self.notify(event)
//    }

    let appPromises = ApplicationElement.all().map(self.watchApplication)

    let (propertyInitPromise, propertyInit, propertyInitError) = Promise<Void>.pending()
    frontmostApplication = WriteableProperty(
      FrontmostApplicationPropertyDelegate(
        appFinder: self,
        appObserver: appObserver,
        initPromise: propertyInitPromise),
      withEvent: FrontmostApplicationChangedEvent.self, receivingObject: State.self, notifier: self)

    // Must add the observer after configuring frontmostApplication.
    appObserver.onFrontmostApplicationChanged(self.frontmostApplication.refresh)
    appObserver.onApplicationLaunched(self.onApplicationLaunch)
    appObserver.onApplicationTerminated(self.onApplicationTerminate)

    // Must not allow frontmostApplication to initialize until the observer is in place.
    when(fulfilled: appPromises).asVoid().then(execute: propertyInit).catch(execute: propertyInitError)

    frontmostApplication.initialized.catch { error in
      log.error("Caught error: \(error)")
    }.always {
      log.debug("Done initializing")
    }
  }

  func watchApplication(appElement: ApplicationElement) -> Promise<Void> {
    return watchApplication(appElement: appElement, retry: 0)
  }

  func watchApplication(appElement: ApplicationElement, retry: Int) -> Promise<Void> {
      return AppDelegate.initialize(axElement: appElement, stateDelegate: self, notifier: self).then { application in
        self.applicationsByPID[try application.axElement.pid()] = application
      }
      .asVoid()
      .recover { error -> Promise<Void> in
        if retry < 3 {
          return self.watchApplication(appElement: appElement, retry: retry+1)
        }
        throw error
      }.recover { error -> () in
        let pid = try? appElement.pid()
        let bundleID = pid.flatMap{NSRunningApplication(processIdentifier: $0)}.flatMap{$0.bundleIdentifier}
        let pidString = (pid == nil) ? "??" : String(pid!)
        log.notice("Could not watch application \(bundleID ?? "") (pid=\(pidString)): \(error)")
      }
  }

  func onApplicationLaunch(_ pid: pid_t) {
    guard let appElement = ApplicationElement(forProcessID: pid) else {
      return
    }
    watchApplication(appElement: appElement).then {
      self.frontmostApplication.refresh()
      // TODO: Send event
    }.catch { err in
      log.error("Error while refreshing frontmostApplication: \(String(describing: err))")
    }
  }

  func onApplicationTerminate(_ pid: pid_t) {
    guard let _ = self.applicationsByPID[pid] else {
      log.debug("Saw termination for unknown pid \(pid)")
      return
    }
    applicationsByPID.removeValue(forKey: pid)
    // TODO: Send event
    // TODO: Clean up observers?
  }

  func on<Event: EventType>(_ handler: @escaping (Event) -> ()) {
    let notification = Event.typeName
    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information that gets erased in the dictionary.
    eventHandlers[notification]!.append({ handler($0 as! Event) })
  }

  // TODO: extract this behavior to a self-contained Notifier struct
  func notify<Event: EventType>(_ event: Event) {
    assert(Thread.current.isMainThread)
    if let handlers = eventHandlers[Event.typeName] {
      for handler in handlers {
        handler(event)
      }
    }
  }
}

extension OSXStateDelegate: PropertyNotifier {
  typealias Object = State

  // TODO... can we get rid of this or simplify it?
  func notify<Event: PropertyEventType>(
    _ event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType
  ) where Event.Object == State {
    notify(Event(external: external, object: State(delegate: self), oldValue: oldValue, newValue: newValue))
  }

  /// Called when the underlying object has become invalid.
  func notifyInvalid() {
    assertionFailure("State can't become invalid")
  }
}

// MARK: PropertyDelegates

protocol AppFinder: class {
  func findAppByPID(_ pid: pid_t) -> Application?
}
extension OSXStateDelegate: AppFinder {
  func findAppByPID(_ pid: pid_t) -> Application? {
    guard let appDelegate = applicationsByPID[pid] else { return nil }
    return Application(delegate: appDelegate)
  }
}

private final class FrontmostApplicationPropertyDelegate: PropertyDelegate {
  typealias T = Application

  weak var appFinder: AppFinder?
  let appObserver: ApplicationObserverType
  let initPromise: Promise<Void>
  init(appFinder: AppFinder, appObserver: ApplicationObserverType, initPromise: Promise<Void>) {
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
      throw PropertyError.invalidObject(cause: error)
    }
  }

  func initialize() -> Promise<Application?> {
    // No need to run in background, the call happens instantly.
    return initPromise.then { return self.readValue() }
  }

  fileprivate func findAppByPID(_ pid: pid_t) -> Application? {
    // TODO extract into runOnMainThread util
    // Avoid using locks by forcing calls out to `windowFinder` to happen on the main thead.
    var app: Application? = nil
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
