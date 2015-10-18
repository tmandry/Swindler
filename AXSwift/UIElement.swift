// Generic UI element which can hold and interact with any accessibility element.
public class UIElement {
  let element: AXUIElement

  init(_ nativeElement: AXUIElement) {
    // Since we are dealing with low-level C APIs, it never hurts to double check types.
    assert(CFGetTypeID(nativeElement) == AXUIElementGetTypeID(), "nativeElement is not an AXUIElement")

    element = nativeElement
  }

  public class func setGlobalMessagingTimeout(seconds: Float) throws {
    try SystemWideElement().setMessagingTimeout(seconds)
  }

  // MARK: - Attributes

  public func attributes() throws -> [String] {
    var names: CFArray?
    let error = AXUIElementCopyAttributeNames(element, &names)

    if error == .NoValue || error == .AttributeUnsupported {
      return []
    }

    guard error == .Success else {
      throw error
    }

    // We must first convert the CFArray to a native array, then downcast to an array of strings.
    return names! as [AnyObject] as! [String]
  }

  // The `attribute` method returns nil for unsupported attributes and empty attributes alike.
  // This is more convenient than dealing with exceptions (which are used for more serious errors).
  // However, if you'd like to see whether an attribute is actually supported, you can use this method.
  public func attributeIsSupported(name: String) throws -> Bool {
    // Ask to copy 0 values, since we are only interested in the return code.
    var value: CFArray?
    let error = AXUIElementCopyAttributeValues(element, name, 0, 0, &value)

    if error == .AttributeUnsupported {
      return false
    }

    if error == .NoValue {
      return true
    }

    guard error == .Success else {
      throw error
    }

    return true
  }

  public func attributeIsSettable(name: String) throws -> Bool {
    var settable: DarwinBoolean = false
    let error = AXUIElementIsAttributeSettable(element, name, &settable)

    if error == .NoValue || error == .AttributeUnsupported {
      return false
    }

    guard error == .Success else {
      throw error
    }

    return settable.boolValue
  }

  // Force-casts the attribute to the desired type. If you want to check the return type, ask for
  // AnyObject.
  public func attribute<T>(name: String) throws -> T? {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(element, name, &value)

    if error == .NoValue || error == .AttributeUnsupported {
      return nil
    }

    guard error == .Success else {
      throw error
    }

    return (value as! T)
  }

  // Throws if the named attribute doesn't exist.
  public func setAttribute(name: String, value: AnyObject) throws {
    let error = AXUIElementSetAttributeValue(element, name, value)

    guard error == .Success else {
      throw error
    }
  }


  // Gets multiple attributes of the element at once and returns them in a dictionary.
  // Presumably you would use this API for performance, though it's not documented that there is
  // actually a difference.
  // Missing values (or attributes) aren't included in the dictionary.
  // If there are any errors other than .NoValue or .AttributeUnsupported it will throw the first
  // one it encounters.
  public func getMultipleAttributes(names: [String]) throws -> [String: AnyObject] {
    var valuesCF: CFArray?
    let error = AXUIElementCopyMultipleAttributeValues(
      element,
      names,
      AXCopyMultipleAttributeOptions(rawValue: 0),  // keep going on errors (particularly NoValue)
      &valuesCF)

    guard error == .Success else {
      throw error
    }

    let values = valuesCF! as [AnyObject]

    // Pack names, values into dictionary
    var result = [String: AnyObject]()
    for (index, name) in names.enumerate() {
      if try checkMultiAttrValue(values[index]) {
        result[name] = values[index]
      }
    }
    return result
  }

  // Helper function: check if value is present and not an error (throws on nontrivial errors).
  private func checkMultiAttrValue(value: AnyObject) throws -> Bool {
    // Check for null
    if value is NSNull {
      return false
    }

    // Check for error
    if CFGetTypeID(value) == AXValueGetTypeID() &&
       AXValueGetType(value as! AXValue).rawValue == kAXValueAXErrorType {
      var error: AXError = AXError.Success;
      AXValueGetValue(value as! AXValue, AXValueType(rawValue: kAXValueAXErrorType)!, &error)

      assert(error != .Success)
      if error == .NoValue || error == .AttributeUnsupported {
        return false
      } else {
        throw error
      }
    }

    return true
  }

  // Convenience function that doesn't require passing an array.
  public func getMultipleAttributes(names: String...) throws -> [String: AnyObject] {
    return try getMultipleAttributes(names)
  }

