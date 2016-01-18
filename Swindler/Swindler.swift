/// The state represents the entire state of the OS, including all known windows, applications, and
/// spaces.
public final class State {
  let delegate: StateDelegate
  init(delegate: StateDelegate) {
    self.delegate = delegate
  }

  /// The currently running applications.
  public var runningApplications: [Application] { return delegate.runningApplications.map{ Application(delegate: $0) } }

  /// The frontmost application.
  public var frontmostApplication: WriteableProperty<OfOptionalType<Application>> { return delegate.frontmostApplication }

  /// All windows that we know about. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { return delegate.knownWindows.flatMap{ Window(delegate: $0) } }

  /// The physical screens in the current display configuration.
  public var screens: [Screen] { return delegate.screens.map{ Screen(delegate: $0) } }

  /// Calls `handler` when the specified `Event` occurs.
  public func on<Event: EventType>(handler: (Event) -> ()) { delegate.on(handler) }
}

// All public classes in Swindler are implemented with an internal delegate. This decoupling aids in
// testing and hides implementation details from the API.
//
// Our delegates differ from most Apple API delegates in that they are internal and are critical to
// the functioning of the class, so they are not held with weak references.
protocol StateDelegate {
  var runningApplications: [ApplicationDelegate] { get }
  var frontmostApplication: WriteableProperty<OfOptionalType<Application>>! { get }
  var knownWindows: [WindowDelegate] { get }
  var screens: [ScreenDelegate] { get }
  func on<Event: EventType>(handler: (Event) -> ())
}

/// A running application.
public final class Application: Equatable {
  let delegate: ApplicationDelegate
  init(delegate: ApplicationDelegate) {
    self.delegate = delegate
  }

  /// The known windows of the application. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { return delegate.knownWindows.flatMap({ Window(delegate: $0) }) }

  /// The main window of the application.
  /// -Note: Setting this will bring the window forward to just below the main window of the frontmost
  ///        application.
  public var mainWindow: WriteableProperty<OfOptionalType<Window>> { return delegate.mainWindow }

  /// The focused (or key) window of the application, the one currently accepting keyboard input.
  /// Usually the same as the main window, or one of its helper windows such as a file open dialog.
  ///
  /// -Note: Sometimes the focused "window" is a sheet and not a window (i.e. it has no title bar
  ///        and cannot be moved by the user). In that case the value will be nil.
  public var focusedWindow: Property<OfOptionalType<Window>> { return delegate.focusedWindow }

  /// Whether the application is hidden.
  public var isHidden: WriteableProperty<OfType<Bool>> { return delegate.isHidden }
}
public func ==(lhs: Application, rhs: Application) -> Bool {
  return lhs.delegate.equalTo(rhs.delegate)
}

protocol ApplicationDelegate: class {
  var processID: pid_t! { get }

  var knownWindows: [WindowDelegate] { get }

  var mainWindow: WriteableProperty<OfOptionalType<Window>>! { get }
  var focusedWindow: Property<OfOptionalType<Window>>! { get }
  var isHidden: WriteableProperty<OfType<Bool>>! { get }

  func equalTo(other: ApplicationDelegate) -> Bool
}

/// A window.
public final class Window: Equatable {
  internal let delegate: WindowDelegate

  // A Window holds a strong reference to the Application and therefore the ApplicationDelegate.
  // It should not be held internally by delegates, or it could create a reference cycle.
  private var application_: Application!

  internal init(delegate: WindowDelegate, appDelegate: ApplicationDelegate) {
    self.delegate = delegate
    self.application_ = Application(delegate: appDelegate)
  }

  /// This initializer fails only if the ApplicationDelegate is no longer reachable (because the
  /// application terminated, which means this window no longer exists).
  internal convenience init?(delegate: WindowDelegate) {
    guard let appDelegate = delegate.appDelegate else {
      // The application terminated.
      log.debug("Window for delegate \(delegate) failed to initialize because of unreachable ApplicationDelegate")
      return nil
    }
    self.init(delegate: delegate, appDelegate: appDelegate)
  }

  /// The application the window belongs to.
  public var application: Application { return application_ }

  /// Whether or not the window referred to by this type remains valid. Windows usually become
  /// invalid because they are destroyed (in which case a WindowDestroyedEvent will be emitted).
  /// They can also become invalid because they do not have all the required properties, or because
  /// the application that owns them is otherwise not giving a well-behaved response.
  public var isValid: Bool { return delegate.isValid }

  /// The position of the top-left corner of the window in screen coordinates.
  public var position: WriteableProperty<OfType<CGPoint>> { return delegate.position }
  /// The size of the window in screen coordinates.
  public var size: WriteableProperty<OfType<CGSize>> { return delegate.size }

  /// The window title.
  public var title: Property<OfType<String>> { return delegate.title }

  /// Whether the window is minimized.
  public var isMinimized: WriteableProperty<OfType<Bool>> { return delegate.isMinimized }

  /// Whether the window is fullscreen or not.
  public var isFullscreen: WriteableProperty<OfType<Bool>> { return delegate.isFullscreen }
}
public func ==(lhs: Window, rhs: Window) -> Bool {
  return lhs.delegate.equalTo(rhs.delegate)
}

