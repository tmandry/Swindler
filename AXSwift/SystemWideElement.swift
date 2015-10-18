public class SystemWideElement: UIElement {
  public init() {
    super.init(AXUIElementCreateSystemWide().takeRetainedValue())
  }

  public override func elementAtPosition(x: Float, _ y: Float) throws -> UIElement? {
    return try super.elementAtPosition(x, y)
  }
}