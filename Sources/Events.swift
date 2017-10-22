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
    associatedtype PropertyType
    associatedtype Object
    init(external: Bool, object: Object, oldValue: PropertyType, newValue: PropertyType)

    /// The old value of the property.
    var oldValue: PropertyType { get }
    /// The new value of the property.
    var newValue: PropertyType { get }
    // TODO: requestedVal?
}

protocol StatePropertyEventType: PropertyEventType {
    associatedtype Object = State
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

public struct ApplicationLaunchedEvent: EventType {
    public let external: Bool
    public let application: Application
}

public struct ApplicationTerminatedEvent: EventType {
    public let external: Bool
    public let application: Application
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
    associatedtype Object = Window
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
    associatedtype Object = Application
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

public struct ScreenLayoutChangedEvent: EventType {
    public let external: Bool
    public let addedScreens: [Screen]
    public let removedScreens: [Screen]
    /// Screens whose frame has changed (moved, resized, or both).
    public let changedScreens: [Screen]
    public let unchangedScreens: [Screen]
}
