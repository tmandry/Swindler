import AXSwift
import PromiseKit

/// A PropertyNotifier handles property events and directs them to the right place.
protocol PropertyNotifier: class {
    associatedtype Object

    /// Called when the property value has been updated.
    func notify<Event: PropertyEventType>(
        _ event: Event.Type,
        external: Bool,
        oldValue: Event.PropertyType,
        newValue: Event.PropertyType
    ) where Event.Object == Object

    /// Called when the underlying object has become invalid.
    func notifyInvalid()
}

/// A PropertyDelegate is responsible for reading and writing property values to/from the OS.
///
/// - important: You must only throw PropertyErrors from your methods.
/// - note: Throw PropertyError.InvalidObject from any method, and `notifyInvalid()` will be called
///         on the WindowPropertyNotifier.
protocol PropertyDelegate {
    associatedtype T: Equatable

    /// Synchronously read the property value from the OS. May be called on a background thread.
    func readValue() throws -> T?

    /// Synchronously write the property value to the OS. May be called on a background thread.
    func writeValue(_ newValue: T) throws

    /// Returns a promise of the property's initial value. It's the responsibility of whoever
    /// defines the property to ensure that the property is not accessed before this promise
    /// resolves.
    /// You can call `refresh()` on the property, however, as it will wait for this to resolve.
    func initialize() -> Promise<T?>
}

public enum PropertyError: Error {
    /// The value the property was set to is illegal.
    /// - note: In practice, applications often simply ignore illegal values instead of returning
    ///         this error.
    case illegalValue

    /// The application did not respond to our request quickly enough.
    case timeout(time: TimeInterval)

    /// The value of the (required) property is missing from the object on the OS.
    case missingValue

    /// The underlying object for the property has become invalid (e.g. the window has been
    /// destroyed). This is considered a permanent failure.
    case invalidObject(cause: Error)

    /// Some other, hopefully temporary, failure.
    case failure(cause: Error)
}

// In Swift, even when T: Equatable, we don't have T?: Equatable (but you CAN compare optionals with
// ==). To get around this while keeping our code general, we have to specify all this explicitly.

public protocol PropertyTypeSpec {
    associatedtype NonOptionalType: Equatable
    /// The property type, which might be the same as the base type, or Optional<NonOptionalType>.
    associatedtype PropertyType
    static func equal(_ lhs: PropertyType, _ rhs: PropertyType) -> Bool
    static func toPropertyType(_ from: NonOptionalType?) throws -> PropertyType
    static func toOptionalType(_ from: PropertyType) -> NonOptionalType?
}

public struct OfType<T: Equatable>: PropertyTypeSpec {
    public typealias NonOptionalType = T
    public typealias PropertyType = T
    public static func equal(_ lhs: T, _ rhs: T) -> Bool { return lhs == rhs }
    public static func toPropertyType(_ from: T?) throws -> T {
        guard let to: T = from else {
            // TODO: unexpected error
            log.error("Cannot convert property value \(String(describing: from)) to type \(T.self)")
            throw PropertyError.invalidObject(cause: PropertyError.missingValue)
        }
        return to
    }
    public static func toOptionalType(_ from: T) -> T? { return from }
}

public struct OfOptionalType<T: Equatable>: PropertyTypeSpec {
    public typealias NonOptionalType = T
    public typealias PropertyType = T?
    public static func equal(_ lhs: T?, _ rhs: T?) -> Bool { return lhs == rhs }
    public static func toPropertyType(_ from: T?) throws -> T? { return from }
    public static func toOptionalType(_ from: T?) -> T? { return from }
}

/// A property on a window. Property values are watched and cached in the background, so they are
/// always available to read.
///
/// - throws: Only `PropertyError` errors are given for rejected promises.
open class Property<TypeSpec: PropertyTypeSpec> {
    public typealias PropertyType = TypeSpec.PropertyType
    public typealias NonOptionalType = TypeSpec.NonOptionalType
    public typealias OptionalType = TypeSpec.NonOptionalType?

    // The backing store
    fileprivate var value_: PropertyType!
    // Implementation of how to read and write the value
    fileprivate var delegate_: PropertyDelegateThunk<TypeSpec>
    // Where events go
    fileprivate var notifier: PropertyNotifierThunk<TypeSpec>

