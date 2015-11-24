import AXSwift
import PromiseKit

public var state = State(delegate: OSXStateDelegate<AXSwift.UIElement, AXSwift.Application, AXSwift.Observer>())

// MARK: - Injectable protocols

/// Protocol that wraps AXSwift.UIElement.
protocol UIElementType: Equatable {
  static var globalMessagingTimeout: Float { get }

  func pid() throws -> pid_t
  func attribute<T>(attribute: Attribute) throws -> T?
  func setAttribute(attribute: Attribute, value: Any) throws
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any]
}
extension AXSwift.UIElement: UIElementType { }

/// Protocol that wraps AXSwift.Observer.
protocol ObserverType {
  typealias UIElement: UIElementType

  init(processID: pid_t, callback: (observer: Self, element: UIElement, notification: AXSwift.Notification) -> ()) throws
  func addNotification(notification: AXSwift.Notification, forElement: UIElement) throws
}
extension AXSwift.Observer: ObserverType {
  typealias UIElement = AXSwift.UIElement
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

  private var axProperties: [PropertyType]!

  var mainWindow: Property<Window>!
  var frontmost: WriteableProperty<Bool>!

  var visibleWindows: [WindowDelegate] {
    return windows.map({ $0 as WindowDelegate })
  }

  init(_ appElement: ApplicationElement, notifier: EventNotifier) throws {
    self.axElement = appElement.toElement
    self.notifier = notifier

    // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
    let (initPromise, fulfill, reject) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()

    // TODO: support applications without main windows
//    mainWindow = Property<Window>(AXPropertyDelegate(axElement, .MainWindow, initPromise),
//        withEvent: ApplicationMainWindowChangedEvent.self, receivingObject: Application.self, notifier: self)
    frontmost = WriteableProperty<Bool>(AXPropertyDelegate(axElement, .Frontmost, initPromise),
        withEvent: ApplicationFrontmostChangedEvent.self, receivingObject: Application.self, notifier: self)

    axProperties = [
//      mainWindow,
      frontmost
    ]

    // Set up notifications.
    observer = try Observer(processID: appElement.pid(), callback: handleEvent)
    try observer.addNotification(.WindowCreated,          forElement: appElement.toElement)
    try observer.addNotification(.MainWindowChanged,      forElement: appElement.toElement)
    try observer.addNotification(.ApplicationActivated,   forElement: appElement.toElement)
    try observer.addNotification(.ApplicationDeactivated, forElement: appElement.toElement)

    // Fetch attribute values.
    fetchAttributes(axProperties, forElement: axElement, fulfill: fulfill, reject: reject)

    // Can't recover from an error during initialization.
    initPromise.error { error in
      self.notifyInvalid()
    }
  }

  private func handleEvent(observer observer: Observer, element: UIElement, notification: AXSwift.Notification) {
    switch notification {
    case .WindowCreated:
      onWindowCreated(element)
    case .MainWindowChanged:
      onMainWindowChanged(element)
    case .ApplicationActivated:
      onActivationChanged()
    case .ApplicationDeactivated:
      onActivationChanged()
    default:
      onWindowEvent(notification, windowElement: element)
    }
  }

  private func onWindowCreated(windowElement: UIElement) {
    OSXWindow.initialize(notifier: notifier, axElement: windowElement, observer: observer).then { window -> () in
      self.windows.append(window)
      self.notifier.notify(WindowCreatedEvent(external: true, window: Window(delegate: window)))
    }.error { error in
      print("Error: Could not watch [\(windowElement)]: \(error)")
    }
  }

  private func onMainWindowChanged(windowElement: UIElement) {
    // update .main properties of windows here
    // do we need to do this with dispatch_async?
//    guard let (_, _) = findWindowAndIndex(windowElement) else {
//      print("Main window for application changed to unknown element \(windowElement)")
//      return
//    }

//    mainWindow.refresh() as ()
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
    // TODO
  }

  private func findWindowAndIndex(axElement: UIElement) -> (Int, OSXWindow)? {
    return windows.enumerate().filter({ $0.1.axElement == axElement }).first
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

  var pos: WriteableProperty<CGPoint>!
  var size: WriteableProperty<CGSize>!
  var title: Property<String>!
  var minimized: WriteableProperty<Bool>!
  var main: WriteableProperty<Bool>!

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
    fetchAttributes(axProperties, forElement: axElement, fulfill: fulfill, reject: reject)

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
        case PromiseKit.Error.When(_, let wrappedError):
          throw wrappedError
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

  func readValue() throws -> T {
    do {
      guard let value: T = try axElement.attribute(attribute) else {
        // This will be caught as an unexpected error.
        throw OSXDriverError.MissingAttribute(attribute: attribute, onElement: axElement)
      }
      return value
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

  func initialize() -> Promise<T> {
    return initPromise.then { (dict: InitDict) throws -> T in
      guard let value = dict[self.attribute] else {
        throw PropertyError.InvalidObject(
          cause: OSXDriverError.MissingAttribute(attribute: self.attribute, onElement: self.axElement))
      }
      return value as! T
    }
  }
}

// Asynchronously fetches all the window attributes.
func fetchAttributes<UIElement: UIElementType>(axProperties: [PropertyType], forElement axElement: UIElement, fulfill: ([Attribute: Any]) -> (), reject: (ErrorType) -> ()) {
  let attributes = axProperties.map({ ($0.delegate as! AXPropertyDelegateType).attribute })
  Promise<Void>().thenInBackground {
    // Issue a request in the background.
    return try axElement.getMultipleAttributes(attributes)
  }.then { attributes -> () in
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
