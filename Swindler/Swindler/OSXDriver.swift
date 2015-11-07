import AXSwift

public var state: State = OSXState<UIElement, Application, Observer>()

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
>: State {
  typealias WindowT = OSXWindow<UIElement, Application, Observer>
  var applications: [Application] = []
  var observers: [Observer] = []
  var windows: [WindowT] = []

  // TODO: add testing
  // TODO: handle errors
  // TODO: fix strong ref cycle

  init() {
    let app = Application.all().first!
    let observer = try! Observer(processID: try! app.pid(), callback: handleEvent)
    try! observer.addNotification(.WindowCreated,     forElement: app.toElement)
    try! observer.addNotification(.MainWindowChanged, forElement: app.toElement)

    applications.append(app)
    observers.append(observer)
  }

  private func handleEvent(observer observer: Observer, element: UIElement, notification: AXSwift.Notification) {
    if .WindowCreated == notification {
      do {
        let window = try WindowT(state: self, axElement: element, observer: observer)
        windows.append(window)
        notify(WindowCreatedEvent(external: true, window: window))
      } catch let error {
        NSLog("Error: Could not watch [\(element)]: \(error)")
      }
    } else if let (index, target) = findWindowAndIndex(element) {
      if .UIElementDestroyed == notification {
        windows.removeAtIndex(index)
        notify(WindowDestroyedEvent(external: true, window: target))
      }
      target.handleEvent(observer, event: notification)
    } else {
      print("Event \(notification) on unknown element \(element)")
    }
  }

  private func findWindowAndIndex(axElement: UIElement) -> (Int, WindowT)? {
    return self.windows.enumerate().filter({ $0.1.axElement == axElement }).first
  }

  var visibleWindows: [Window] {
    get { return windows }
  }

  private typealias EventHandler = (Event) -> ()
  private var eventHandlers: [String: [EventHandler]] = [:]

  func on<EventType: Event>(handler: (EventType) -> ()) {
    let notification = EventType.typeName
    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information that gets erased in the dictionary.
    eventHandlers[notification]!.append({ handler($0 as! EventType) })
  }

  func notify<EventType: Event>(event: EventType) {
    if let handlers = eventHandlers[EventType.typeName] {
      for handler in handlers {
        handler(event)
      }
    }
  }
}

class OSXWindow<
    UIElement: UIElementType, Application: ApplicationType, Observer: ObserverType
    where Observer.UIElement == UIElement, Application.UIElement == UIElement
>: Window {
  typealias StateT = OSXState<UIElement, Application, Observer>
  let state: StateT
  let axElement: UIElement

  init(state: StateT, axElement: UIElement, observer: Observer) throws {
    self.state = state
    self.axElement = axElement
    try loadAttributes()

    try observer.addNotification(.UIElementDestroyed, forElement: axElement)
    try observer.addNotification(.Moved, forElement: axElement)
    try observer.addNotification(.Resized, forElement: axElement)
  }

  func handleEvent(observer: Observer, event: AXSwift.Notification) {
    switch event {
    case .Moved:
      updateProperty(.Position, &pos_, WindowPosChangedEvent.self)
    case .Resized:
      updateProperty(.Size, &size_, WindowSizeChangedEvent.self)
    case .UIElementDestroyed:
      break
    default:
      print("Unknown event on \(self): \(event)")
    }
  }

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

  private func loadAttributes() throws {
    let attrNames: [AXSwift.Attribute] = [.Position, .Size]
    let attributes = try axElement.getMultipleAttributes(attrNames)

    guard attributes.count == attrNames.count else {
      NSLog("Could not get required attributes for window. Wanted: \(attrNames). Got: \(attributes.keys)")
      throw AXSwift.Error.InvalidUIElement  // TODO: make our own
    }

    pos_ = attributes[.Position]! as! CGPoint
    size_ = attributes[.Size]! as! CGSize
  }

  // Updates the given property from the axElement (events marked as external).
  private func updateProperty<EventType: WindowPropertyEventInternal>(
      axAttr: AXSwift.Attribute, inout _ store: EventType.PropertyType!, _ eventType: EventType.Type) {
    do {
      let value: EventType.PropertyType = try axElement.attribute(axAttr)!
      updatePropertyWithValue(&store, value, eventType)
    } catch {
      fatalError("unhandled error: \(error)")
    }
  }

  // Updates the given property to the given value (events marked as external).
  private func updatePropertyWithValue<EventType: WindowPropertyEventInternal>(
      inout store: EventType.PropertyType!, _ value: EventType.PropertyType, _ eventType: EventType.Type) {
    if store != value {
      let oldVal = store
      store = value
      state.notify(EventType(external: true, window: self, oldVal: oldVal, newVal: store))
    }
  }

  // Sets the given property and axElement attribute to the given value (events marked as internal).
  private func setProperty<EventType: WindowPropertyEventInternal>(
      axAttr: AXSwift.Attribute, inout _ store: EventType.PropertyType!, _ newVal: EventType.PropertyType,
      _ eventType: EventType.Type) {
    // TODO: check value asynchronously(?), deal with failure modes (set fails, get fails)
    // TODO: purge all events for this attribute? otherwise a notification could come through with an old value.
    do {
      try axElement.setAttribute(axAttr, value: newVal)
      // Ask for the new value to find out what actually resulted
      let actual: EventType.PropertyType = try axElement.attribute(axAttr)!
      if store != actual {
        let oldVal = store
        store = actual
        state.notify(EventType(external: false, window: self, oldVal: oldVal, newVal: store))
      }
    } catch let error {
      fatalError("unhandled error: \(error)")
    }
  }
}
