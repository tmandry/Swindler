import AXSwift
import PromiseKit

protocol PropertyNotifier: class {
  typealias Object

  /// Called when the property value has been updated.
  func notify<Event: PropertyEventTypeInternal where Event.Object == Object>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType)

  /// Called when the underlying object has become invalid.
  func notifyInvalid()
}

/// A PropertyDelegate is responsible for reading and writing property values to/from the OS.
///
/// - important: You must only throw PropertyErrors from your methods.
/// - note: Throw PropertyError.InvalidObject from any method, and `notifyInvalid()` will be called
///         on the WindowPropertyNotifier.
protocol PropertyDelegate {
  typealias T: Equatable

  /// Synchronously read the property value from the OS. May be called on a background thread.
  func readValue() throws -> T

  /// Synchronously write the property value to the OS. May be called on a background thread.
  func writeValue(newValue: T) throws

  /// Returns a promise of the property's initial value. It's the responsibility of whoever defines
  /// the property to ensure that the property is not accessed before this promise resolves.
  /// You can call `refresh()` on the property, however, as it will wait for this to resolve.
  func initialize() -> Promise<T>
}

public enum PropertyError: ErrorType {
  /// The value the property was set to is illegal.
  /// - note: In practice, applications often simply ignore illegal values.
  case IllegalValue

  /// The application did not respond to our request quickly enough.
  case Timeout(time: NSTimeInterval)

  /// The underlying object for the property has become invalid (e.g. the window has been destroyed).
  /// This is considered a permanent failure.
  case InvalidObject(cause: ErrorType)

  /// Some other, hopefully temporary, failure.
  case Failure(cause: ErrorType)
}

/// A property on a window. Property values are watched and cached in the background, so they are
/// always available to read.
///
/// - throws: Only `PropertyError` errors are given for rejected promises.
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

  init<Impl: PropertyDelegate, Notifier: PropertyNotifier where Impl.T == Type>(_ delegate: Impl, notifier: Notifier) {
    self.notifier = PropertyNotifierThunk<Type>(notifier)
    self.delegate = delegate
    self.delegate_ = PropertyDelegateThunk(delegate)

    let (initialized, fulfill, reject) = Promise<Void>.pendingPromise()
    self.initialized = initialized  // must be set before capturing `self` in a closure

    delegate.initialize().then { (value: Type) -> () in
      self.value_ = value
      fulfill()
    }.error { error in
      do {
        try self.handleError(error)
      } catch {
        reject(error)
      }
    }
  }

  /// Use this initializer if there is an event associated with the property.
  convenience init<Impl: PropertyDelegate, Notifier: PropertyNotifier, Event: PropertyEventTypeInternal, Object where Impl.T == Type, Event.PropertyType == Type, Event.Object == Object, Notifier.Object == Object>(_ delegate: Impl, withEvent: Event.Type, receivingObject: Object.Type, notifier: Notifier) {
    self.init(delegate, notifier: notifier)
    self.notifier = PropertyNotifierThunk<Type>(notifier, withEvent: Event.self, receivingObject: Object.self)
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
    // Allow queueing up a refresh before initialization is complete, which means "assume the value
    // you will be initialized with is going to be stale". This is useful if an event is received
    // before fully initializing.
    return self.initialized.then(on: backgroundQueue) { () -> (Type, Type) in
      self.requestLock.lock()
      defer { self.requestLock.unlock() }

      let actual = try self.delegate_.readValue()
      let oldValue = self.updateBackingStore(actual)

      return (oldValue, actual)
    }.then { (oldValue: Type, actual: Type) throws -> Type in
      // Back on main thread.
      if oldValue != actual {
        self.notifier.notify?(external: true, oldValue: oldValue, newValue: actual)
      }
      return actual
    }.recover { error in
      try self.handleError(error)
    }
  }

  /// Synchronously updates the backing store and returns the old value.
  private func updateBackingStore(newValue: Type) -> Type {
    self.backingStoreLock.lock()
    defer { self.backingStoreLock.unlock() }

    let oldValue = self.value_
    self.value_ = newValue

    return oldValue
  }

  /// Checks and re-throws an error.
  private func handleError(error: ErrorType) throws -> Type {
    assert(error is PropertyError,
      "Errors thrown from PropertyDelegate must be PropertyErrors, but got \(error)")

    if case PropertyError.InvalidObject = error {
      self.notifier.notifyInvalid()
    }

    throw error
  }
}

/// A property that can be set. Writes happen asynchronously.
public class WriteableProperty<Type: Equatable>: Property<Type> {
  // Due to a Swift bug I have to override this.
  override init<Impl: PropertyDelegate, Notifier: PropertyNotifier where Impl.T == Type>(_ delegate: Impl, notifier: Notifier) {
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
      do {
        let actual = try self.delegate_.readValue()
        let oldValue = self.updateBackingStore(actual)
        return (oldValue, actual)
      } catch PropertyError.Timeout(let time) {
        NSLog("A readback timed out (in \(time) seconds) after successfully writing a property (of " +
              "type \(Type.self)). This can result in an inconsistent property state in Swindler " +
              "where ChangedEvents are marked as external that are actually internal.")
        throw PropertyError.Timeout(time: time)
      }
    }.then { (oldValue: Type, actual: Type) -> Type in
      // Back on main thread.
      if actual != oldValue {
        self.notifier.notify?(external: false, oldValue: oldValue, newValue: actual)
      }
      return actual
    }.recover { error in
      try self.handleError(error)
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

private struct PropertyNotifierThunk<PropertyType: Equatable> {
  // Will be nil if not initialized with an event type.
  let notify: Optional<(external: Bool, oldValue: PropertyType, newValue: PropertyType) -> ()>
  let notifyInvalid: () -> ()

  init<Notifier: PropertyNotifier, Event: PropertyEventTypeInternal, Object where Event.PropertyType == PropertyType, Notifier.Object == Object, Event.Object == Object>(_ wrappedNotifier: Notifier, withEvent: Event.Type, receivingObject: Object.Type) {
    self.notifyInvalid = { wrappedNotifier.notifyInvalid() }
    self.notify = { (external: Bool, oldValue: PropertyType, newValue: PropertyType) in
      wrappedNotifier.notify(Event.self, external: external, oldValue: oldValue, newValue: newValue)
    }
  }

  init<Notifier: PropertyNotifier>(_ wrappedNotifier: Notifier) {
    self.notifyInvalid = { wrappedNotifier.notifyInvalid() }
    self.notify = nil
  }
}