    // Only do one request on a given property at a time. This ensures that events get emitted from
    // the right operation.
    fileprivate let requestLock = NSLock()
    // Since the backing store can be updated on another thread, we need to lock it.
    // This lock MUST NOT be held during a slow call. Only hold it as long as necessary.
    fileprivate let backingStoreLock = NSLock()

    // Exposed for testing only.
    var backgroundQueue: DispatchQueue = DispatchQueue.global(qos: .default)

    // Property definer is responsible for ensuring that it is NOT used before this promise
    // resolves.
    fileprivate(set) var initialized: Promise<Void>
    // Property definer can access the delegate they provided here
    fileprivate(set) var delegate: Any

    init<Impl: PropertyDelegate, Notifier: PropertyNotifier>(
        _ delegate: Impl,
        notifier: Notifier
    ) where Impl.T == NonOptionalType {
        self.notifier = PropertyNotifierThunk(notifier)
        self.delegate = delegate
        delegate_ = PropertyDelegateThunk(delegate)

        let (initialized, fulfill, reject) = Promise<Void>.pending()
        self.initialized = initialized // must be set before capturing `self` in a closure

        delegate.initialize().then { (value: OptionalType) -> Void in
            self.value_ = try TypeSpec.toPropertyType(value)
            fulfill(())
        }.catch { error in
            do {
                try self.handleError(error)
            } catch {
                reject(error)
            }
        }
    }

    /// Use this initializer if there is an event associated with the property.
    convenience init<Impl: PropertyDelegate,
                     Notifier: PropertyNotifier,
                     Event: PropertyEventType,
                     Object>(
        _ delegate: Impl,
        withEvent: Event.Type,
        receivingObject: Object.Type,
        notifier: Notifier
    ) where Impl.T == NonOptionalType,
            Event.PropertyType == PropertyType,
            Event.Object == Object,
            Notifier.Object == Object {
        self.init(delegate, notifier: notifier)
        self.notifier = PropertyNotifierThunk(notifier,
                                              withEvent: Event.self,
                                              receivingObject: Object.self)
    }

    /// The value of the property.
    public var value: PropertyType {
        backingStoreLock.lock()
        defer { backingStoreLock.unlock() }
        return value_
    }

    /// Forces the value of the property to refresh. Most properties are watched so you don't need
    /// to call this yourself.
    public final func refresh() -> Promise<PropertyType> {
        // Allow queueing up a refresh before initialization is complete, which means "assume the
        // value you will be initialized with is going to be stale". This is useful if an event is
        // received before fully initializing.
        return initialized.then(on: backgroundQueue) { () -> (PropertyType, PropertyType) in
            self.requestLock.lock()
            defer { self.requestLock.unlock() }

            let actual = try TypeSpec.toPropertyType(self.delegate_.readValue())
            let oldValue = self.updateBackingStore(actual)

            return (oldValue, actual)
        }.then { (oldValue: PropertyType, actual: PropertyType) throws -> PropertyType in
            // Back on main thread.
            if !TypeSpec.equal(oldValue, actual) {
                self.notifier.notify?(true, oldValue, actual)
            }
            return actual
        }.recover { error in
            try self.handleError(error)
        }
    }

    /// Synchronously updates the backing store and returns the old value.
    fileprivate func updateBackingStore(_ newValue: PropertyType) -> PropertyType {
        backingStoreLock.lock()
        defer { self.backingStoreLock.unlock() }

        let oldValue = value_
        value_ = newValue

        return oldValue!
    }

    /// Checks and re-throws an error.
    @discardableResult
    fileprivate func handleError(_ error: Error) throws -> PropertyType {
        assert(error is PropertyError,
               "Errors thrown from PropertyDelegate must be PropertyErrors, but got \(error)")

        if case PropertyError.invalidObject = error {
            log.debug("Marking property of type \(PropertyType.self) invalid: \(error)")
            self.notifier.notifyInvalid()
        }

        throw error
    }
}

