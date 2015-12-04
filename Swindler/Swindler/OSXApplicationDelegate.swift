import AXSwift
import PromiseKit

/// Implements ApplicationDelegate using the AXUIElement API.
class OSXApplicationDelegate<
  UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
  where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: ApplicationDelegate, PropertyNotifier {
  typealias Object = Application
  typealias OSXWindow = OSXWindowDelegate<UIElement, ApplicationElement, Observer>

  private let notifier: EventNotifier
  private let axElement: UIElement
  private var observer: Observer!
  private var windows: [OSXWindow] = []
  private var newWindowPromises: [(UIElement, Promise<Void>)] = []

  private var properties: [PropertyType]!

  var mainWindow: Property<OfOptionalType<Window>>!
  var frontmost: WriteableProperty<OfType<Bool>>!

  var visibleWindows: [WindowDelegate] {
    return windows.map({ $0 as WindowDelegate })
  }

  init(_ appElement: ApplicationElement, notifier: EventNotifier) throws {
    // TODO: initialize function like OSXWindowDelegate
    // TODO: filter out applications by activation policy
    self.axElement = appElement.toElement
    self.notifier = notifier

    // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
    let (fetchAttrs, fulfill, reject) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()
    let initPromise = when(fetchAttrs, fetchWindows()).then({ $0.0 }).recover(unwrapWhenErrors)

    mainWindow = Property<OfOptionalType<Window>>(
      WindowPropertyAdapter(AXPropertyDelegate(axElement, .MainWindow, initPromise),
        windowFinder: self, windowDelegate: OSXWindow.self),
      withEvent: ApplicationMainWindowChangedEvent.self, receivingObject: Application.self, notifier: self)
    frontmost = WriteableProperty<OfType<Bool>>(AXPropertyDelegate(axElement, .Frontmost, initPromise),
      withEvent: ApplicationFrontmostChangedEvent.self, receivingObject: Application.self, notifier: self)

    properties = [
      mainWindow,
      frontmost
    ]
    let attributes: [Attribute] = [
      .MainWindow,
      .Frontmost
    ]

    // Set up notifications.
    // TODO: Before fetchWindows()
    // TODO: these can hang, put them on background thread
    observer = try Observer(processID: appElement.pid(), callback: handleEvent)
    try observer.addNotification(.WindowCreated,          forElement: appElement.toElement)
    try observer.addNotification(.MainWindowChanged,      forElement: appElement.toElement)
    try observer.addNotification(.ApplicationActivated,   forElement: appElement.toElement)
    try observer.addNotification(.ApplicationDeactivated, forElement: appElement.toElement)

    // Fetch attribute values.
    fetchAttributes(attributes, forElement: axElement, fulfill: fulfill, reject: reject)

    // Can't recover from an error during initialization.
    initPromise.error { error in
      self.notifyInvalid()
    }
  }

  private func fetchWindows() -> Promise<Void> {
    // TODO: add tests
    var elements: [UIElement]!
    return Promise<Void>().thenInBackground { () -> [UIElement]? in
      return try self.axElement.arrayAttribute(.Windows)
    }.then { maybeWindowElements -> Promise<[OSXWindow]> in
      guard let windowElements = maybeWindowElements else {
        throw OSXDriverError.MissingAttribute(attribute: .Windows, onElement: self.axElement)
      }
      elements = windowElements
      let windowPromises = windowElements.map({
        OSXWindow.initialize(notifier: self.notifier, axElement: $0, observer: self.observer)
      })
      return any(windowPromises, onError: { index, error in
        let windowElement = elements[index]
        let description: String = (try? windowElement.attribute(.Description) ?? "") ?? ""
        print("Couldn't initialize window for element \(windowElement) (\(description)): \(error)")
      })
    }.then { windowDelegates -> () in
      self.windows = windowDelegates
    }.recover { error -> () in
      // No valid windows, but no big deal
    }
  }

  private func handleEvent(observer observer: Observer, element: UIElement, notification: AXSwift.Notification) {
    switch notification {
    case .WindowCreated:
      onWindowCreated(element)
    case .MainWindowChanged:
      onMainWindowChanged()
    case .ApplicationActivated:
      onActivationChanged()
    case .ApplicationDeactivated:
      onActivationChanged()
    default:
      onWindowEvent(notification, windowElement: element)
    }
  }

  private func onWindowCreated(windowElement: UIElement) {
    let promise = OSXWindow.initialize(notifier: notifier, axElement: windowElement, observer: observer).then { window -> () in
      self.windows.append(window)
      self.notifier.notify(WindowCreatedEvent(external: true, window: Window(delegate: window)))
    }

    // Maintain a list of all pending new window promises.
    // TODO: Test usages
    newWindowPromises.append((windowElement, promise))
    promise.always {
      let result = self.newWindowPromises.enumerate().filter({ arg -> Bool in
        let axElement = arg.element.0
        return axElement == windowElement
      })
      self.newWindowPromises.removeAtIndex(result.first!.index)
    }

    promise.error { error in
      print("Error: Could not watch [\(windowElement)]: \(error)")
    }
  }

  private func onMainWindowChanged() {
    // Run through all other notifications to look for any new windows.
    // TODO: Test different situations and orders of events
    observer.processPendingNotifications()
    // The main window could be changed to a Window that is pending initialization, so delay refresh
    // until that is done.
    when(newWindowPromises.map({ $0.1 })).then { _ in
      self.mainWindow.refresh() as ()
    }
  }

  private func onActivationChanged() {
    frontmost.refresh() as ()
  }

  private func onWindowEvent(notification: AXSwift.Notification, windowElement: UIElement) {
    guard let (index, window) = findWindowAndIndex(windowElement) else {
      print("Event \(notification) on unknown element \(windowElement)")
      return
    }

    window.handleEvent(notification, observer: observer)

    if .UIElementDestroyed == notification {
      windows.removeAtIndex(index)
      notifier.notify(WindowDestroyedEvent(external: true, window: Window(delegate: window)))
    }
  }

  func notify<Event: PropertyEventTypeInternal where Event.Object == Application>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notifier.notify(Event(external: external, object: Application(delegate: self), oldVal: oldValue, newVal: newValue))
  }

  func notifyInvalid() {
    print("Application invalidated: \(self)")
    // TODO
  }

  private func findWindowAndIndex(axElement: UIElement) -> (Int, OSXWindow)? {
    return windows.enumerate().filter({ $0.1.axElement == axElement }).first
  }

  func findWindowByElement(element: UIElement) -> Window? {
    if let windowDelegate = windows.filter({ $0.axElement == element }).first {
      return Window(delegate: windowDelegate)
    } else {
      return nil
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

protocol WindowFinder: class {
  typealias UIElement: UIElementType
  func findWindowByElement(element: UIElement) -> Window?
}
extension OSXApplicationDelegate: WindowFinder {}
protocol HasElement {
  typealias UIElement: UIElementType
  var axElement: UIElement { get }
  var valid: Bool { get }
}
extension OSXWindowDelegate: HasElement {}

/// Converts a UIElement attribute into a Window property.
class WindowPropertyAdapter<
    Delegate: PropertyDelegate, WinFinder: WindowFinder, WinDelegate: HasElement
    where Delegate.T == WinFinder.UIElement, WinFinder.UIElement == WinDelegate.UIElement
>: PropertyDelegate {
  typealias T = Window

  let delegate: Delegate
  let windowFinder: WinFinder
  init(_ delegate: Delegate, windowFinder: WinFinder, windowDelegate: WinDelegate.Type) {
    self.delegate = delegate
    self.windowFinder = windowFinder
  }

  func readValue() throws -> Window? {
    guard let element = try delegate.readValue() else {
      return nil
    }
    return findWindowByElement(element)
  }

  func writeValue(newValue: Window) throws {
    // Extract the element from the window delegate.
    guard let winDelegate = newValue.delegate as? WinDelegate else {
      throw PropertyError.IllegalValue
    }
    guard winDelegate.valid else {
      throw PropertyError.IllegalValue
    }
    try delegate.writeValue(winDelegate.axElement)
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
      window = windowFinder.findWindowByElement(element)
    } else {
      dispatch_sync(dispatch_get_main_queue()) {
        window = self.windowFinder.findWindowByElement(element)
      }
    }
    return window
  }
}
