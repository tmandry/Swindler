import AXSwift

public var state: State = OSXState()

class OSXState: State {
  var applications: [Application] = []
  var observers: [Observer] = []
  var windows: [OSXWindow] = []

  // TODO: add testing
  // TODO: handle errors
  // TODO: fix strong ref cycle

  init() {
    // TODO: clean this up
    let app = Application.allForBundleID("com.apple.finder").first!
    print("app attrs: \(try! app.attributes())")
    let observer = app.createObserver() { (observer, element, notification) in
      if notification == .WindowCreated {
        let window = try! OSXWindow(state: self, axElement: element, observer: observer)
        self.windows.append(window)
        self.notify(.WindowCreated, event: WindowEvent(window: window, external: true))
      } else if let (index, target) = self.findWindowAndIndex(element) {
        if notification == .UIElementDestroyed {
          self.windows.removeAtIndex(index)
          self.notify(.WindowDestroyed, event: WindowEvent(window: target, external: true))
        }
        target.onEvent(observer, event: notification)
      } else {
        print("Event \(notification) on unknown element \(element)")
      }
    }!
    try! observer.addNotification(.WindowCreated,     forElement: app)
    try! observer.addNotification(.MainWindowChanged, forElement: app)
    observer.start()

    applications.append(app)
    observers.append(observer)
  }

  var visibleWindows: [Window] {
    get { return windows }
  }

  private func findWindowAndIndex(axElement: UIElement) -> (Int, OSXWindow)? {
    return self.windows.enumerate().filter({ $0.1.axElement == axElement }).first
  }

  private typealias EventHandler = (Event) -> ()
  private var eventHandlers: [Notification: [EventHandler]] = [:]
  private var windowPropertyHandlers: [WindowProperty: [EventHandler]] = [:]

  func onEvent<EventType: Event>(notification: Notification, handler: (EventType) -> ()) {
    // If we must do run-time type checking, do it during setup, not when an event fires.
    guard EventType.self == typeForNotification(notification) else {
      fatalError("Wrong event type \(EventType.self) used for \(notification) handler; " +
        "correct type is \(typeForNotification(notification))")
    }

    if eventHandlers[notification] == nil {
      eventHandlers[notification] = []
    }

    // Wrap in a casting closure to preserve type information.
    eventHandlers[notification]!.append({ handler($0 as! EventType) })
  }

  func onWindowPropertyChanged<EventType: GenericWindowPropertyEvent>(
      property: WindowProperty, handler: (EventType) -> ()) {
    guard EventType.PropertyType.self == typeForProperty(property) else {
      fatalError("Wrong event type \(EventType.self) used for \(property) change event handler; " +
        "correct type is Window\(property)ChangedEvent (WindowPropertyEvent<\(typeForProperty(property))>)")
    }

    if windowPropertyHandlers[property] == nil {
      windowPropertyHandlers[property] = []
    }

    // Wrap in a casting closure to preserve type information.
    windowPropertyHandlers[property]!.append({ handler($0 as! EventType) })
  }

  func notify<EventType: Event>(notification: Notification, event: EventType) {
    assert(EventType.self == typeForNotification(notification))

    if let handlers = eventHandlers[notification] {
      for handler in handlers {
        handler(event)
      }
    }
  }

  func notifyWindowPropertyChanged<EventType: GenericWindowPropertyEvent>(
      property: WindowProperty, event: EventType) {
    assert(EventType.PropertyType.self == typeForProperty(property))

    if let handlers = windowPropertyHandlers[property] {
      for handler in handlers {
        handler(event)
      }
    }
  }
}

class OSXWindow: Window {
  let state: OSXState
  let axElement: UIElement

  init(state: OSXState, axElement: UIElement, observer: Observer) throws {
    self.state = state
    self.axElement = axElement
    try loadAttributes()

    do {
      try observer.addNotification(.UIElementDestroyed, forElement: axElement)
      try observer.addNotification(.Moved, forElement: axElement)
      try observer.addNotification(.Resized, forElement: axElement)
    } catch let error {
      NSLog("Error: Could not watch [\(axElement)]: \(error)")
    }
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

  private func updateAttribute<T: Equatable>(prop: WindowProperty, _ axAttr: AXSwift.Attribute, inout _ store: T!) {
    do {
      let value: T = try axElement.attribute(axAttr)!
      updateAttributeWithValue(prop, &store, value)
    } catch {
      fatalError("unhandled error: \(error)")
    }
  }

  private func updateAttributeWithValue<T: Equatable>(prop: WindowProperty, inout _ store: T!, _ value: T) {
    if store != value {
      let oldVal = store
      store = value
      state.notifyWindowPropertyChanged(prop, event: WindowPropertyEvent<T>(window: self, external: true, oldVal: oldVal, newVal: store))
    }
  }

  private func setAttribute<T: Equatable>(prop: WindowProperty, _ axAttr: AXSwift.Attribute, inout _ store: T!, _ newVal: T) {
    // TODO: check value asynchronously(?), deal with failure modes (set fails, get fails)
    // TODO: purge all events for this attribute? otherwise a notification could come through with an old value.
    do {
      try axElement.setAttribute(axAttr, value: newVal)
      // Ask for the new value to find out what actually resulted
      let actual: T = try axElement.attribute(axAttr)!
      if store != actual {
        let oldVal = store
        store = actual
        state.notifyWindowPropertyChanged(prop, event: WindowPropertyEvent<T>(window: self, external: false, oldVal: oldVal, newVal: store))
      }
    } catch let error {
      fatalError("unhandled error: \(error)")
    }
  }

  func onEvent(observer: AXSwift.Observer, event: AXSwift.Notification) {
    print("\(axElement): \(event)")
    switch event {
    case .Moved:
      updateAttribute(.Pos, .Position, &pos_)
    case .Resized:
      updateAttribute(.Size, .Size, &size_)
    default:
      print("Unknown event on \(self): \(event)")
    }
  }

  private var pos_: CGPoint!
  var pos: CGPoint {
    get { return pos_ }
    set { setAttribute(.Pos, .Position, &pos_, newValue) }
  }

  private var size_: CGSize!
  var size: CGSize {
    get { return size_ }
    set { setAttribute(.Size, .Size, &size_, newValue) }
  }
}
