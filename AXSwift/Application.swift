public class Application: UIElement {
  // Creates a UIElement for the given process ID.
  // Does NOT check if the given process actually exists, just checks for a valid ID.
  init?(forKnownProcessID processID: pid_t) {
    let appElement = AXUIElementCreateApplication(processID).takeRetainedValue()
    super.init(appElement)

    if (processID < 0) {
      return nil
    }
  }

  public convenience init?(_ app: NSRunningApplication) {
    if app.terminated {
      return nil
    }
    self.init(forKnownProcessID: app.processIdentifier)
  }

  public convenience init?(forProcessID processID: pid_t) {
    guard let app = NSRunningApplication(processIdentifier: processID) else {
      return nil
    }
    self.init(app)
  }

  public class func all(forBundleID bundleID: String) -> [Application] {
    let runningApps = NSWorkspace.sharedWorkspace().runningApplications
    return runningApps
      .filter({ $0.bundleIdentifier == bundleID })
      .flatMap({ Application($0) })
  }

  public func windows() throws -> [UIElement]? {
    let axWindows: [AXUIElement]? = try self.attribute("AXWindows")
    return axWindows?.map({ UIElement($0) })
  }

  public override func elementAtPosition(x: Float, _ y: Float) throws -> UIElement? {
    return try super.elementAtPosition(x, y)
  }
}