import AXSwift
import PromiseKit

protocol WindowPropertyNotifier: class {
  /// Called when the property value has been updated.
  func notify<Event: WindowPropertyEventTypeInternal>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType)

  /// Called when the underlying object has become invalid.
  func notifyInvalid()
}

/// A PropertyDelegate is responsible for reading and writing property values to/from the OS.
protocol PropertyDelegate {
  typealias T: Equatable

  /// Synchronously read the property value from the OS. May be called on a background thread.
  func readValue() throws -> T

  /// Synchronously write the property value to the OS. May be called on a background thread.
  func writeValue(newValue: T) throws

  /// Returns a promise of the property's initial value. It's the responsibility of whoever defines
  /// the property to ensure that the property is not accessed before this promise resolves.
  func initialize() -> Promise<T>
}

/// If the underlying UI object becomes invalid, throw a PropertyError.Invalid which wraps a public
/// error type from your delegate. The unwrapped error will be presented to the user.
enum PropertyError: ErrorType {
  case Invalid(error: ErrorType)
}

/// A property on a window. Property values are watched and cached in the background, so they are
/// always available to read.
public class Property<Type: Equatable> {
  // The backing store
  private var value_: Type!
  // Implementation of how to read and write the value
  private var delegate_: PropertyDelegateThunk<Type>
  // Where events go
  private var notifier: PropertyNotifierThunk<Type>

  // Only do one request on a given property at a time. This ensures that events get emitted from
  // the right operation.
  private let requestLock = NSLock()
  // Since the backing store can be updated on another thread, we need to lock it.
  // This lock MUST NOT be held during a slow call. Only hold it as long as necessary.
  private let backingStoreLock = NSLock()

  // Exposed for testing only.
  var backgroundQueue: dispatch_queue_t = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

  // Property definer is responsible for ensuring that it is NOT used before this promise resolves.
  private(set) var initialized: Promise<Void>
  // Property definer can access the delegate they provided here
  private(set) var delegate: Any

  init<Impl: PropertyDelegate where Impl.T == Type>(_ delegate: Impl, notifier: WindowPropertyNotifier) {
    self.notifier = PropertyNotifierThunk<Type>(notifier)
    self.delegate = delegate
    self.delegate_ = PropertyDelegateThunk(delegate)

    let (initialized, fulfill, reject) = Promise<Void>.pendingPromise()
    self.initialized = initialized  // must be set before capturing `self` in a closure
    delegate.initialize().then { (value: Type) -> () in
      self.value_ = value
      fulfill()
    }.error { error in
      if case PropertyError.Invalid(let wrappedError) = error {
        reject(wrappedError)
      } else {
        reject(error)
      }
    }
  }

  /// Use this initializer if there is an event associated with the property.
  convenience init<Event: WindowPropertyEventTypeInternal, Impl: PropertyDelegate where Event.PropertyType == Type, Impl.T == Type>(_ delegate: Impl, withEvent: Event.Type, notifier: WindowPropertyNotifier) {
    self.init(delegate, notifier: notifier)
    self.notifier = PropertyNotifierThunk<Type>(notifier, withEvent: Event.self)
  }

  /// The value of the property.
  public var value: Type {
    backingStoreLock.lock()
    defer { backingStoreLock.unlock() }
    return value_
  }

  /// Forces the value of the property to refresh. Most properties are watched so you don't need to
  /// call this yourself.
  public func refresh() -> Promise<Type> {
    return Promise<Void>().then(on: backgroundQueue) { () -> (Type, Type) in
      self.requestLock.lock()
      defer { self.requestLock.unlock() }

      let actual = try self.delegate_.readValue()
      let oldValue = try self.updateBackingStore(actual)

      return (oldValue, actual)
    }.then { (oldValue: Type, actual: Type) throws -> Type in
      // Back on main thread.
      if oldValue != actual {
        self.notifier.notify?(external: true, oldValue: oldValue, newValue: actual)
      }
      return actual
    }.recover { error in
      try self.unwrapInvalidError(error)
    }
  }