/// A property that can be set. Writes happen asynchronously.
public class WriteableProperty<TypeSpec: PropertyTypeSpec>: Property<TypeSpec> {
    // Due to a Swift bug I have to override this.
    override init<Impl: PropertyDelegate, Notifier: PropertyNotifier>(
        _ delegate: Impl, notifier: Notifier
    ) where Impl.T == NonOptionalType {
        super.init(delegate, notifier: notifier)
    }

    /// The value of the property. Reading is instant and synchronous, but writing is asynchronous
    /// and the value will not be updated until the write is complete. Use `set` to retrieve a
    /// promise.
    public final override var value: PropertyType {
        get {
            return super.value
        }
        set {
            // Unwrap the value, if it's an optional.
            guard let value = TypeSpec.toOptionalType(newValue) else {
                log.warn("A property (of type \(PropertyType.self)) was set to nil; this has no "
                       + "effect.")
                return
            }
            set(value).always {}
        }
    }

    /// Sets the value of the property.
    /// - returns: A promise that resolves to the new actual value of the property.
    public final func set(_ newValue: NonOptionalType) -> Promise<PropertyType> {
        return Promise<Void>(value: ()).then(on: backgroundQueue) {
            () throws -> (PropertyType, PropertyType) in

            self.requestLock.lock()
            defer { self.requestLock.unlock() }

            // Write, then read back the value to see what actually changed.
            try self.delegate_.writeValue(newValue)
            do {
                let actual = try TypeSpec.toPropertyType(self.delegate_.readValue())
                let oldValue = self.updateBackingStore(actual)
                return (oldValue, actual)
            } catch let PropertyError.timeout(time) {
                log.warn("A readback timed out (in \(time) seconds) after successfully writing a "
                       + "property (of type \(PropertyType.self)). This can result in an "
                       + "inconsistent property state in Swindler where ChangedEvents are marked "
                       + "as external that are actually internal.")
                throw PropertyError.timeout(time: time)
            }
        }.then { (oldValue: PropertyType, actual: PropertyType) -> PropertyType in
            // Back on main thread.
            if !TypeSpec.equal(actual, oldValue) {
                self.notifier.notify?(false, oldValue, actual)
            }
            return actual
        }.recover { error in
            try self.handleError(error)
        }
    }
}

// Because Swift doesn't have generic protocols, we have to use these ugly thunks to simulate them.
// Hopefully this will be addressed in a future Swift release.

private struct PropertyDelegateThunk<TypeSpec: PropertyTypeSpec> {
    // Use non-optional type as base so we don't have a double optional, and preserve the Equatable
    // info.
    typealias PropertyType = TypeSpec.NonOptionalType

    init<Impl: PropertyDelegate>(_ impl: Impl) where Impl.T == PropertyType {
        writeValue_ = impl.writeValue
        readValue_ = impl.readValue
    }

    let writeValue_: (_ newValue: PropertyType) throws -> Void
    let readValue_: () throws -> PropertyType?

    func writeValue(_ newValue: PropertyType) throws { try writeValue_(newValue) }
    func readValue() throws -> PropertyType? { return try readValue_() }
}

private struct PropertyNotifierThunk<TypeSpec: PropertyTypeSpec> {
    typealias PropertyType = TypeSpec.PropertyType

    // Will be nil if not initialized with an event type.
    let notify: Optional<
        (_ external: Bool, _ oldValue: PropertyType, _ newValue: PropertyType) -> Void
    >
    let notifyInvalid: () -> Void

    init<Notifier: PropertyNotifier, Event: PropertyEventType, Object>(
        _ wrapped: Notifier, withEvent: Event.Type, receivingObject: Object.Type
    ) where Event.PropertyType == PropertyType, Notifier.Object == Object, Event.Object == Object {
        weak var wrappedNotifier = wrapped
        self.notifyInvalid = { wrappedNotifier?.notifyInvalid() }
        self.notify = { (external: Bool, oldValue: PropertyType, newValue: PropertyType) in
            wrappedNotifier?.notify(Event.self,
                                    external: external,
                                    oldValue: oldValue,
                                    newValue: newValue)
        }
    }

    init<Notifier: PropertyNotifier>(_ wrapped: Notifier) {
        weak var wrappedNotifier = wrapped
        self.notifyInvalid = { wrappedNotifier?.notifyInvalid() }
        self.notify = nil
    }
}
