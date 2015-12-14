import AXSwift
import PromiseKit

/// Implements WindowDelegate using the AXUIElement API.
class OSXWindowDelegate<
  UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
  where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: WindowDelegate, PropertyNotifier {
  typealias Object = Window

  private weak var notifier: EventNotifier?
  private var initialized: Promise<Void>!

  let axElement: UIElement

  private(set) var isValid: Bool = true

  var position: WriteableProperty<OfType<CGPoint>>!
  var size: WriteableProperty<OfType<CGSize>>!
  var title: Property<OfType<String>>!
  var isMinimized: WriteableProperty<OfType<Bool>>!
  var main: WriteableProperty<OfType<Bool>>!

  private var axProperties: [PropertyType]!
  private var watchedAxProperties: [AXSwift.Notification: PropertyType]!

  private init(notifier: EventNotifier?, axElement: UIElement, observer: Observer) throws {
    // TODO: reject invalid roles (Chrome ghost windows)

    self.notifier = notifier
    self.axElement = axElement

    // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
    let (initPromise, fulfill, reject) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()

    // Initialize all properties.
    position = WriteableProperty(AXPropertyDelegate(axElement, .Position, initPromise),
      withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: self)
    size = WriteableProperty(AXPropertyDelegate(axElement, .Size, initPromise),
      withEvent: WindowSizeChangedEvent.self, receivingObject: Window.self, notifier: self)
    title = Property(AXPropertyDelegate(axElement, .Title, initPromise),
      withEvent: WindowTitleChangedEvent.self, receivingObject: Window.self, notifier: self)
    isMinimized = WriteableProperty(AXPropertyDelegate(axElement, .Minimized, initPromise),
      withEvent: WindowMinimizedChangedEvent.self, receivingObject: Window.self, notifier: self)

    axProperties = [
      position,
      size,
      title,
      isMinimized,
    ]

    // Map notifications on this element to the corresponding property.
    watchedAxProperties = [
      .Moved: position,
      .Resized: size,
      .TitleChanged: title,
      .WindowMiniaturized: isMinimized,
      .WindowDeminiaturized: isMinimized
    ]

    // Start watching for notifications.
    let notifications = watchedAxProperties.keys + [
      .UIElementDestroyed
    ]
    let watched = watchWindowElement(axElement, observer: observer, notifications: notifications)

    // Fetch attribute values.
    let attributes = axProperties.map({ ($0.delegate as! AXPropertyDelegateType).attribute })
    fetchAttributes(attributes, forElement: axElement, after: watched, fulfill: fulfill, reject: reject)

    initialized = initializeProperties(axProperties, ofElement: axElement).asVoid()
  }

  func watchWindowElement(element: UIElement, observer: Observer, notifications: [Notification]) -> Promise<Void> {
    return Promise<Void>().thenInBackground { () -> () in
      for notification in notifications {
        try observer.addNotification(notification, forElement: self.axElement)
      }
    }
  }

  // Initializes the window and returns it as a Promise once it's ready.
  static func initialize(notifier notifier: EventNotifier?, axElement: UIElement, observer: Observer) -> Promise<OSXWindowDelegate> {
    return firstly {  // capture thrown errors in promise
      let window = try OSXWindowDelegate(notifier: notifier, axElement: axElement, observer: observer)
      return window.initialized.then { return window }
    }
  }

  func handleEvent(event: AXSwift.Notification, observer: Observer) {
    switch event {
    case .UIElementDestroyed:
      isValid = false
    default:
      if let property = watchedAxProperties[event] {
        property.refresh()
      } else {
        log.debug("Unknown event on \(self): \(event)")
      }
    }
  }

  func notify<Event: PropertyEventTypeInternal where Event.Object == Window>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notifier?.notify(Event(external: external, object: Window(delegate: self), oldValue: oldValue, newValue: newValue))
  }

  func notifyInvalid() {
    isValid = false
  }

  func equalTo(rhs: WindowDelegate) -> Bool {
    if let other = rhs as? OSXWindowDelegate {
      return self.axElement == other.axElement
    } else {
      return false
    }
  }
}
