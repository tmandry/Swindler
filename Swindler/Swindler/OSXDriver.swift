import AXSwift
import PromiseKit

public var state = State(delegate: OSXStateDelegate<AXSwift.UIElement, AXSwift.Application, AXSwift.Observer>())

// MARK: - Injectable protocols

/// Protocol that wraps AXSwift.UIElement.
protocol UIElementType: Equatable {
  static var globalMessagingTimeout: Float { get }

  func pid() throws -> pid_t
  func attribute<T>(attribute: Attribute) throws -> T?
  func arrayAttribute<T>(attribute: Attribute) throws -> [T]?
  func setAttribute(attribute: Attribute, value: Any) throws
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any]

  var inspect: String { get }
}
extension AXSwift.UIElement: UIElementType { }

/// Protocol that wraps AXSwift.Observer.
protocol ObserverType {
  typealias UIElement: UIElementType

  init(processID: pid_t, callback: (observer: Self, element: UIElement, notification: AXSwift.Notification) -> ()) throws
  func addNotification(notification: AXSwift.Notification, forElement: UIElement) throws
  func processPendingNotifications()
}
extension AXSwift.Observer: ObserverType {
  typealias UIElement = AXSwift.UIElement

  func processPendingNotifications() {
    // Maybe we can configure a custom mode to only process AX notifications.
    // TODO: not sure this works (and does it go here?)
    var result: CFRunLoopRunResult!
    repeat {
      result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, true)
    } while result == CFRunLoopRunResult.HandledSource
  }
}

/// Protocol that wraps AXSwift.Application.
protocol ApplicationElementType: UIElementType {
  typealias UIElement: UIElementType

  static func all() -> [Self]

  // Until the Swift type system improves, I don't see a way around this.
  var toElement: UIElement { get }
}
extension AXSwift.Application: ApplicationElementType {
  typealias UIElement = AXSwift.UIElement
  var toElement: UIElement { return self }
}

// MARK: - Internal protocols

protocol EventNotifier: class {
  func notify<Event: EventType>(event: Event)
}

// MARK: - Errors

enum OSXDriverError: ErrorType {
  case MissingAttribute(attribute: AXSwift.Attribute, onElement: UIElementType)
  case UnknownWindow(element: UIElementType)
}

// MARK: - Implementation

class OSXStateDelegate<
    UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: StateDelegate, EventNotifier {
  typealias Window = OSXWindowDelegate<UIElement, ApplicationElement, Observer>
  typealias Application = OSXApplicationDelegate<UIElement, ApplicationElement, Observer>
  private typealias EventHandler = (EventType) -> ()

  private var applications: [Application] = []
  private var eventHandlers: [String: [EventHandler]] = [:]

  var runningApplications: [ApplicationDelegate] { return applications.map({ $0 as ApplicationDelegate }) }
  var visibleWindows: [WindowDelegate] { return applications.flatMap({ $0.visibleWindows }) }

  // TODO: fix strong ref cycle
  // TODO: retry instead of ignoring an app/window when timeouts are encountered during initialization?

  init() {
    print("Initializing Swindler")
    for appElement in ApplicationElement.all() {
      do {
        let application = try Application(appElement, notifier: self)
        applications.append(application)
      } catch {
        let runningApplication = try? NSRunningApplication(processIdentifier: appElement.pid())
        print("Could not watch application \(runningApplication): \(error)")
        assert(error is AXSwift.Error)
      }
    }
    print("Done initializing")
  }

  func on<Event: EventType>(handler: (Event) -> ()) {
    let notification = Event.typeName
    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information that gets erased in the dictionary.
    eventHandlers[notification]!.append({ handler($0 as! Event) })
  }

  func notify<Event: EventType>(event: Event) {
    if let handlers = eventHandlers[Event.typeName] {
      for handler in handlers {
        handler(event)
      }
    }
  }
}

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

// Making this private = Swift compiler segfault
protocol PropertyType {
  func refresh()
  var delegate: Any { get }
  var initialized: Promise<Void> { get }
}
extension Property: PropertyType {
  func refresh() {
    let _: Promise<Type> = self.refresh()
  }
}

