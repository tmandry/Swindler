/// A singleton for the system-wide element.
public var systemWideElement = SystemWideElement()

/// A `UIElement` for the system-wide accessibility element, which can be used to retrieve global,
/// application-inspecific parameters like the currently focused element.
public class SystemWideElement: UIElement {
  private convenience init() {
    self.init(AXUIElementCreateSystemWide().takeRetainedValue())
  }

  /// Returns the element at the specified top-down coordinates, or nil if there is none.
  public override func elementAtPosition(x: Float, _ y: Float) throws -> UIElement? {
    return try super.elementAtPosition(x, y)
  }
}
