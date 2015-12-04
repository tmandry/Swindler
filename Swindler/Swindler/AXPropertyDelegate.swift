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
      return try axElement.attribute(attribute)
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
      try axElement.setAttribute(attribute, value: newValue)
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
func fetchAttributes<UIElement: UIElementType>(attributeNames: [Attribute], forElement axElement: UIElement, fulfill: ([Attribute: Any]) -> (), reject: (ErrorType) -> ()) {
  Promise<Void>().thenInBackground { () -> () in
    // Issue a request in the background.
    let attributes = try axElement.getMultipleAttributes(attributeNames)
    fulfill(attributes)
    }.recover { error -> () in
      // Rewrite errors as PropertyErrors.
      do {
        throw error
      } catch AXSwift.Error.CannotComplete {
        // If messaging timeout unspecified, we'll pass -1.
        let time = (UIElement.globalMessagingTimeout) != 0 ? UIElement.globalMessagingTimeout : -1.0
        throw PropertyError.Timeout(time: NSTimeInterval(time))
      } catch AXSwift.Error.IllegalArgument {
        throw PropertyError.InvalidObject(cause: AXSwift.Error.IllegalArgument)
      } catch AXSwift.Error.NotImplemented {
        throw PropertyError.InvalidObject(cause: AXSwift.Error.NotImplemented)
      } catch AXSwift.Error.InvalidUIElement {
        throw PropertyError.InvalidObject(cause: AXSwift.Error.InvalidUIElement)
      } catch {
        unexpectedError(error, onElement: axElement)
        throw PropertyError.InvalidObject(cause: error)
      }
    }.error { error in
      reject(error)
  }
}