  /// Synchronously updates the backing store and returns the old value.
  private func updateBackingStore(newValue: Type) throws -> Type {
    self.backingStoreLock.lock()
    defer { self.backingStoreLock.unlock() }

    let oldValue = self.value_
    self.value_ = newValue

    return oldValue
  }

  private func unwrapInvalidError(error: ErrorType) throws -> Type {
    do {
      throw error
    } catch PropertyError.Invalid(let wrappedError) {
      self.notifier.notifyInvalid()
      throw wrappedError
    }
  }
}

/// A property that can be set. Writes happen asynchronously.
public class WriteableProperty<Type: Equatable>: Property<Type> {
  // Due to a Swift bug I have to override this.
  override init<Impl: PropertyDelegate where Impl.T == Type>(_ delegate: Impl, notifier: WindowPropertyNotifier) {
    super.init(delegate, notifier: notifier)
  }

  /// The value of the property. Reading is instant and synchronous, but writing is asynchronous and
  /// the value will not be updated until the write is complete. Use `set` to retrieve a promise.
  override public var value: Type {
    get {
      backingStoreLock.lock()
      defer { backingStoreLock.unlock() }
      return value_
    }
    set {
      // `set` takes care of locking.
      set(newValue)
    }
  }

  /// Sets the value of the property.
  /// - returns: A promise that resolves to the new actual value of the property.
  public func set(newValue: Type) -> Promise<Type> {
    return Promise<Void>().then(on: backgroundQueue) { () throws -> (Type, Type) in
      self.requestLock.lock()
      defer { self.requestLock.unlock() }

      // Write, then read back the value to see what actually changed.
      try self.delegate_.writeValue(newValue)
      let actual = try self.delegate_.readValue()
      let oldValue = try self.updateBackingStore(actual)

      return (oldValue, actual)
    }.then { (oldValue: Type, actual: Type) -> Type in
      // Back on main thread.
      if actual != oldValue {
        self.notifier.notify?(external: false, oldValue: oldValue, newValue: actual)
      }
      return actual
    }.recover { error in
      try self.unwrapInvalidError(error)
    }
  }
}

// Because Swift doesn't have generic protocols, we have to use these ugly thunks to simulate them.
// Hopefully this will be addressed in a future Swift release.

private struct PropertyDelegateThunk<Type: Equatable>: PropertyDelegate {
  init<Impl: PropertyDelegate where Impl.T == Type>(_ impl: Impl) {
    writeValue_ = impl.writeValue
    readValue_ = impl.readValue
    initialize_ = impl.initialize
  }

  let writeValue_: (newValue: Type) throws -> ()
  let readValue_: () throws -> Type
  let initialize_: () -> Promise<Type>

  func writeValue(newValue: Type) throws { try writeValue_(newValue: newValue) }
  func readValue() throws -> Type { return try readValue_() }
  func initialize() -> Promise<Type> { return initialize_() }
}

class PropertyNotifierThunk<PropertyType: Equatable> {
  let wrappedNotifier: WindowPropertyNotifier
  // Will be nil if not initialized with an event type.
  let notify: Optional<(external: Bool, oldValue: PropertyType, newValue: PropertyType) -> ()>

  init<Event: WindowPropertyEventTypeInternal where Event.PropertyType == PropertyType>(_ wrappedNotifier: WindowPropertyNotifier, withEvent: Event.Type) {
    self.wrappedNotifier = wrappedNotifier
    self.notify = { (external: Bool, oldValue: PropertyType, newValue: PropertyType) in
      wrappedNotifier.notify(Event.self, external: external, oldValue: oldValue, newValue: newValue)
    }
  }

  init(_ wrappedNotifier: WindowPropertyNotifier) {
    self.wrappedNotifier = wrappedNotifier
    self.notify = nil
  }

  func notifyInvalid() {
    wrappedNotifier.notifyInvalid()
  }
}
