import AXSwift
import PromiseKit

/// Implements PropertyDelegate using the AXUIElement API.
class AXPropertyDelegate<T: Equatable, UIElement: UIElementType>: PropertyDelegate {
  typealias InitDict = [AXSwift.Attribute: Any]
  let axElement: UIElement
  let attribute: AXSwift.Attribute
  let initPromise: Promise<InitDict>

  init(_ axElement: UIElement, _ attribute: AXSwift.Attribute, _ initPromise: Promise<InitDict>) {
    self.axElement = axElement
    self.attribute = attribute
    self.initPromise = initPromise
  }

  func readValue() throws -> T? {
    do {
      return try traceRequest(axElement, "attribute", attribute) {
        try axElement.attribute(attribute)
      }
    } catch AXSwift.Error.CannotComplete {
      // If messaging timeout unspecified, we'll pass -1.
      let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
      throw PropertyError.Timeout(time: NSTimeInterval(time))
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement)
    } catch let error {
      unexpectedError(error)
      throw PropertyError.InvalidObject(cause: error)
    }
  }

  func writeValue(newValue: T) throws {
    do {
      return try traceRequest(axElement, "setAttribute", attribute, newValue) {
        try axElement.setAttribute(attribute, value: newValue)
      }
    } catch AXSwift.Error.IllegalArgument {
      throw PropertyError.IllegalValue
    } catch AXSwift.Error.CannotComplete {
      // If messaging timeout unspecified, we'll pass -1.
      let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
      throw PropertyError.Timeout(time: NSTimeInterval(time))
    } catch AXSwift.Error.Failure {
      throw PropertyError.Failure(cause: AXSwift.Error.Failure)
    } catch AXSwift.Error.InvalidUIElement {
      throw PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement)
    } catch let error {
      unexpectedError(error)
      throw PropertyError.InvalidObject(cause: error)
    }
  }

  func initialize() -> Promise<T?> {
    return initPromise.then { (dict: InitDict) throws -> T? in
      guard let value = dict[self.attribute] else {
        return nil
      }
      return (value as! T)
    }.recover { error -> T? in
      switch error {
      case AXSwift.Error.CannotComplete:
        // If messaging timeout unspecified, we'll pass -1.
        let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
        throw PropertyError.Timeout(time: NSTimeInterval(time))
      default:
        throw PropertyError.InvalidObject(cause: error)
      }
    }
  }
}

// Non-generic protocols of generic types make it easy to store (or cast) objects.

protocol AXPropertyDelegateType {
  var attribute: AXSwift.Attribute { get }
}
extension AXPropertyDelegate: AXPropertyDelegateType { }

protocol PropertyType {
  func refresh()
  var delegate: Any { get }
  var initialized: Promise<Void> { get }
}
extension Property: PropertyType {
  func refresh() {
    let _: Promise<Type> = self.refresh()
  }
}

/// Asynchronously fetches all the element attributes.
func fetchAttributes<UIElement: UIElementType>(attributeNames: [Attribute], forElement axElement: UIElement, after: Promise<Void>, fulfill: ([Attribute: Any]) -> (), reject: (ErrorType) -> ()) {
  // Issue a request in the background.
  after.thenInBackground { () -> () in
    let attributes = try traceRequest(axElement, "getMultipleAttributes", attributeNames) {
      try axElement.getMultipleAttributes(attributeNames)
    }
    fulfill(attributes)
  }.error { error in
    reject(error)
  }
}

/// Returns a promise that resolves when all the provided properties are initialized.
/// Adds additional error information for AXPropertyDelegates.
func initializeProperties<UIElement: UIElementType>(properties: [PropertyType], ofElement axElement: UIElement) -> Promise<Void> {
  let propertiesInitialized = Array(properties.map({ $0.initialized }))
  return when(propertiesInitialized).recover { (error: ErrorType) -> () in
    switch error {
    case PromiseKit.Error.When(let index, let wrappedError):
      switch wrappedError {
      case PropertyError.MissingValue, PropertyError.InvalidObject(cause: PropertyError.MissingValue):
        // Add more information
        if let propertyDelegate = properties[index].delegate as? AXPropertyDelegateType {
          throw OSXDriverError.MissingAttribute(attribute: propertyDelegate.attribute, onElement: axElement)
        } else {
          throw wrappedError
        }
      default:
        throw wrappedError
      }
    default:
      throw error
    }
  }
}

/// Tracks how long `requestFunc` takes, and logs it if needed.
/// - Parameter object: The object the request is being made on (usually, a UIElement).
func traceRequest<T>(
    object: Any,
  _ request: String,
  _ arg1: Any,
  _ arg2: Any? = nil,
  @noescape requestFunc: () throws -> T
) throws -> T {
  var result: T?
  var error: ErrorType?

  let start = NSDate()
  do {
    result = try requestFunc()
  } catch let err {
    error = err
  }
  let end = NSDate()

  let elapsed = end.timeIntervalSinceDate(start)
  log.trace({ () -> String in
    // This closure won't be evaluated if tracing is disabled.
    let formatElapsed = String(format: "%.1f", elapsed * 1000)
    let formatArgs    = (arg2 == nil) ? "\(arg1)" : "\(arg1), \(arg2!)"
    let formatResult  = (error == nil) ? "responded with \(result!)" : "failed with \(error!)"
    return "\(request)(\(formatArgs)) on \(object) \(formatResult) in \(formatElapsed)ms"
  }())
  // TODO: if more than some threshold, log as info

  if let error = error {
    throw error
  }
  return result!
}
