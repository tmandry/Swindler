import AXSwift
import PromiseKit

/// The global Swindler state, lazily initialized.
public var state = State(delegate: OSXStateDelegate<AXSwift.UIElement, AXSwift.Application, AXSwift.Observer>(appObserver: ApplicationObserver()))

/// An object responsible for propagating the given event. Used internally by the OSX delegates.
protocol EventNotifier: class {
  func notify<Event: EventType>(event: Event)
}

/// Wraps behavior needed to track the frontmost applications.
protocol ApplicationObserverType {
  var frontmostApplicationPID: pid_t? { get }
  func onFrontmostApplicationChanged(handler: () -> ())
  func makeApplicationFrontmost(pid: pid_t) throws
}

struct ApplicationObserver: ApplicationObserverType {
  var frontmostApplicationPID: pid_t? {
    return NSWorkspace.sharedWorkspace().frontmostApplication?.processIdentifier
  }

  func onFrontmostApplicationChanged(handler: () -> ()) {
    let sharedWorkspace    = NSWorkspace.sharedWorkspace()
    let notificationCenter = sharedWorkspace.notificationCenter

    // Err on the side of updating too often; watch both activate and deactivate notifications.
    notificationCenter.addObserverForName(
      NSWorkspaceDidActivateApplicationNotification, object: sharedWorkspace, queue: nil
    ) { _ in
      handler()
    }
    notificationCenter.addObserverForName(
      NSWorkspaceDidDeactivateApplicationNotification, object: sharedWorkspace, queue: nil
    ) { _ in
      handler()
    }
  }

  func makeApplicationFrontmost(pid: pid_t) throws {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
      throw OSXDriverError.RunningApplicationNotFound(processID: pid)
    }
    app.activateWithOptions([])
  }
}

/// Implements StateDelegate using the AXUIElement API.
final class OSXStateDelegate<
    UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: StateDelegate, EventNotifier {
  typealias WinDelegate = OSXWindowDelegate<UIElement, ApplicationElement, Observer>
  typealias AppDelegate = OSXApplicationDelegate<UIElement, ApplicationElement, Observer>
  private typealias EventHandler = (EventType) -> ()

  private var applicationsByPID: [pid_t: AppDelegate] = [:]
  private var eventHandlers: [String: [EventHandler]] = [:]

  // For convenience/readability.
  private var applications: LazyMapCollection<[pid_t: AppDelegate], AppDelegate> { return applicationsByPID.values }

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

    let appPromises = ApplicationElement.all().map { appElement in
      return AppDelegate.initialize(axElement: appElement, notifier: self).then { application in
        self.applicationsByPID[try application.axElement.pid()] = application
      }.asVoid().recover { error -> () in
        let pid = try? appElement.pid()
        let bundleID = pid.flatMap{NSRunningApplication(processIdentifier: $0)}.flatMap{$0.bundleIdentifier}
        let pidString = (pid == nil) ? "??" : String(pid!)
        log.notice("Could not watch application \(bundleID ?? "") (pid=\(pidString)): \(error)")
      }
    }

    let (propertyInit, fulfill, _) = Promise<Void>.pendingPromise()
    frontmostApplication = WriteableProperty(
      FrontmostApplicationPropertyDelegate(appFinder: self, appObserver: appObserver, initPromise: propertyInit),
      withEvent: FrontmostApplicationChangedEvent.self, receivingObject: State.self, notifier: self)

    // Must add the observer after configuring frontmostApplication.
    appObserver.onFrontmostApplicationChanged {
      self.frontmostApplication.refresh()
    }

    // Must not allow frontmostApplication to initialize until the observer is in place.
    when(appPromises).asVoid().then(fulfill)

    frontmostApplication.initialized.then {
      log.debug("Done initializing")
    }
  }

  func on<Event: EventType>(handler: (Event) -> ()) {
    let notification = Event.typeName
    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information that gets erased in the dictionary.
    eventHandlers[notification]!.append({ handler($0 as! Event) })
  }

  // TODO: extract this behavior to a self-contained Notifier struct
  func notify<Event: EventType>(event: Event) {
    assert(NSThread.currentThread().isMainThread)
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
  func notify<Event: PropertyEventType where Event.Object == State>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notify(Event(external: external, object: State(delegate: self), oldValue: oldValue, newValue: newValue))
  }

  /// Called when the underlying object has become invalid.
  func notifyInvalid() {
    assertionFailure("State can't become invalid")
  }
}

protocol AppFinder: class {
  func findAppByPID(pid: pid_t) -> Application?
}
extension OSXStateDelegate: AppFinder {
  func findAppByPID(pid: pid_t) -> Application? {
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

  func writeValue(newValue: Application) throws {
    let pid = newValue.delegate.processID
    do {
      try appObserver.makeApplicationFrontmost(pid)
    } catch {
      throw PropertyError.InvalidObject(cause: error)
    }
  }

  func initialize() -> Promise<Application?> {
    // No need to run in background, the call happens instantly.
    return initPromise.then { return self.readValue() }
  }

  private func findAppByPID(pid: pid_t) -> Application? {
    // TODO extract into runOnMainThread util
    // Avoid using locks by forcing calls out to `windowFinder` to happen on the main thead.
    var app: Application? = nil
    if NSThread.currentThread().isMainThread {
      app = appFinder?.findAppByPID(pid)
    } else {
      dispatch_sync(dispatch_get_main_queue()) {
        app = self.appFinder?.findAppByPID(pid)
      }
    }
    return app
  }
}
