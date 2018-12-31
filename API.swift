// API.swift
//
// This file defines the eventual API that Swindler will expose. It is not compiled, but serves as
// a roadmap for development.
//
// Everything should be documented.
// The API should conform to Swift's API Design Guidelines:
// https://swift.org/documentation/api-design-guidelines.html

/// The state represents the entire state of the OS, including all known windows, applications, and
/// spaces.
public protocol State {
    /// The currently running applications.
    public var runningApplications: [Application] { get }

    /// The frontmost application.
    public var frontmostApplication: WriteableProperty<OfOptionalType<Application>> { get }

    /// All windows that we know about. Windows on spaces that we haven't seen yet aren't included.
    public var knownWindows: [Window] { get }

    // TODO:
    /// All windows that are currently visible on the screen (including those that are obscured
    /// fully by other windows). This does not include windows that are minimized, hidden, or on
    /// another space.
    public var visibleWindows: [Window] { get }

    /// The physical screens in the current display configuration.
    public var screens: [Screen]

    // TODO:
    /// All spaces the user has been to since Swindler was started.
    public var knownSpaces: [Space]
    /// The current space the user is on (one per screen).
    public var currentSpaces: [Space]

    /// Calls `handler` when the specified `Event` occurs.
    public func on<Event: EventType>(handler: (Event) -> Void)
}

// Events

// FrontmostApplicationChanged

/// A running application.
public protocol Application {
    /// The global Swindler state.
    public var swindlerState: State { get }

    /// The process ID of this application.
    public var processIdentifier: pid_t { get }
    /// The bundle ID of this application, if it has one.
    public var bundleIdentifier: String? { get }

    /// The known windows of the application. Windows on spaces that we haven't seen yet aren't
    /// included.
    public var knownWindows: [Window] { get }

    // TODO: (convenience)
    /// All application windows that are currently visible on the screen (including those that are
    /// obscured fully by other windows). This does not include windows that are minimized, hidden,
    /// or on another space.
    public var visibleWindows: [Window] { get }

    /// The main window of the application.
    /// -Note: Setting this will bring the window forward to just below the main window of the
    ///        frontmost application.
    public var mainWindow: WriteableProperty<OfOptionalType<Window>> { get }

    /// The focused (or key) window of the application, the one currently accepting keyboard input.
    /// Usually the same as the main window, or one of its helper windows such as a file open
    /// dialog.
    ///
    /// -Note: Sometimes the focused "window" is a sheet that is not a window (i.e. it has no title
    ///        bar and cannot be moved by the user). In that case the value will be nil.
    public var focusedWindow: Property<OfOptionalType<Window>> { get }

    // TODO: (convenience)
    /// Whether the application is the frontmost application.
    public var isFrontmost: WriteableProperty<OfType<Bool>> { get }

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
    /// The application the window belongs to.
    public var application: Application { get }

    /// Whether or not the window referred to by this type remains valid. Windows usually become
    /// invalid because they are destroyed (in which case a WindowDestroyedEvent will be emitted).
    /// They can also become invalid because they do not have all the required properties, or
    /// because the application that owns them is otherwise not giving a well-behaved response.
    public var isValid: Bool { get }

    /// The frame of the window.
    public var frame: WriteableProperty<OfType<CGRect>> { return delegate.frame }
    /// The position of the bottom-left corner of the window in screen coordinates.
    /// To set this, use `frame.origin`. This property may be removed in the future.
    public var position: Property<OfType<CGPoint>> { get }
    /// The size of the window in screen coordinates.
    public var size: WriteableProperty<OfType<CGSize>> { get }

    /// The window title.
    public var title: Property<OfType<String>> { get }

    /// Whether the window is minimized.
    public var isMinimized: WriteableProperty<OfType<Bool>> { get }

    // TODO: (convenience)
    /// Whether or not the window is the main window of its application.
    public var isMain: WriteableProperty<OfType<Bool>> { get }

    // TODO: (convenience)
    /// Whether or not the window is the focused (key) window of its application, the one currently
    /// accepting keyboard input.
    public var isFocused: Property<OfType<Bool>> { get }

