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

public typealias Error = AXError