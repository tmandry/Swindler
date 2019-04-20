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

/// Specifies an error that occurred during a property read or write.
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

/// Internally used by Swindler. You should not use this directly.
/// :nodoc:
public protocol PropertyTypeSpec {
    associatedtype NonOptionalType: Equatable
    /// The property type, which might be the same as the base type, or Optional<NonOptionalType>.
    associatedtype PropertyType
    static func equal(_ lhs: PropertyType, _ rhs: PropertyType) -> Bool
    static func toPropertyType(_ from: NonOptionalType?) throws -> PropertyType
    static func toOptionalType(_ from: PropertyType) -> NonOptionalType?
}

/// Specifies that a `Property` has type `T`.
///
/// Internally used by Swindler. You should not use this directly.
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

/// Used to specify that a `Property` has the type `T?`.
///
/// Internally used by Swindler. You should not use this directly.
public struct OfOptionalType<T: Equatable>: PropertyTypeSpec {
    public typealias NonOptionalType = T
    public typealias PropertyType = T?
    public static func equal(_ lhs: T?, _ rhs: T?) -> Bool { return lhs == rhs }
    public static func toPropertyType(_ from: T?) throws -> T? { return from }
    public static func toOptionalType(_ from: T?) -> T? { return from }
}

/// A property on a Swindler object.
///
/// Property values are watched and cached in the background, so they are always available to read.
///
/// - throws: Only `PropertyError` errors are given for rejected promises.
public class Property<TypeSpec: PropertyTypeSpec> {
    public typealias PropertyType = TypeSpec.PropertyType
    public typealias NonOptionalType = TypeSpec.NonOptionalType
    public typealias OptionalType = TypeSpec.NonOptionalType?

    // The backing store
    fileprivate var value_: PropertyType!
    // Implementation of how to read and write the value
    var delegate_: PropertyDelegateThunk<TypeSpec>
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
    fileprivate(set) var initialized: Promise<Void>!
    // Property definer can access the delegate they provided here
    fileprivate(set) var delegate: Any

    init<Impl: PropertyDelegate, Notifier: PropertyNotifier>(
        _ delegate: Impl,
        notifier: Notifier
    ) where Impl.T == NonOptionalType {
        self.notifier = PropertyNotifierThunk(notifier)
        self.delegate = delegate
        delegate_ = PropertyDelegateThunk(delegate)

        self.initialized = initialize(delegate)
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

    func initialize<Impl: PropertyDelegate>(_ delegate: Impl) -> Promise<Void>
    where Impl.T == NonOptionalType {
        let (promise, seal) = Promise<Void>.pending()
        delegate.initialize().done { value in
            self.value_ = try TypeSpec.toPropertyType(value)
            seal.fulfill(())
        }.catch { error in
            self.handleError(error)
            seal.reject(error)
        }
        return promise
    }

    /// The value of the property.
    public var value: PropertyType {
        return getValue()
    }

    func getValue() -> PropertyType {
        backingStoreLock.lock()
        defer { backingStoreLock.unlock() }
        return value_
    }

    /// Forces the value of the property to refresh.
    ///
    /// You almost never need to call this yourself, because properties are watched and updated
    /// automatically.
    ///
    /// You might need this if, for example, you receive information via a side channel that a
    /// property has updated, and want to make sure you have the latest value before continuing.
    ///
    /// - throws: `PropertyError` (via Promise)
    @discardableResult
    public func refresh() -> Promise<PropertyType> {
        // Allow queueing up a refresh before initialization is complete, which means "assume the
        // value you will be initialized with is going to be stale". This is useful if an event is
        // received before fully initializing.
        return initialized.map(on: backgroundQueue) { () -> (PropertyType, PropertyType) in
            self.requestLock.lock()
            defer { self.requestLock.unlock() }

            let actual = try TypeSpec.toPropertyType(self.delegate_.readValue())
            let oldValue = self.updateBackingStore(actual)

            return (oldValue, actual)
        }.map { (oldValue, actual) -> PropertyType in
            // Back on main thread.
            if !TypeSpec.equal(oldValue, actual) {
                self.notifier.notify?(true, oldValue, actual)
            }
            return actual
        }.tap { result in
            if case .rejected(let error) = result {
                self.handleError(error)
            }
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

    /// Checks an error.
    fileprivate func handleError(_ error: Error) {
        assert(error is PropertyError,
               "Errors thrown from PropertyDelegate must be PropertyErrors, but got \(error)")

        if case PropertyError.invalidObject = error {
            log.debug("Marking property of type \(PropertyType.self) invalid: \(error)")
            self.notifier.notifyInvalid()
        }
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
    public override var value: PropertyType {
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
            set(value).catch { error in
                log.error("Error while writing to property (of type \(PropertyType.self)): "
                        + String(describing: error))
            }
        }
    }

    /// Sets the value of the property.
    ///
    /// - returns: A promise that resolves to the new _actual_ value of the property, once set.
    /// - throws: `PropertyError` (via Promise)
    public func set(_ newValue: NonOptionalType) -> Promise<PropertyType> {
        return mutateWith() {
            try self.delegate_.writeValue(newValue)
            return newValue
        }
    }

    final func mutateWith(f: @escaping () throws -> (NonOptionalType)) -> Promise<PropertyType> {
        return Promise<Void>.value(()).map(on: backgroundQueue) {
            () throws -> (PropertyType, PropertyType, PropertyType) in

            self.requestLock.lock()
            defer { self.requestLock.unlock() }

            // Write, then read back the value to see what actually changed.
            let newValue = try f()
            do {
                let actual = try TypeSpec.toPropertyType(self.delegate_.readValue())
                let oldValue = self.updateBackingStore(actual)
                let desired = try TypeSpec.toPropertyType(newValue)
                return (oldValue, desired, actual)
            } catch let PropertyError.timeout(time) {
                log.warn("A readback timed out (in \(time) seconds) after successfully writing a "
                       + "property (of type \(PropertyType.self)). This can result in an "
                       + "inconsistent property state in Swindler where ChangedEvents are marked "
                       + "as external that are actually internal.")
                throw PropertyError.timeout(time: time)
            }
        }.map { (oldValue: PropertyType, desired: PropertyType, actual: PropertyType)
                  -> PropertyType in
            // Back on main thread.
            if !TypeSpec.equal(actual, oldValue) {
                // If the new value is not the desired value, then _something_ external interfered.
                // That something could be the user, the application, or the operating system.
                // Therefore we mark the event as external.
                let external = !TypeSpec.equal(actual, desired)
                self.notifier.notify?(external, oldValue, actual)
            }
            return actual
        }.tap { result in
            if case .rejected(let error) = result {
                self.handleError(error)
            }
        }
    }
}

// Because Swift doesn't have generic protocols, we have to use these ugly thunks to simulate them.
// Hopefully this will be addressed in a future Swift release.

struct PropertyDelegateThunk<TypeSpec: PropertyTypeSpec> {
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
