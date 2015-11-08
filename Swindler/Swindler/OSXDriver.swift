import AXSwift

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

// MARK: - Implementation

class OSXState<
    UIElement: UIElementType, Application: ApplicationType, Observer: ObserverType
    where Observer.UIElement == UIElement, Application.UIElement == UIElement
>: StateType {
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
    do {
      let window = try Window(state: self, axElement: windowElement, observer: observer)
      windows.append(window)
      notify(WindowCreatedEvent(external: true, window: window))
    } catch {
      // TODO: handle timeouts
      print("Error: Could not watch [\(windowElement)]: \(error)")
      assert(error is AXSwift.Error)
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

enum OSXDriverError: ErrorType {
  case MissingAttributes
}

class OSXWindow<
    UIElement: UIElementType, Application: ApplicationType, Observer: ObserverType
    where Observer.UIElement == UIElement, Application.UIElement == UIElement
>: WindowType {
  typealias State = OSXState<UIElement, Application, Observer>
  let state: State
  let axElement: UIElement

  init(state: State, axElement: UIElement, observer: Observer) throws {
    self.state = state
    self.axElement = axElement
    try loadAttributes()

    try observer.addNotification(.UIElementDestroyed, forElement: axElement)
    try observer.addNotification(.Moved, forElement: axElement)
    try observer.addNotification(.Resized, forElement: axElement)
    try observer.addNotification(.TitleChanged, forElement: axElement)
  }

  func handleEvent(event: AXSwift.Notification, observer: Observer) {
    switch event {
    case .UIElementDestroyed:
      valid = false
    case .Moved:
      updateProperty(.Position, &pos_, WindowPosChangedEvent.self)
    case .Resized:
      updateProperty(.Size, &size_, WindowSizeChangedEvent.self)
    case .TitleChanged:
      updateProperty(.Title, &title_, WindowTitleChangedEvent.self)
    default:
      print("Unknown event on \(self): \(event)")
    }
  }

  private(set) var valid: Bool = true

  private var pos_: CGPoint!
  var pos: CGPoint {
    get { return pos_ }
    set { setProperty(.Position, &pos_, newValue, WindowPosChangedEvent.self) }
  }

  private var size_: CGSize!
  var size: CGSize {
    get { return size_ }
    set { setProperty(.Size, &size_, newValue, WindowSizeChangedEvent.self) }
  }

  private var title_: String!
  var title: String {
    get { return title_ }
  }

  private func loadAttributes() throws {
    let attrNames: [AXSwift.Attribute] = [.Position, .Size, .Title]
    let attributes = try axElement.getMultipleAttributes(attrNames)

    guard attributes.count == attrNames.count else {
      print("Could not get required attributes for window. Wanted: \(attrNames). Got: \(attributes.keys)")
      throw OSXDriverError.MissingAttributes
    }

    pos_   = attributes[.Position]! as! CGPoint
    size_  = attributes[.Size]! as! CGSize
    title_ = attributes[.Title]! as! String
  }

  // Updates the given property from the axElement (events marked as external).
  private func updateProperty<Event: WindowPropertyEventInternalType>(
              axAttr:    AXSwift.Attribute,
      inout _ store:     Event.PropertyType!,
      _       eventType: Event.Type) {
    do {
      let value: Event.PropertyType = try axElement.attribute(axAttr)!
      updatePropertyWithValue(&store, value, eventType)
    } catch AXSwift.Error.InvalidUIElement {
      valid = false
    } catch {
      // TODO: deal with timeouts
      unexpectedError(error, onElement: axElement)
      valid = false
    }
  }

  // Updates the given property to the given value (events marked as external).
  private func updatePropertyWithValue<Event: WindowPropertyEventInternalType>(
      inout store:     Event.PropertyType!,
      _     value:     Event.PropertyType,
      _     eventType: Event.Type) {
    if store != value {
      let oldVal = store
      store = value
      state.notify(Event(external: true, window: self, oldVal: oldVal, newVal: store))
    }
  }

  // Sets the given property and axElement attribute to the given value (events marked as internal).
  private func setProperty<Event: WindowPropertyEventInternalType>(
              axAttr:    AXSwift.Attribute,
      inout _ store:     Event.PropertyType!,
      _       newVal:    Event.PropertyType,
      _       eventType: Event.Type) {
    // TODO: check value asynchronously(?)
    // TODO: purge all events for this attribute? otherwise a notification could come through with an old value.
    do {
      try axElement.setAttribute(axAttr, value: newVal)
      // Ask for the new value to find out what actually resulted
      let actual: Event.PropertyType = try axElement.attribute(axAttr)!
      if store != actual {
        let oldVal = store
        store = actual
        state.notify(Event(external: false, window: self, oldVal: oldVal, newVal: store))
      }
    } catch AXSwift.Error.InvalidUIElement {
      valid = false
    } catch {
      // TODO: deal with timeouts
      unexpectedError(error, onElement: axElement)
      valid = false
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
