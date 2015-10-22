import AXSwift

public var state: State = OSXState()

func dispatchAfter(delay: NSTimeInterval, block: dispatch_block_t) {
  let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC)))
  dispatch_after(time, dispatch_get_main_queue(), block)
}

class OSXState: State {
  var applications: [Application] = []
  var observers: [Observer] = []
  var windows: [OSXWindow] = []

  // TODO: fix strong ref cycle

  init() {
    let app = Application.allForBundleID("com.apple.finder").first!
    print("app attrs: \(try! app.attributes())")
    let observer = app.createObserver() { (observer, element, notification) in
      if notification == .WindowCreated {
        self.windows.append(try! OSXWindow(axElement: element, observer: observer))
      } else if let (index, target) = self.findWindowAndIndex(element) {
        if notification == .UIElementDestroyed {
          self.windows.removeAtIndex(index)
        }
        target.onEvent(observer, event: notification)
      } else {
        print("Event \(notification) on unknown element \(element)")
      }
    }!
    try! observer.addNotification(.WindowCreated,     forElement: app)
    try! observer.addNotification(.MainWindowChanged, forElement: app)
    observer.start()

    applications.append(app)
    observers.append(observer)
  }

  var visibleWindows: [Window] {
    get { return windows }
  }

  private func findWindowAndIndex(axElement: UIElement) -> (Int, OSXWindow)? {
    return self.windows.enumerate().filter({ $0.1.axElement == axElement }).first
  }
}

class OSXWindow: Window {
  let axElement: UIElement

  init(axElement: UIElement, observer: Observer) throws {
    self.axElement = axElement
    try loadAttributes()
    let attrs = try! axElement.attributes()
    print("new window, attrs: \(attrs)")
    print("- settable: \(attrs.filter({ try! axElement.attributeIsSettable($0) }))")

    do {
      try observer.addNotification(.UIElementDestroyed, forElement: axElement)
      try observer.addNotification(.Moved, forElement: axElement)
      try observer.addNotification(.Resized, forElement: axElement)
    } catch let error {
      NSLog("Error: Could not watch [\(axElement)]: \(error)")
    }

    dispatchAfter(4.0) {
      self.pos = CGPoint(x: 200, y: 200)
      self.size = CGSize(width: 30, height: 30)
    }
  }

  private func loadAttributes() throws {
    let attrNames: [AXSwift.Attribute] = [.Position, .Size]
    let attributes = try axElement.getMultipleAttributes(attrNames)

    guard attributes.count == attrNames.count else {
      NSLog("Could not get required attributes for window. Wanted: \(attrNames). Got: \(attributes.keys)")
      throw AXSwift.Error.InvalidUIElement  // TODO: make our own
    }

    pos_ = attributes[.Position]! as! CGPoint
    size_ = attributes[.Size]! as! CGSize
  }

  private func updateAttribute<T: Equatable>(attr: Attribute, _ axAttr: AXSwift.Attribute, inout _ store: T!) {
    do {
      let value: T = try axElement.attribute(axAttr)!
      updateAttributeWithValue(attr, &store, value)
    } catch {
      fatalError("unhandled error: \(error)")
    }
  }

  private func updateAttributeWithValue<T: Equatable>(attr: Attribute, inout _ store: T!, _ value: T) {
    if store != value {
      store = value
      print("\(attr) changed to \(value), cause: external")
    }
  }

  private func setAttribute<T: Equatable>(attr: Attribute, _ axAttr: AXSwift.Attribute, inout _ store: T!, _ newVal: T) {
    // TODO: check value asynchronously(?), deal with failure modes (set fails, get fails)
    do {
      try axElement.setAttribute(axAttr, value: newVal)
      // Ask for the new value to find out what actually resulted
      let actual: T = try axElement.attribute(axAttr)!
      if store != actual {
        store = actual
        print("\(attr) changed to \(actual), cause: internal (requested: \(newVal))")
      }
    } catch let error {
      fatalError("unhandled error: \(error)")
    }
  }

  func onEvent(observer: Observer, event: Notification) {
    print("\(axElement): \(event)")
    switch event {
    case .Moved:
      updateAttribute(.Pos, .Position, &pos_)
    case .Resized:
      updateAttribute(.Size, .Size, &size_)
    default:
      print("Unknown event on \(self): \(event)")
    }
  }

  enum Attribute {
    case Pos
    case Size
  }

  private var pos_: CGPoint!
  var pos: CGPoint {
    get { return pos_ }
    set { setAttribute(.Pos, .Position, &pos_, newValue) }
  }

  private var size_: CGSize!
  var size: CGSize {
    get { return size_ }
    set { setAttribute(.Size, .Size, &size_, newValue) }
  }
}
