import AXSwift
import PromiseKit

/// Implements ApplicationDelegate using the AXUIElement API.
class OSXApplicationDelegate<
  UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
  where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: ApplicationDelegate, PropertyNotifier {
  typealias Object = Application
  typealias WinDelegate = OSXWindowDelegate<UIElement, ApplicationElement, Observer>

  private weak var notifier: EventNotifier?
  internal let axElement: UIElement  // internal for testing only
  internal var observer: Observer!  // internal for testing only
  private var windows: [WinDelegate] = []

  // Used internally for deferring code until an OSXWindowDelegate has been initialized for a given
  // UIElement.
  private var newWindowHandler = NewWindowHandler<UIElement>()

  private var initialized: Promise<Void>!

  var mainWindow: WriteableProperty<OfOptionalType<Window>>!
  var focusedWindow: Property<OfOptionalType<Window>>!
  var isFrontmost: WriteableProperty<OfType<Bool>>!
  var isHidden: WriteableProperty<OfType<Bool>>!

  var processID: pid_t!
  var knownWindows: [WindowDelegate] {
    return windows.map({ $0 as WindowDelegate })
  }

  private init(axElement: ApplicationElement, notifier: EventNotifier) throws {
    // TODO: filter out applications by activation policy
    self.axElement = axElement.toElement
    self.notifier = notifier
    self.processID = try axElement.pid()

    let notifications: [Notification] = [
      .WindowCreated,
      .MainWindowChanged,
      .FocusedWindowChanged,
      .ApplicationActivated,
      .ApplicationDeactivated,
      .ApplicationHidden,
      .ApplicationShown
    ]

    // Watch for notifications on app asynchronously.
    let appWatched     = watchApplicationElement(notifications)
    // Get the list of windows asynchronously (after notifications are subscribed so we can't miss one).
    let windowsFetched = fetchWindows(after: appWatched)

    // Create a promise for the attribute dictionary we'll get from fetchAttributes.
    let (attrsFetched, fulfillAttrs, rejectAttrs) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()

    // Some properties can't initialize until we fetch the windows. (WindowPropertyAdapter)
    let initProperties =
      when(attrsFetched, windowsFetched)
      .then({ (fetchedAttrs, _) in fetchedAttrs })
      .recover(unwrapWhenErrors)

    // Configure properties.
    mainWindow = WriteableProperty<OfOptionalType<Window>>(
        MainWindowPropertyDelegate(axElement, windowFinder: self, windowDelegate: WinDelegate.self, initProperties),
      withEvent: ApplicationMainWindowChangedEvent.self, receivingObject: Application.self, notifier: self)
    focusedWindow = Property<OfOptionalType<Window>>(
      WindowPropertyAdapter.init(AXPropertyDelegate(axElement, .FocusedWindow, initProperties),
        windowFinder: self, windowDelegate: WinDelegate.self),
      withEvent: ApplicationFocusedWindowChangedEvent.self, receivingObject: Application.self, notifier: self)
    isFrontmost = WriteableProperty<OfType<Bool>>(AXPropertyDelegate(axElement, .Frontmost, initProperties),
      withEvent: ApplicationIsFrontmostChangedEvent.self, receivingObject: Application.self, notifier: self)
    isHidden = WriteableProperty<OfType<Bool>>(AXPropertyDelegate(axElement, .Hidden, initProperties),
      withEvent: ApplicationIsHiddenChangedEvent.self, receivingObject: Application.self, notifier: self)

    let properties: [PropertyType] = [
      mainWindow,
      focusedWindow,
      isFrontmost,
      isHidden
    ]
    let attributes: [Attribute] = [
      .MainWindow,
      .FocusedWindow,
      .Frontmost,
      .Hidden
    ]

    // Fetch attribute values, after subscribing to notifications so there are no gaps.
    fetchAttributes(attributes, forElement: axElement, after: appWatched, fulfill: fulfillAttrs, reject: rejectAttrs)

    initialized = initializeProperties(properties, ofElement: axElement).asVoid()
  }

  /// Called during initialization to set up an observer on the application element.
  private func watchApplicationElement(notifications: [Notification]) -> Promise<Void> {
    do {
      weak var weakSelf = self
      observer = try Observer(processID: self.processID, callback: { o, e, n in
        weakSelf?.handleEvent(observer: o, element: e, notification: n)
      })
    } catch {
      return Promise(error: error)
    }

    return Promise<Void>().thenInBackground { () -> () in
      for notification in notifications {
        try traceRequest(self.axElement, "addNotification", notification) {
          try self.observer.addNotification(notification, forElement: self.axElement)
        }
      }
    }
  }

  /// Called during initialization to fetch a list of window elements and initialize window delegates for them.
  private func fetchWindows(after promise: Promise<Void>) -> Promise<Void> {
    return promise.thenInBackground { () -> [UIElement]? in
      // Fetch the list of window elements.
      return try self.axElement.arrayAttribute(.Windows)
    }.then { maybeWindowElements -> Promise<[WinDelegate]> in
      guard let windowElements = maybeWindowElements else {
        throw OSXDriverError.MissingAttribute(attribute: .Windows, onElement: self.axElement)
      }

      // Initialize OSXWindowDelegates from the window elements.
      let windowPromises = windowElements.map({ windowElement in
        WinDelegate.initialize(
            appDelegate: self, notifier: self.notifier, axElement: windowElement, observer: self.observer)
      })

      return successes(windowPromises, onError: { index, error in
        // Log any errors we encounter, but don't fail.
        log.debug({
          let windowElement = windowElements[index]
          let description: String = (try? windowElement.attribute(.Description) ?? "") ?? ""
          return "Couldn't initialize window for element \(windowElement) (\(description)) of \(self): \(error)"
        }())
      })
    }.then { windowDelegates -> () in
      self.windows = windowDelegates

      // Now we can process any events received during initialization that depended on these windows.
      for windowDelegate in windowDelegates {
        self.newWindowHandler.windowCreated(windowDelegate.axElement)
      }
    }
  }

  /// Initializes the object and returns it as a Promise that resolves once it's ready.
  static func initialize(axElement axElement: ApplicationElement, notifier: EventNotifier) -> Promise<OSXApplicationDelegate> {
    return firstly {  // capture thrown errors in promise chain
      let appDelegate = try OSXApplicationDelegate(axElement: axElement, notifier: notifier)
      return appDelegate.initialized.then { return appDelegate }
    }
  }

  private func handleEvent(observer observer: Observer, element: UIElement, notification: AXSwift.Notification) {
    assert(NSThread.currentThread().isMainThread)
    log.trace("Received \(notification) on \(element)")

    switch notification {
    case .WindowCreated:
      onWindowCreated(element)
    case .MainWindowChanged:
      onWindowTypePropertyChanged(mainWindow, element: element)
    case .FocusedWindowChanged:
      onWindowTypePropertyChanged(focusedWindow, element: element)
    case .ApplicationActivated, .ApplicationDeactivated:
      isFrontmost.refresh() as ()
    case .ApplicationShown, .ApplicationHidden:
      isHidden.refresh() as ()
    default:
      onWindowEvent(notification, windowElement: element)
    }
  }

  private func onWindowCreated(windowElement: UIElement) {
    WinDelegate.initialize(appDelegate: self, notifier: notifier, axElement: windowElement, observer: observer).then { windowDelegate -> () in
      let window = Window(delegate: windowDelegate, appDelegate: self)
      self.windows.append(windowDelegate)
      self.notifier?.notify(WindowCreatedEvent(external: true, window: window))
      self.newWindowHandler.windowCreated(windowElement)
    }.error { error in
      log.debug("Could not watch \(windowElement): \(error)")
    }
  }

  /// Does special handling for updating of properties that hold windows (mainWindow, focusedWindow).
  private func onWindowTypePropertyChanged(property: Property<OfOptionalType<Window>>, element: UIElement) {
    if element == axElement {
      // Was passed the application (this means there is no main/focused window); we can refresh immediately.
      property.refresh() as ()
    } else if windows.contains({ $0.axElement == element }) {
      // Was passed an already-initialized window; we can refresh immediately.
      property.refresh() as ()
    } else {
      // We don't know about the element that has been passed. Wait until the window is initialized.
      newWindowHandler.performAfterWindowCreatedForElement(element) { property.refresh() }

      // In some cases, the element is actually IS the application element, but equality checks
      // inexplicably return false. (This has been observed for Finder.) In this case we will never
      // see a new window for this element. Asynchronously check the element role to handle this case.
      checkIfWindowPropertyElementIsActuallyApplication(element, property: property)
    }
  }

  private func checkIfWindowPropertyElementIsActuallyApplication(element: UIElement, property: Property<OfOptionalType<Window>>) {
    Promise<Void>().thenInBackground { () -> Role? in
      guard let role: String = try element.attribute(.Role) else { return nil }
      return Role(rawValue: role)
    }.then { role -> () in
      if role == .Application {
        // There is no main window; we can refresh immediately.
        property.refresh() as ()
        // Remove the handler that will never be called.
        self.newWindowHandler.removeAllForUIElement(element)
      }
    }.error { error in
      switch error {
      case AXSwift.Error.InvalidUIElement:
        // The window is already gone.
        property.refresh() as ()
        self.newWindowHandler.removeAllForUIElement(element)
      default:
        // TODO: Retry on timeout
        // Just refresh and hope for the best. Leave the handler in case the element does show up again.
        property.refresh() as ()
        log.warn("Received MainWindowChanged on unknown element \(element), then \(error) when " +
                 "trying to read its role")
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

  private func onWindowEvent(notification: AXSwift.Notification, windowElement: UIElement) {
    func handleEvent(windowDelegate: WinDelegate) {
      windowDelegate.handleEvent(notification, observer: observer)

      if .UIElementDestroyed == notification {
        // Remove window.
        windows = windows.filter({ !$0.equalTo(windowDelegate) })

        let window = Window(delegate: windowDelegate, appDelegate: self)
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
          log.debug("Deferred notification \(notification) on window element \(windowElement) never reached delegate")
        }
      }
    }
  }

  func notify<Event: PropertyEventTypeInternal where Event.Object == Application>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notifier?.notify(Event(external: external, object: Application(delegate: self), oldValue: oldValue, newValue: newValue))
  }

  func notifyInvalid() {
    log.debug("Application invalidated: \(self)")
    // TODO
  }

  private func findWindowDelegateByElement(axElement: UIElement) -> WinDelegate? {
    return windows.filter({ $0.axElement == axElement }).first
  }

  func equalTo(rhs: ApplicationDelegate) -> Bool {
    if let other = rhs as? OSXApplicationDelegate {
      return self.axElement == other.axElement
    } else {
      return false
    }
  }
}

extension OSXApplicationDelegate: CustomStringConvertible {
  var description: String {
    do {
      guard let app = NSRunningApplication(processIdentifier: try self.axElement.pid()) else {
        return "Unknown"
      }
      return app.bundleIdentifier ?? "Unknown"
    } catch {
      return "Invalid"
    }
  }
}

/// Stores internal new window handlers for OSXApplicationDelegate.
private struct NewWindowHandler<UIElement: Equatable> {
  private var handlers: [HandlerType<UIElement>] = []

  mutating func performAfterWindowCreatedForElement(windowElement: UIElement, handler: Void -> Void) {
    assert(NSThread.currentThread().isMainThread)
    handlers.append(HandlerType(windowElement: windowElement, handler: handler))
  }

  mutating func removeAllForUIElement(windowElement: UIElement) {
    assert(NSThread.currentThread().isMainThread)
    handlers = handlers.filter({ $0.windowElement != windowElement })
  }

  mutating func windowCreated(windowElement: UIElement) {
    assert(NSThread.currentThread().isMainThread)
    handlers.filter({ $0.windowElement == windowElement }).forEach { entry in
      entry.handler()
    }
    removeAllForUIElement(windowElement)
  }
}
private struct HandlerType<UIElement> {
  let windowElement: UIElement
  let handler: Void -> Void
}

/// Used by WindowPropertyAdapter to match a UIElement to a Window object.
protocol WindowFinder: class {
  // This would be more elegantly implemented by passing the list of delegates with every refresh
  // request, but currently we don't have a way of piping that through.
  typealias UIElement: UIElementType
  func findWindowByElement(element: UIElement) -> Window?
}
extension OSXApplicationDelegate: WindowFinder {
  func findWindowByElement(element: UIElement) -> Window? {
    if let windowDelegate = findWindowDelegateByElement(element) {
      return Window(delegate: windowDelegate)
    } else {
      return nil
    }
  }
}

protocol OSXDelegateType {
  typealias UIElement: UIElementType
  var axElement: UIElement { get }
  var isValid: Bool { get }
}
extension OSXWindowDelegate: OSXDelegateType {}

/// Custom PropertyDelegate for the mainWindow property.
class MainWindowPropertyDelegate<
  AppElement: ApplicationElementType, WinFinder: WindowFinder, WinDelegate: OSXDelegateType
  where WinFinder.UIElement == WinDelegate.UIElement
>: PropertyDelegate {
  typealias T = Window
  typealias UIElement = WinFinder.UIElement

  let readDelegate: WindowPropertyAdapter<AXPropertyDelegate<UIElement, AppElement>, WinFinder, WinDelegate>

  init(_ appElement: AppElement, windowFinder: WinFinder, windowDelegate: WinDelegate.Type, _ initPromise: Promise<[Attribute: Any]>) {
    readDelegate = WindowPropertyAdapter(AXPropertyDelegate(appElement, .MainWindow, initPromise), windowFinder: windowFinder, windowDelegate: windowDelegate)
  }

  func initialize() -> Promise<Window?> {
    return readDelegate.initialize()
  }

  func readValue() throws -> Window? {
    return try readDelegate.readValue()
  }

  func writeValue(newValue: Window) throws {
    // Extract the element from the window delegate.
    guard let winDelegate = newValue.delegate as? WinDelegate else {
      throw PropertyError.IllegalValue
    }
    // Check early to see if the element is still valid. If it becomes invalid after this check, the
    // same error will get thrown, it will just take longer.
    guard winDelegate.isValid else {
      throw PropertyError.IllegalValue
    }

    // Note: This is happening on a background thread, so only properties that don't change should be
    // accessed (the axElement).

    // To set the main window, we have to access the .Main attribute of the window element and set
    // it to true.
    let writeDelegate = AXPropertyDelegate<Bool, UIElement>(winDelegate.axElement, .Main, Promise([:]))
    try writeDelegate.writeValue(true)
  }
}

/// Converts a UIElement attribute into a readable Window property.
class WindowPropertyAdapter<
    Delegate: PropertyDelegate, WinFinder: WindowFinder, WinDelegate: OSXDelegateType
    where Delegate.T == WinFinder.UIElement, WinFinder.UIElement == WinDelegate.UIElement
>: PropertyDelegate {
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
      // This can happen if, for instance, the window was destroyed since the refresh was requested.
      log.debug("While updating property value, could not find window matching element: \(element)")
    }
    return window
  }

  func writeValue(newValue: Window) throws {
    // If we got here, a property is wrongly configured.
    fatalError("Writing directly to an \"object\" property is not supported by the AXUIElement API")
  }

  func initialize() -> Promise<Window?> {
    return delegate.initialize().then { maybeElement -> Window? in
      guard let element = maybeElement else {
        return nil
      }
      return self.findWindowByElement(element)
    }
  }

  private func findWindowByElement(element: Delegate.T) -> Window? {
    // Avoid using locks by forcing calls out to `windowFinder` to happen on the main thead.
    var window: Window? = nil
    if NSThread.currentThread().isMainThread {
      window = windowFinder?.findWindowByElement(element)
    } else {
      dispatch_sync(dispatch_get_main_queue()) {
        window = self.windowFinder?.findWindowByElement(element)
      }
    }
    return window
  }
}
