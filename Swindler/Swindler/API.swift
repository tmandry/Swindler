// API.swift
//
// This file defines the eventual API that Swindler will expose. It is not compiled, but serves as
// a roadmap for development.
//
// Everything should be documented.
// The API should conform to Swift's API Design Guidelines: https://swift.org/documentation/api-design-guidelines.html

/// The state represents the entire state of the OS, including all known windows, applications, and
/// spaces.
public protocol State {
  /// The currently running applications.
  public var runningApplications: [Application] { get }

  /// All windows that we know about. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { get }

  // TODO
  /// All windows that are currently visible on the screen (including those that are obscured fully
  /// by other windows). This does not include windows that are minimized, hidden, or on another space.
  public var visibleWindows: [Window] { get }

  // TODO
  /// The physical screens in the current display configuration.
  public var screens: [Screen]

  // TODO
  /// All spaces the user has been to since Swindler was started.
  public var knownSpaces: [Space]
  /// The current space the user is on (one per screen).
  public var currentSpaces: [Space]

  /// Calls `handler` when the specified `Event` occurs.
  public func on<Event: EventType>(handler: (Event) -> ())
}

/// A running application.
public protocol Application {
  // TODO
  /// The NSRunningApplication that corresponds to this application.
  public var runningApplication: NSRunningApplication { get }

  /// The known windows of the application. Windows on spaces that we haven't seen yet aren't included.
  public var knownWindows: [Window] { get }

  // TODO
  /// All application windows that are currently visible on the screen (including those that are obscured fully
  /// by other windows). This does not include windows that are minimized, hidden, or on another space.
  public var visibleWindows: [Window] { get }

  // TODO: writeable
  /// The main window of the application.
  public var mainWindow: WriteableProperty<OfOptionalType<Window>> { get }

  /// The focused (key) window of the application, the one currently accepting keyboardinput.
  public var focusedWindow: Property<OfOptionalType<Window>> { get }

  /// Whether the application is the frontmost application.
  public var isFrontmost: WriteableProperty<OfType<Bool>> { get }

  // TODO
  /// Whether the application is hidden.
  public var isHidden: WriteableProperty<OfType<Bool>> { get }

  /// TODO?
  public var isAssignedToSpace: Bool
  public var isAssignedToAllSpaces: Bool
}

// Events

// ApplicationLaunched
// ApplicationTerminated
//
// MainWindowChanged
// FocusedWindowChanged
// IsHiddenChanged
// IsFrontmostChanged

/// A window.
public protocol Window: Equatable {
  // TODO
  /// The application the window belongs to.
  public var application: Application { get }

  // TODO: name
  /// Whether or not the window referred to by this type remains valid. Windows usually become
  /// invalid because they are destroyed (in which case a WindowDestroyedEvent will be emitted).
  /// They can also become invalid because they do not have all the required properties, or because
  /// the application that owns them is otherwise not giving a well-behaved response.
  public var isValid: Bool { get }

  /// The position of the top-left corner of the window in screen coordinates.
  public var pos: WriteableProperty<OfType<CGPoint>> { get }
  /// The size of the window in screen coordinates.
  public var size: WriteableProperty<OfType<CGSize>> { get }

  /// The window title.
  public var title: Property<OfType<String>> { get }

  // TODO: name
  /// Whether the window is minimized.
  public var isMinimized: WriteableProperty<OfType<Bool>> { get }

  // TODO
  /// Whether or not the window is the main window of its application.
  public var isMain: WriteableProperty<OfType<Bool>> { get }

  // TODO
  /// Whether or not the window is the focused (key) window of its application, the one currently
  /// accepting keyboard input.
  public var isFocused: Property<OfType<Bool>> { get }

  // TODO
  /// Whether the window is full screen or not.
  public var isFullScreen: WriteableProperty<OfType<Bool>> { get }

  // TODO
  /// The screen that (most of) the window is on.
  public var screen: Property<OfType<Screen>> { get }

  // TODO
  /// The space of the window. If nil, it is assigned to all spaces.
  public var space: Property<OfOptionalType<Space>> { get }
}

