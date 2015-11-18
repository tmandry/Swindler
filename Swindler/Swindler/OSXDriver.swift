import AXSwift
import PromiseKit

public var state: StateType = OSXState<UIElement, Application, Observer>()

// MARK: - Injectable protocols

protocol UIElementType: Equatable {
  func pid() throws -> pid_t
  func attribute<T>(attribute: Attribute) throws -> T?
  func setAttribute(attribute: Attribute, value: Any) throws
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any]
}
extension AXSwift.UIElement: UIElementType { }

protocol ObserverType {
  typealias UIElement: UIElementType

  init(processID: pid_t, callback: (observer: Self, element: UIElement, notification: AXSwift.Notification) -> ()) throws
  func addNotification(notification: AXSwift.Notification, forElement: UIElement) throws
}
extension AXSwift.Observer: ObserverType {
  typealias UIElement = AXSwift.UIElement
}

protocol ApplicationType: UIElementType {
  typealias UIElement: UIElementType

  static func all() -> [Self]

  // Until the Swift type system improves, I don't see a way around this.
  var toElement: UIElement { get }
}
extension AXSwift.Application: ApplicationType {
  typealias UIElement = AXSwift.UIElement
  var toElement: UIElement { return self }
}

// MARK: - Internal protocols

protocol EventNotifier: class {
  func notify<Event: EventType>(event: Event)
}

// MARK: - Errors

enum OSXDriverError: ErrorType {
  case MissingAttribute
}

// MARK: - Implementation

class OSXState<
    UIElement: UIElementType, Application: ApplicationType, Observer: ObserverType
    where Observer.UIElement == UIElement, Application.UIElement == UIElement