    /// Whether the window is full screen or not.
    public var isFullscreen: WriteableProperty<OfType<Bool>> { get }

    /// The screen that (most of) the window is on. `nil` if the window is completely off-screen.
    public var screen: Property<OfType<Screen>> { get }

    // TODO:
    /// The space of the window. If nil, it is assigned to all spaces.
    public var space: Property<OfOptionalType<Space>> { get }
}

// Events

// WindowCreatedEvent
// WindowDestroyedEvent
// WindowFrameChangedEvent
// WindowMinimizedChangedEvent
// WindowTitleChangedEvent
//
// WindowDiscoveredEvent
// IsFullScreenChanged (?)
// ScreenChanged
//   - cause: {.Moved, .ScreenLayoutChanged}
// SpaceChanged

/// A physical display.
public protocol Screen: Equatable {
    /// The frame defining the screen boundaries in global coordinates. Note that x and y may be
    /// negative.

    public var frame: CGRect { get }

    /// The frame defining the screen boundaries in global coordinates, excluding the menu bar and
    /// dock.
    public var applicationFrame: CGRect { get }

    // TODO:
    /// The windows currently visible on this screen.
    public var visibleWindows: [Window] { get }

    // TODO:
    // use case?
    /// The known windows that are on this screen.
    public var knownWindows: [Window] { get }

    // TODO:
    /// The known spaces that correspond to this screen.
    public var knownSpaces: [Space] { get }

    // TODO:
    /// The space that is currently visible on this screen.
    public var currentSpace: Space { get }
}

// Events

struct ScreenLayoutChangedEvent {
    let external: Bool
    let addedScreens: [Screen]
    let removedScreens: [Screen]
    /// Screens whose frame has changed (moved, resized, or both).
    let changedScreens: [Screen]
    let unchangedScreens: [Screen]
}

// TODO:
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

    /// The known windows on this space. Additional windows could exist if this is not the current
    /// space and new windows were created on it since the user last visited it.
    public var knownWindows: [Window] { get }

    /// The known visible windows on this space.
    public var visibleWindows: [Window] { get }
}

// Events

// SpaceChanged
// SpaceDiscovered
// SpaceCulled?

struct SpaceChangedEvent {
    var screen: Screen
    var oldValue: Space
    var newValue: Space
    var windowsLost: [Window]
    var windowsGained: [Window]
}

/// The basic protocol for an event struct.
public protocol EventType {
    /// All events are marked as internal or external. Internal events were caused via Swindler,
    /// external events were not.
    var external: Bool { get }
}

public struct WindowCreatedEvent: EventType {
    public var external: Bool
    public var window: Window
}

public struct WindowDestroyedEvent: EventType {
    public var external: Bool
    public var window: Window
}

public struct WindowPosChangedEvent: EventType {
    public typealias PropertyType = CGPoint
    public var external: Bool
    public var window: Window
    public var oldValue: PropertyType
    public var newValue: PropertyType
}

public struct WindowSizeChangedEvent: EventType {
    public typealias PropertyType = CGSize
    public var external: Bool
    public var window: Window
    public var oldValue: PropertyType
    public var newValue: PropertyType
}

public struct WindowTitleChangedEvent: EventType {
    public typealias PropertyType = String
    public var external: Bool
    public var window: Window
    public var oldValue: PropertyType
    public var newValue: PropertyType
}

public struct WindowMinimizedChangedEvent: EventType {
    public typealias PropertyType = Bool
    public var external: Bool
    public var window: Window
    public var oldValue: PropertyType
    public var newValue: PropertyType
}

public struct ApplicationFrontmostChangedEvent: EventType {
    public typealias PropertyType = Bool
    public var external: Bool
    public var application: Application
    public var oldValue: PropertyType
    public var newValue: PropertyType
}

public struct ApplicationMainWindowChangedEvent: EventType {
    public typealias PropertyType = Window?
    public var external: Bool
    public var application: Application
    public var oldValue: PropertyType
    public var newValue: PropertyType
}
