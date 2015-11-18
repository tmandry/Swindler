import AXSwift
import PromiseKit

protocol WindowPropertyNotifier: class {
  func notify<Event: WindowPropertyEventTypeInternal>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType)
  func notifyInvalid()
}

/// A PropertyDelegate is responsible for reading and writing property values to/from the OS.
protocol PropertyDelegate {
  typealias T: Equatable
  func writeValue(newValue: T) throws
  func readValue() throws -> T

  /// Returns a promise of the property's initial value. It's the responsibility of whoever defines
  /// the property to ensure that the property is not accessed before this promise resolves.
  /// We could make this optional and use `readValue()` otherwise.
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
  private var value_: Type!
  private var notifier: PropertyNotifierThunk<Type>
  private var delegate_: PropertyDelegateThunk<Type>

  private(set) var delegate: Any
  private(set) var initialized: Promise<Void>

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
  public var value: Type { return value_ }

  /// Forces the value of the property to refresh. Most properties are watched so you don't need to
  /// call this yourself.
  public func refresh() -> Promise<Type> {
    return Promise<Void>().thenInBackground {
      return try self.delegate_.readValue()
    }.then { (actual: Type) throws -> Type in
      if self.value_ != actual {
        let oldValue = self.value_
        self.value_ = actual
        self.notifier.notify?(external: true, oldValue: oldValue, newValue: self.value_)
      }
      return self.value_
    }.recover { (error: ErrorType) throws -> Type in
      do {
        throw error
      } catch PropertyError.Invalid(let wrappedError) {
        self.notifier.notifyInvalid()
        throw wrappedError
      }
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
    get { return value_ }
    set { set(newValue) }
  }

  /// Sets the value of the property.
  /// - returns: A promise that resolves to the new actual value of the property.
  public func set(newValue: Type) -> Promise<Type> {
    return Promise<Void>().thenInBackground { () throws -> Type in
      try self.delegate_.writeValue(newValue)
      return try self.delegate_.readValue()
    }.then { (actual: Type) -> Type in
      if actual != self.value_ {
        let oldValue = self.value_
        self.value_ = actual
        self.notifier.notify?(external: false, oldValue: oldValue, newValue: actual)
      }
      return actual
    }.recover { (error: ErrorType) throws -> Type in
      switch error {
      case PropertyError.Invalid(let wrappedError):
        self.notifier.notifyInvalid()
        throw wrappedError
      default:
        throw error
      }
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