>: StateType, EventNotifier {
  typealias Window = OSXWindow<UIElement, Application, Observer>
  var applications: [Application] = []
  var observers: [Observer] = []
  var windows: [Window] = []

  // TODO: handle errors
  // TODO: fix strong ref cycle

  init() {
    print("Initializing Swindler")
    for app in Application.all() {
      do {
        let observer = try Observer(processID: app.pid(), callback: handleEvent)
        try observer.addNotification(.WindowCreated,     forElement: app.toElement)
        try observer.addNotification(.MainWindowChanged, forElement: app.toElement)

        applications.append(app)
        observers.append(observer)
      } catch {
        // TODO: handle timeouts
        let application = try? NSRunningApplication(processIdentifier: app.pid())
        print("Could not watch application \(application): \(error)")
        assert(error is AXSwift.Error)
      }
    }
    print("Done initializing")
  }

  private func handleEvent(observer observer: Observer, element: UIElement, notification: AXSwift.Notification) {
    if .WindowCreated == notification {
      onWindowCreated(element, observer: observer)
      return
    }

    let handled = onWindowEvent(notification, windowElement: element, observer: observer)
    if !handled {
      print("Event \(notification) on unknown element \(element)")
    }
  }

  private func onWindowCreated(windowElement: UIElement, observer: Observer) {
    Window.initialize(notifier: self, axElement: windowElement, observer: observer).then { (window: Window) -> () in
      self.windows.append(window)
      self.notify(WindowCreatedEvent(external: true, window: window))
    }.error { error in
      // TODO: handle timeouts
      print("Error: Could not watch [\(windowElement)]: \(error)")
      assert(error is AXSwift.Error || error is OSXDriverError)
    }
  }

  private func onWindowEvent(notification: AXSwift.Notification, windowElement: UIElement, observer: Observer) -> Bool {
    guard let (index, window) = findWindowAndIndex(windowElement) else {
      return false
    }

    window.handleEvent(notification, observer: observer)

    if .UIElementDestroyed == notification {
      windows.removeAtIndex(index)
      notify(WindowDestroyedEvent(external: true, window: window))
    }

    return true
  }

  private func findWindowAndIndex(axElement: UIElement) -> (Int, Window)? {
    return windows.enumerate().filter({ $0.1.axElement == axElement }).first
  }

  var visibleWindows: [WindowType] {
    return windows.map({ $0 as WindowType })
  }

  private typealias EventHandler = (EventType) -> ()
  private var eventHandlers: [String: [EventHandler]] = [:]

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

// Making this private = compiler segfault
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

class OSXWindow<
    UIElement: UIElementType, Application: ApplicationType, Observer: ObserverType
    where Observer.UIElement == UIElement, Application.UIElement == UIElement
>: WindowType, WindowPropertyNotifier {
  typealias State = OSXState<UIElement, Application, Observer>
  let notifier: EventNotifier
  let axElement: UIElement

  private(set) var valid: Bool = true

  var pos: WriteableProperty<CGPoint>!
  var size: WriteableProperty<CGSize>!
  var title: Property<String>!
  var minimized: WriteableProperty<Bool>!
  var main: WriteableProperty<Bool>!

  private var watchedAxProperties: [AXSwift.Notification: PropertyType]!

  private init(notifier: EventNotifier, axElement: UIElement, observer: Observer) throws {
    // TODO: reject invalid roles (Chrome ghost windows)

    self.notifier = notifier
    self.axElement = axElement

    // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
    let (initPromise, fulfill, _) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()

    // Initialize all properties.
    pos = WriteableProperty(WindowPosChangedEvent.self, self, AXPropertyDelegate(axElement, .Position, initPromise))
    size = WriteableProperty(WindowSizeChangedEvent.self, self, AXPropertyDelegate(axElement, .Size, initPromise))
    title = Property(WindowTitleChangedEvent.self, self, AXPropertyDelegate(axElement, .Title, initPromise))
    minimized = WriteableProperty(WindowMinimizedChangedEvent.self, self, AXPropertyDelegate(axElement, .Minimized, initPromise))
    main = WriteableProperty(WindowMainChangedEvent.self, self, AXPropertyDelegate(axElement, .Main, initPromise))

    // Map notifications to the corresponding property.
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

    // Asynchronously fetch the attribute values.
    let axProperties = watchedAxProperties.values  // might contain duplicates
    let attrNames: [Attribute] = axProperties.map({ ($0.delegate as! AXPropertyDelegateType).attribute })
    let uniqueAttrNames = Array(Set(attrNames))
    Promise<Void>().thenInBackground {
      return try axElement.getMultipleAttributes(uniqueAttrNames)
    }.then { attributes in
      fulfill(attributes)
    }.error { error in
      // TODO: handle timeouts
      unexpectedError(error, onElement: axElement)
      self.notifyInvalid()
    }
  }

  static func initialize(notifier notifier: EventNotifier, axElement: UIElement, observer: Observer) -> Promise<OSXWindow> {
    return firstly {
      let window = try OSXWindow(notifier: notifier, axElement: axElement, observer: observer)
      let axProperties = window.watchedAxProperties.values
      let attrPromises = axProperties.map({ $0.initialized })
      return when(Array(attrPromises)).then { _ -> OSXWindow in
        return window
      }
    }.recover { (error: ErrorType) -> OSXWindow in
      // Pass through errors wrapped by when
      switch error {
      case PromiseKit.Error.When(_, let wrappedError):
        throw wrappedError
      default:
        throw error
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

  func notify<Event: WindowPropertyEventTypeInternal>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notifier.notify(Event(external: external, window: self, oldVal: oldValue, newVal: newValue))
  }

  func notifyInvalid() {
    valid = false
  }
}

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
      // TODO: handle missing values
      return try axElement.attribute(attribute)!
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.Invalid(error: AXSwift.Error.InvalidUIElement)
    } catch let error {
      // TODO: handle kAXErrorAttributeUnsupported, kAXErrorCannotComplete, kAXErrorNotImplemented
      unexpectedError(error)
      throw PropertyError.Invalid(error: error)
    }
  }

  func writeValue(newValue: T) throws {
    do {
      try axElement.setAttribute(attribute, value: newValue)
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.Invalid(error: AXSwift.Error.InvalidUIElement)
    } catch AXSwift.Error.Failure {
      throw AXSwift.Error.Failure
    } catch let error {
      // TODO: handle kAXErrorIllegalArgument, kAXErrorAttributeUnsupported, kAXErrorCannotComplete, kAXErrorNotImplemented
      unexpectedError(error)
      throw PropertyError.Invalid(error: error)
    }
  }

  func initialize() -> Promise<T> {
    return initPromise.thenInBackground { (dict: InitDict) throws -> T in
      guard let value = dict[self.attribute] else {
        print("Missing attribute \(self.attribute) on window element \(self.axElement)")
        throw PropertyError.Invalid(error: OSXDriverError.MissingAttribute)
      }
      return value as! T
    }
  }
}

// MARK: - Error handling

// Handle unexpected errors with detailed logging, and abort when in debug mode.
func unexpectedError(error: ErrorType, file: String = __FILE__, line: Int = __LINE__) {
  print("unexpected error: \(error) at \(file):\(line)")
  assertionFailure()
}
func unexpectedError<UIElement: UIElementType>(
    error: ErrorType, onElement element: UIElement, file: String = __FILE__, line: Int = __LINE__) {
  let application = try? NSRunningApplication(processIdentifier: element.pid())
  print("unexpected error: \(error) on element: \(element) of application: \(application) at \(file):\(line)")
  assertionFailure()
}
