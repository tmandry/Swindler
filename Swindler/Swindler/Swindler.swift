public protocol StateType {
  var visibleWindows: [WindowType] { get }
  func on<Event: EventType>(handler: (Event) -> ())
}

public protocol WindowType {
  var valid: Bool { get }

  var pos: WriteableProperty<CGPoint>! { get }
  var size: WriteableProperty<CGSize>! { get }
//  var rect: CGRect { get set }

  var title: Property<String>! { get }
}

extension WindowType {
  // Convenience parameter
  var rect: CGRect {
    get { return CGRect(origin: pos.value, size: size.value) }
    set {
      pos.value = newValue.origin
      size.value = newValue.size
    }
  }
}

// (oldSpace, newSpace, windowsArrived, windowsDeparted)
// case SpaceChanged
// (oldLayout?, newLayout)
// case ScreenLayoutChanged

public protocol EventType {
  var external: Bool { get }
}

extension EventType {
  // In a later version of Swift, this can be stored (lazily).. store as hashValue for more speed.
  // Instead of using this, we _could_ use an enum of all notifications and require each event to
  // declare a static var of its notification. That's error prone, though, and this is fast enough.
  static var typeName: String {
    return Mirror(reflecting: Self.self).description
  }
}

public protocol WindowEventType: EventType {
  var window: WindowType { get }
  var external: Bool { get }
}

public struct WindowCreatedEvent: WindowEventType {
  public var external: Bool
  public var window: WindowType
}

public struct WindowDestroyedEvent: WindowEventType {
  public var external: Bool
  public var window: WindowType
}

public protocol WindowPropertyEventType: WindowEventType {
  typealias PropertyType: Equatable

  var oldVal: PropertyType { get }
  var newVal: PropertyType { get }
  // TODO: requestedVal?
}

protocol WindowPropertyEventTypeInternal: WindowPropertyEventType {
  init(external: Bool, window: WindowType, oldVal: PropertyType, newVal: PropertyType)
}

public struct WindowPosChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = CGPoint
  public var external: Bool
  public var window: WindowType
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct WindowSizeChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = CGSize
  public var external: Bool
  public var window: WindowType
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct WindowTitleChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = String
  public var external: Bool
  public var window: WindowType
  public var oldVal: PropertyType
  public var newVal: PropertyType
}
