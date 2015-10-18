extension AXError : ErrorType { }

// For some reason values don't get described in this enum, so we have to do it manually.
extension AXError : CustomStringConvertible {
  private var valueAsString: String {
    switch (self) {
    case Success:
      return "Success"
    case Failure:
      return "Failure"
    case IllegalArgument:
      return "IllegalArgument"
    case InvalidUIElement:
      return "InvalidUIElement"
    case InvalidUIElementObserver:
      return "InvalidUIElementObserver"
    case CannotComplete:
      return "CannotComplete"
    case AttributeUnsupported:
      return "AttributeUnsupported"
    case ActionUnsupported:
      return "ActionUnsupported"
    case NotificationUnsupported:
      return "NotificationUnsupported"
    case NotImplemented:
      return "NotImplemented"
    case NotificationAlreadyRegistered:
      return "NotificationAlreadyRegistered"
    case NotificationNotRegistered:
      return "NotificationNotRegistered"
    case APIDisabled:
      return "APIDisabled"
    case NoValue:
      return "NoValue"
    case ParameterizedAttributeUnsupported:
      return "ParameterizedAttributeUnsupported"
    case NotEnoughPrecision:
      return "NotEnoughPrecision"
    }
  }

  public var description: String {
    return "AXError.\(valueAsString)"
  }
}

/// All possible errors that could be returned from UIElement or one of its subclasses.
///
/// These are just the errors that can be returned from the underlying API.
///
/// - seeAlso: [AXUIElement.h Reference](https://developer.apple.com/library/mac/documentation/ApplicationServices/Reference/AXUIElement_header_reference/)
/// - seeAlso: `UIElement` for a list of errors that you should handle
public typealias Error = AXError
