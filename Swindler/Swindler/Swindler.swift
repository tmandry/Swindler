public protocol State {
  var visibleWindows: [Window] { get }
  func onEvent(notification: Notification, handler: EventHandler)
  func onWindowPropertyChanged(property: WindowProperty, handler: WindowPropertyHandler)
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

public typealias EventHandler = (event: Event) -> ()

public enum Notification {
  // (window)
  case WindowCreated
  case WindowDiscovered
  case WindowDestroyed
  // case WindowPropertyChanged(property: OSXWindow.Attribute)
  //  // (window, cause: {SpaceChange, ...})
  //  case WindowMoved
  //  // (window, oldSize, [newSize], cause)
  //  case WindowResized
  //  // (window, cause)
  //  case WindowClosed
  //  // (window, cause)
  //  case WindowMinimized
  // (oldSpace, newSpace, windowsArrived, windowsDeparted)
  case SpaceChanged
  // (oldLayout?, newLayout)
  case ScreenLayoutChanged
}

public protocol Event {
  var external: Bool { get }
}

public struct WindowEvent: Event {
  public var window: Window
  public var external: Bool
}

public typealias WindowPropertyHandler = (event: Event) -> ()

protocol GenericWindowPropertyEvent: Event {
  typealias PropertyType

  var window: Window { get }
  var oldVal: PropertyType { get }
  var newVal: PropertyType { get }
  // TODO: requestedVal?
}

public struct WindowPropertyEvent<PropertyType>: GenericWindowPropertyEvent {
  public var window: Window
  public var external: Bool
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public typealias WindowPosChangedEvent = WindowPropertyEvent<CGPoint>
public typealias WindowSizeChangedEvent = WindowPropertyEvent<CGSize>

public enum WindowProperty {
  case Pos
  case Size
}