  // MARK: Array attributes

  // Returns nil if the attribute doesn't exist or has no value.
  // Returns empty array if there are no elements starting at `index`.
  public func valuesForAttribute<T: AnyObject>
      (name: String, startAtIndex index: Int, maxValues: Int) throws -> [T]? {
    var values: CFArray?
    let error = AXUIElementCopyAttributeValues(element, name, index, maxValues, &values)

    if error == .NoValue || error == .AttributeUnsupported {
      return nil
    }

    guard error == .Success else {
      throw error
    }

    return (values! as [AnyObject] as! [T])
  }

  // Throws if the attribute doesn't exist (.AttributeUnsupported) or isn't an array (.IllegalArgument).
  public func valueCountForAttribute(name: String) throws -> Int {
    var count: Int = 0
    let error = AXUIElementGetAttributeValueCount(element, name, &count)

    guard error == .Success else {
      throw error
    }

    return count
  }

  // MARK: Parameterized attributes

  public func parameterizedAttributes() throws -> [String] {
    var names: CFArray?
    let error = AXUIElementCopyParameterizedAttributeNames(element, &names)

    if error == .NoValue || error == .AttributeUnsupported {
      return []
    }

    guard error == .Success else {
      throw error
    }

    // We must first convert the CFArray to a native array, then downcast to an array of strings.
    return names! as [AnyObject] as! [String]
  }

  public func parameterizedAttribute<T, U>(name: String, param: U) throws -> T? {
    var value: AnyObject?
    let error = AXUIElementCopyParameterizedAttributeValue(element, name, param as! AnyObject, &value)

    if error == .NoValue || error == .AttributeUnsupported {
      return nil
    }

    guard error == .Success else {
      throw error
    }

    return (value as! T)
  }

  // MARK: - Actions

  public func actions() throws -> [String] {
    var names: CFArray?
    let error = AXUIElementCopyActionNames(element, &names)

    if error == .NoValue || error == .AttributeUnsupported {
      return []
    }

    guard error == .Success else {
      throw error
    }

    // We must first convert the CFArray to a native array, then downcast to an array of strings.
    return names! as [AnyObject] as! [String]
  }

  public func actionDescription(action: String) throws -> String? {
    var description: CFString?
    let error = AXUIElementCopyActionDescription(element, action, &description)

    if error == .NoValue || error == .ActionUnsupported {
      return nil
    }

    guard error == .Success else {
      throw error
    }

    return description! as String
  }

  public func performAction(action: String) throws {
    let error = AXUIElementPerformAction(element, action)

    guard error == .Success else {
      throw error
    }
  }

  // MARK: -

  public func pid() throws -> pid_t {
    var pid: pid_t = -1
    let error = AXUIElementGetPid(element, &pid)

    guard error == .Success else {
      throw error
    }

    return pid
  }

  // Only applies to this instance of UIElement, not other instances that happen to equal it.
  // See also UIElement.setGlobalMessagingTimeout().
  public func setMessagingTimeout(seconds: Float) throws {
    let error = AXUIElementSetMessagingTimeout(element, seconds)

    guard error == .Success else {
      throw error
    }
  }

  // Gets the element at the specified coordinates.
  // This can only be called on applications and the system-wide element, so it is internal here.
  func elementAtPosition(x: Float, _ y: Float) throws -> UIElement? {
    var result: AXUIElement?
    let error = AXUIElementCopyElementAtPosition(element, x, y, &result)

    if error == .NoValue {
      return nil
    }

    guard error == .Success else {
      throw error
    }

    return UIElement(result!)
  }

  // TODO: docs
  // TODO: observers
  // TODO: convenience functions for attributes
}

// MARK: - CustomStringConvertible

extension UIElement: CustomStringConvertible {
  public var description: String {
    let role = (try? self.role()) ?? "UIElement"
    return "\(role): \(element)"
  }
}

// MARK: - Equatable

extension UIElement: Equatable { }
public func ==(lhs: UIElement, rhs: UIElement) -> Bool {
  return CFEqual(lhs.element, rhs.element)
}

// MARK: - Convenience getters

/// Convenience getters for UIElement
extension UIElement {
  // should this be non-optional?
  public func role() throws -> String? {
    return try self.attribute(NSAccessibilityRoleAttribute)
  }
}