class OSXWindowDelegate<
    UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
    where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: WindowDelegate, PropertyNotifier {
  typealias State = OSXStateDelegate<UIElement, ApplicationElement, Observer>
  typealias Object = Window
  let notifier: EventNotifier
  let axElement: UIElement

  private(set) var valid: Bool = true

  var pos: WriteableProperty<OfType<CGPoint>>!
  var size: WriteableProperty<OfType<CGSize>>!
  var title: Property<OfType<String>>!
  var minimized: WriteableProperty<OfType<Bool>>!
  var main: WriteableProperty<OfType<Bool>>!

  private var axProperties: [PropertyType]!
  private var watchedAxProperties: [AXSwift.Notification: PropertyType]!

  private init(notifier: EventNotifier, axElement: UIElement, observer: Observer) throws {
    // TODO: reject invalid roles (Chrome ghost windows)

    self.notifier = notifier
    self.axElement = axElement

    // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
    let (initPromise, fulfill, reject) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()

    // Initialize all properties.
    pos = WriteableProperty(AXPropertyDelegate(axElement, .Position, initPromise),
        withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: self)
    size = WriteableProperty(AXPropertyDelegate(axElement, .Size, initPromise),
        withEvent: WindowSizeChangedEvent.self, receivingObject: Window.self, notifier: self)
    title = Property(AXPropertyDelegate(axElement, .Title, initPromise),
        withEvent: WindowTitleChangedEvent.self, receivingObject: Window.self, notifier: self)
    minimized = WriteableProperty(AXPropertyDelegate(axElement, .Minimized, initPromise),
        withEvent: WindowMinimizedChangedEvent.self, receivingObject: Window.self, notifier: self)

    axProperties = [
      pos,
      size,
      title,
      minimized,
    ]

    // Map notifications on this element to the corresponding property.
    watchedAxProperties = [
      .Moved: pos,
      .Resized: size,
      .TitleChanged: title,
      .WindowMiniaturized: minimized,
      .WindowDeminiaturized: minimized
    ]

    // Start watching for notifications.
    for notification in watchedAxProperties.keys {
      try observer.addNotification(notification, forElement: axElement)
    }
    try observer.addNotification(.UIElementDestroyed, forElement: axElement)

    // Fetch attribute values.
    let attributes = axProperties.map({ ($0.delegate as! AXPropertyDelegateType).attribute })
    fetchAttributes(attributes, forElement: axElement, fulfill: fulfill, reject: reject)

    // Can't recover from an error during initialization.
    initPromise.error { error in
      self.notifyInvalid()
    }
  }

  // Initializes the window and returns it as a Promise once it's ready.
  static func initialize(notifier notifier: EventNotifier, axElement: UIElement, observer: Observer) -> Promise<OSXWindowDelegate> {
    return firstly {  // capture thrown errors in promise
      let window = try OSXWindowDelegate(notifier: notifier, axElement: axElement, observer: observer)

      let propertiesInitialized = Array(window.axProperties.map({ $0.initialized }))
      return when(propertiesInitialized).then { _ -> OSXWindowDelegate in
        return window
      }.recover { (error: ErrorType) -> OSXWindowDelegate in
        // Unwrap When errors
        switch error {
        case PromiseKit.Error.When(let index, let wrappedError):
          switch wrappedError {
          case PropertyError.MissingValue, PropertyError.InvalidObject(cause: PropertyError.MissingValue):
            // Add more information
            let propertyDelegate = window.axProperties[index].delegate as! AXPropertyDelegateType
            throw OSXDriverError.MissingAttribute(attribute: propertyDelegate.attribute, onElement: axElement)
          default:
            throw wrappedError
          }
        default:
          throw error
        }
      }
    }
  }

  func handleEvent(event: AXSwift.Notification, observer: Observer) {
    switch event {
    case .UIElementDestroyed:
      valid = false
    default:
      if let property = watchedAxProperties[event] {
        property.refresh()
      } else {
        print("Unknown event on \(self): \(event)")
      }
    }
  }

  func notify<Event: PropertyEventTypeInternal where Event.Object == Window>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notifier.notify(Event(external: external, object: Window(delegate: self), oldVal: oldValue, newVal: newValue))
  }

  func notifyInvalid() {
    valid = false
  }

  func equalTo(rhs: WindowDelegate) -> Bool {
    if let other = rhs as? OSXWindowDelegate {
      return self.axElement == other.axElement
    } else {
      return false
    }
  }
}

// Used by OSXWindowDelegate to pull out the AXSwift attributes.
protocol AXPropertyDelegateType {
  var attribute: AXSwift.Attribute { get }
}