protocol WindowDelegate: class {
  var isValid: Bool { get }

  // Optional because a WindowDelegate shouldn't hold a strong reference to its parent ApplicationDelegate.
  var appDelegate: ApplicationDelegate? { get }

  var position: WriteableProperty<OfType<CGPoint>>! { get }
  var size: WriteableProperty<OfType<CGSize>>! { get }
  var title: Property<OfType<String>>! { get }
  var isMinimized: WriteableProperty<OfType<Bool>>! { get }
  var isFullscreen: WriteableProperty<OfType<Bool>>! { get }

  func equalTo(other: WindowDelegate) -> Bool
}

/// A physical display.
public final class Screen: Equatable, CustomDebugStringConvertible {
  internal let delegate: ScreenDelegate
  internal init(delegate: ScreenDelegate) {
    self.delegate = delegate
  }

  public var debugDescription: String { return delegate.debugDescription }

  /// The frame defining the screen boundaries in global coordinates.
  /// -Note: x and y may be negative.
  public var frame: CGRect { return delegate.frame }

  /// The frame defining the screen boundaries in global coordinates, excluding the menu bar and dock.
  public var applicationFrame: CGRect { return delegate.applicationFrame }
}
public func ==(lhs: Screen, rhs: Screen) -> Bool {
  return lhs.delegate.equalTo(rhs.delegate)
}

internal protocol ScreenDelegate: class, CustomDebugStringConvertible {
  var frame: CGRect { get }
  var applicationFrame: CGRect { get }

  func equalTo(other: ScreenDelegate) -> Bool
}

// (oldSpace, newSpace, windowsArrived, windowsDeparted)
// case SpaceChanged
// (oldLayout?, newLayout)
// case ScreenLayoutChanged

// MARK: - Events

/// The basic protocol for an event struct.
public protocol EventType {
  /// All events are marked as internal or external. Internal events were caused via Swindler,
  /// external events were not.
  var external: Bool { get }
}

internal extension EventType {
  // In a later version of Swift, this can be stored (lazily).. store as hashValue for more speed.
  // Instead of using this, we _could_ use an enum of all notifications and require each event to
  // declare a static var of its notification. That's error prone, though, and this is fast enough.
  static var typeName: String {
    return Mirror(reflecting: Self.self).description
  }
}

/// An event describing a property change.
protocol PropertyEventType: EventType {
  typealias PropertyType
  typealias Object
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType)

  /// The old value of the property.
  var oldValue: PropertyType { get }
  /// The new value of the property.
  var newValue: PropertyType { get }
  // TODO: requestedVal?
}

protocol StatePropertyEventType: PropertyEventType {
  typealias Object = State
  init(external: Bool, state: Object, oldValue: PropertyType, newValue: PropertyType)
}
extension StatePropertyEventType {
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType) {
    self.init(external: external, state: object, oldValue: oldValue, newValue: newValue)
  }
}

public struct FrontmostApplicationChangedEvent: StatePropertyEventType {
  public typealias PropertyType = Application?
  public let external: Bool
  public let state: State
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

public struct WindowCreatedEvent: EventType {
  public let external: Bool
  public let window: Window
}

public struct WindowDestroyedEvent: EventType {
  public let external: Bool
  public let window: Window
}

protocol WindowPropertyEventType: PropertyEventType {
  typealias Object = Window
  init(external: Bool, window: Object, oldValue: PropertyType, newValue: PropertyType)
}
extension WindowPropertyEventType {
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType) {
    self.init(external: external, window: object, oldValue: oldValue, newValue: newValue)
  }
}

public struct WindowPosChangedEvent: WindowPropertyEventType {
  public typealias PropertyType = CGPoint
  public let external: Bool
  public let window: Window
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

public struct WindowSizeChangedEvent: WindowPropertyEventType {
  public typealias PropertyType = CGSize
  public let external: Bool
  public let window: Window
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

public struct WindowTitleChangedEvent: WindowPropertyEventType {
  public typealias PropertyType = String
  public let external: Bool
  public let window: Window
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

public struct WindowMinimizedChangedEvent: WindowPropertyEventType {
  public typealias PropertyType = Bool
  public let external: Bool
  public let window: Window
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

protocol ApplicationPropertyEventType: PropertyEventType {
  typealias Object = Application
  init(external: Bool, application: Object, oldValue: PropertyType, newValue: PropertyType)
}
extension ApplicationPropertyEventType {
  init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType) {
    self.init(external: external, application: object, oldValue: oldValue, newValue: newValue)
  }
}

public struct ApplicationIsHiddenChangedEvent: ApplicationPropertyEventType {
  public typealias PropertyType = Bool
  public let external: Bool
  public let application: Application
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

public struct ApplicationMainWindowChangedEvent: ApplicationPropertyEventType {
  public typealias PropertyType = Window?
  public let external: Bool
  public let application: Application
  public let oldValue: PropertyType
  public let newValue: PropertyType
}

public struct ApplicationFocusedWindowChangedEvent: ApplicationPropertyEventType {
  public typealias PropertyType = Window?
  public let external: Bool
  public let application: Application
  public let oldValue: PropertyType
  public let newValue: PropertyType
}
