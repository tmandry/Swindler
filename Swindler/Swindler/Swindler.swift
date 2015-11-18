/// The state represents the entire state of the OS, including all known windows, applications, and
/// spaces.
public protocol StateType {
  var visibleWindows: [WindowType] { get }
  func on<Event: EventType>(handler: (Event) -> ())
}

/// A window.
public protocol WindowType {
  /// Whether or not the window referred to by this type remains valid. Windows usually become
  /// invalid because they are destroyed (in which case a WindowDestroyedEvent will be emitted).
  /// They can also become invalid because they do not have all the required properties, or because
  /// the application that owns them is otherwise not giving a well-behaved response.
  var valid: Bool { get }

  /// The position of the top-left corner of the window in screen coordinates.
  var pos: WriteableProperty<CGPoint>! { get }
  /// The size of the window in screen coordinates.
  var size: WriteableProperty<CGSize>! { get }

  /// The window title.
  var title: Property<String>! { get }
}

extension WindowType {
  /// Convenience parameter for getting the position and size as a rectangle.
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

/// The basic protocol for an event struct.
public protocol EventType {
  /// All events are marked as internal or external. Internal events were caused via Swindler,
  /// external events were not.
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

/// An event on a window.
public protocol WindowEventType: EventType {
  var external: Bool { get }
  /// The window corresponding to the event.
  var window: WindowType { get }
}

public struct WindowCreatedEvent: WindowEventType {
  public var external: Bool
  public var window: WindowType
}

public struct WindowDestroyedEvent: WindowEventType {
  public var external: Bool
  public var window: WindowType
}

/// An event describing a window property change.
public protocol WindowPropertyEventType: WindowEventType {
  typealias PropertyType: Equatable

  /// The old value of the property.
  var oldVal: PropertyType { get }
  /// The new value of the property.
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