class AXPropertyDelegate<T: Equatable, UIElement: UIElementType>: PropertyDelegate, AXPropertyDelegateType {
  typealias InitDict = [AXSwift.Attribute: Any]
  let axElement: UIElement
  let attribute: AXSwift.Attribute
  let initPromise: Promise<InitDict>

  init(_ axElement: UIElement, _ attribute: AXSwift.Attribute, _ initPromise: Promise<InitDict>) {
    self.axElement = axElement
    self.attribute = attribute
    self.initPromise = initPromise
  }

  func readValue() throws -> T? {
    do {
      return try axElement.attribute(attribute)
    } catch AXSwift.Error.CannotComplete {
      // If messaging timeout unspecified, we'll pass -1.
      let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
      throw PropertyError.Timeout(time: NSTimeInterval(time))
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement)
    } catch let error {
      unexpectedError(error)
      throw PropertyError.InvalidObject(cause: error)
    }
  }

  func writeValue(newValue: T) throws {
    do {
      try axElement.setAttribute(attribute, value: newValue)
    } catch AXSwift.Error.IllegalArgument {
      throw PropertyError.IllegalValue
    } catch AXSwift.Error.CannotComplete {
      // If messaging timeout unspecified, we'll pass -1.
      let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
      throw PropertyError.Timeout(time: NSTimeInterval(time))
    } catch AXSwift.Error.Failure {
      throw PropertyError.Failure(cause: AXSwift.Error.Failure)
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement)
    } catch let error {
      unexpectedError(error)
      throw PropertyError.InvalidObject(cause: error)
    }
  }

  func initialize() -> Promise<T?> {
    return initPromise.then { (dict: InitDict) throws -> T? in
      guard let value = dict[self.attribute] else {
        return nil
      }
      return (value as! T)
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
class WindowPropertyAdapter<Delegate: PropertyDelegate, WinFinder: WindowFinder, WinDelegate: HasElement where Delegate.T == WinFinder.UIElement, WinFinder.UIElement == WinDelegate.UIElement>: PropertyDelegate {
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

// Asynchronously fetches all the element attributes.
func fetchAttributes<UIElement: UIElementType>(attributeNames: [Attribute], forElement axElement: UIElement, fulfill: ([Attribute: Any]) -> (), reject: (ErrorType) -> ()) {
  Promise<Void>().thenInBackground { () -> () in
    // Issue a request in the background.
    let attributes = try axElement.getMultipleAttributes(attributeNames)
    fulfill(attributes)
  }.recover { error -> () in
    // Rewrite errors as PropertyErrors.
    do {
      throw error
    } catch AXSwift.Error.CannotComplete {
      // If messaging timeout unspecified, we'll pass -1.
      let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
      throw PropertyError.Timeout(time: NSTimeInterval(time))
    } catch AXSwift.Error.IllegalArgument {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.IllegalArgument)
    } catch AXSwift.Error.NotImplemented {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.NotImplemented)
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement)
    } catch {
      unexpectedError(error, onElement: axElement)
      throw PropertyError.InvalidObject(cause: error)
    }
  }.error { error in
    reject(error)
  }
}

// MARK: - Error handling

func unwrapWhenErrors<T>(error: ErrorType) throws -> Promise<T> {
  switch error {
  case PromiseKit.Error.When(_, let wrappedError):
    throw wrappedError
  default:
    throw error
  }
}

// Handle unexpected errors with detailed logging, and abort when in debug mode.
func unexpectedError(error: String, file: String = __FILE__, line: Int = __LINE__) {
  print("unexpected error: \(error) at \(file):\(line)")
  assertionFailure()
}
func unexpectedError<UIElement: UIElementType>(
    error: String, onElement element: UIElement, file: String = __FILE__, line: Int = __LINE__) {
  let application = try? NSRunningApplication(processIdentifier: element.pid())
  print("unexpected error: \(error) on element: \(element) of application: \(application) at \(file):\(line)")
  assertionFailure()
}
func unexpectedError(error: ErrorType, file: String = __FILE__, line: Int = __LINE__) {
  unexpectedError(String(error), file: file, line: line)
}
func unexpectedError<UIElement: UIElementType>(
  error: ErrorType, onElement element: UIElement, file: String = __FILE__, line: Int = __LINE__) {
    unexpectedError(String(error), onElement: element, file: file, line: line)
}
