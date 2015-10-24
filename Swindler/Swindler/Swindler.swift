public protocol State {
  var visibleWindows: [Window] { get }
  func on<EventType: Event>(handler: (EventType) -> ())
}

public protocol Window {
  var pos: CGPoint { get set }
  var size: CGSize { get set }
  var rect: CGRect { get set }
}

extension Window {
  // Convenience parameter
  var rect: CGRect {
    get { return CGRect(origin: pos, size: size) }
    set {
      pos = newValue.origin
      size = newValue.size
    }
  }
}

// (oldSpace, newSpace, windowsArrived, windowsDeparted)
// case SpaceChanged
// (oldLayout?, newLayout)
// case ScreenLayoutChanged

public protocol Event {
  var external: Bool { get }
}

extension Event {
  // In a later version of Swift, this can be stored (lazily).. store as hashValue for more speed.
  // Instead of using this, we _could_ use an enum of all notifications and require each event to
  // declare a static var of its notification. That's error prone, though, and this is fast enough.
  static var typeName: String {
    return Mirror(reflecting: Self.self).description
  }
}

public protocol WindowEvent: Event {
  var window: Window { get }
  var external: Bool { get }
}

public struct WindowCreatedEvent: Event {
  public var external: Bool
  public var window: Window
}

public struct WindowDestroyedEvent: Event {
  public var external: Bool
  public var window: Window
}

public protocol WindowPropertyEvent: WindowEvent {
  typealias PropertyType: Equatable

  var oldVal: PropertyType { get }
  var newVal: PropertyType { get }

  // TODO: requestedVal?
}

protocol WindowPropertyEventInternal: WindowPropertyEvent {
  init(external: Bool, window: Window, oldVal: PropertyType, newVal: PropertyType)
}

public struct WindowPosChangedEvent: WindowPropertyEventInternal {
  public typealias PropertyType = CGPoint

  public var external: Bool
  public var window: Window
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct WindowSizeChangedEvent: WindowPropertyEventInternal {
  public typealias PropertyType = CGSize

  public var external: Bool
  public var window: Window
  public var oldVal: PropertyType
  public var newVal: PropertyType
}