// Events

// WindowCreatedEvent
// WindowDestroyedEvent
// WindowDiscoveredEvent
//
// PositionChanged
// SizeChanged
// TitleChanged
// IsMinimizedChanged
// IsFullScreenChanged (?)
// ScreenChanged
//   - cause: {.Moved, .ScreenLayoutChanged}
// SpaceChanged

// TODO
/// A physical display.
public protocol Screen: Equatable {
  /// The rectangle defining the screen boundaries in global coordinates. Note that these may be negative.
  public var rect: CGRect { get }

  /// The windows currently visible on this screen.
  public var visibleWindows: [Window] { get }

  // use case?
  /// The known windows that are on this screen.
  public var knownWindows: [Window] { get }

  /// The known spaces that correspond to this screen.
  public var knownSpaces: [Space] { get }

  /// The space that is currently visible on this screen.
  public var currentSpace: Space { get }
}

// Events

// ScreenLayoutChanged
// SpaceChanged

struct SpaceChangedEvent {
  var screen: Screen
  var oldValue: Space
  var newValue: Space
  var windowsLost: [Window]
  var windowsGained: [Window]
}

// TODO
// Spaces may be culled when they no longer have any windows and are not visible?
/// A space, or virtual desktop. In Swindler, spaces correspond to only one screen. Many users have
/// the option "displays have separate spaces", and this corresponds to that option, which is more
/// general. For users who do not, every system space is actually made of `screens.count` spaces in
/// Swindler, and switching spaces will cause that many space change events to be emitted.
public protocol Space: Equatable {
  /// The screen this space corresponds to.
  public var screen: Screen { get }

  /// Whether the space is the current space on `screen`.
  public var isVisible: Bool { get }

  /// The known windows on this space. Additional windows could exist if this is not the current space
  /// and new windows were created on it since the user last visited it.
  public var knownWindows: [Window] { get }

  /// The known visible windows on this space.
  public var visibleWindows: [Window] { get }
}

// Events

// SpaceDiscovered
// SpaceCulled?

/// The basic protocol for an event struct.
public protocol EventType {
  /// All events are marked as internal or external. Internal events were caused via Swindler,
  /// external events were not.
  var external: Bool { get }
}

/// An event on a window.
public protocol WindowEventType: EventType {
  var external: Bool { get }  // TODO: remove
  /// The window corresponding to the event.
  var window: Window { get }
}

public struct WindowCreatedEvent: WindowEventType {
  public var external: Bool
  public var window: Window
}

public struct WindowDestroyedEvent: WindowEventType {
  public var external: Bool
  public var window: Window
}

/// An event describing a property change.
public protocol PropertyEventType: EventType {
  typealias PropertyType

  var external: Bool { get }
  /// The old value of the property.
  var oldVal: PropertyType { get }
  /// The new value of the property.
  var newVal: PropertyType { get }
  // TODO: requestedVal?
}

public protocol WindowPropertyEventType: WindowEventType, PropertyEventType {}

public struct WindowPosChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = CGPoint
  public var external: Bool
  public var window: Window
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct WindowSizeChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = CGSize
  public var external: Bool
  public var window: Window
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct WindowTitleChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = String
  public var external: Bool
  public var window: Window
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct WindowMinimizedChangedEvent: WindowPropertyEventTypeInternal {
  public typealias PropertyType = Bool
  public var external: Bool
  public var window: Window
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public protocol ApplicationEventType: EventType {
  var application: Application { get }
}

public protocol ApplicationPropertyEventType: ApplicationEventType, PropertyEventType {}

public struct ApplicationFrontmostChangedEvent: ApplicationPropertyEventTypeInternal {
  public typealias PropertyType = Bool
  public var external: Bool
  public var application: Application
  public var oldVal: PropertyType
  public var newVal: PropertyType
}

public struct ApplicationMainWindowChangedEvent: ApplicationPropertyEventTypeInternal {
  public typealias PropertyType = Window?
  public var external: Bool
  public var application: Application
  public var oldVal: PropertyType
  public var newVal: PropertyType
}