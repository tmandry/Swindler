import AXSwift
import PromiseKit

/// Implements WindowDelegate using the AXUIElement API.
class OSXWindowDelegate<
  UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
  where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: WindowDelegate, PropertyNotifier {
  typealias State = OSXStateDelegate<UIElement, ApplicationElement, Observer>
  typealias Object = Window
  let notifier: EventNotifier
  let axElement: UIElement

  private(set) var valid: Bool = true

  var pos: WriteableProperty<OfType<CGPoint>>!
  var size: WriteableProperty<OfType<CGSize>>!
  var title: Property<OfType<String>>!
  var minimized: WriteableProperty<OfType<Bool>>!
  var main: WriteableProperty<OfType<Bool>>!

  private var axProperties: [PropertyType]!
  private var watchedAxProperties: [AXSwift.Notification: PropertyType]!

  private init(notifier: EventNotifier, axElement: UIElement, observer: Observer) throws {
    // TODO: reject invalid roles (Chrome ghost windows)

    self.notifier = notifier
    self.axElement = axElement

    // Create a promise for the attribute dictionary we'll get from getMultipleAttributes.
    let (initPromise, fulfill, reject) = Promise<[AXSwift.Attribute: Any]>.pendingPromise()

    // Initialize all properties.
    pos = WriteableProperty(AXPropertyDelegate(axElement, .Position, initPromise),
      withEvent: WindowPosChangedEvent.self, receivingObject: Window.self, notifier: self)
    size = WriteableProperty(AXPropertyDelegate(axElement, .Size, initPromise),
      withEvent: WindowSizeChangedEvent.self, receivingObject: Window.self, notifier: self)
    title = Property(AXPropertyDelegate(axElement, .Title, initPromise),
      withEvent: WindowTitleChangedEvent.self, receivingObject: Window.self, notifier: self)
    minimized = WriteableProperty(AXPropertyDelegate(axElement, .Minimized, initPromise),
      withEvent: WindowMinimizedChangedEvent.self, receivingObject: Window.self, notifier: self)

    axProperties = [
      pos,
      size,
      title,
      minimized,
    ]

    // Map notifications on this element to the corresponding property.
    watchedAxProperties = [
      .Moved: pos,
      .Resized: size,
      .TitleChanged: title,
      .WindowMiniaturized: minimized,
      .WindowDeminiaturized: minimized
    ]

    // Start watching for notifications.
    for notification in watchedAxProperties.keys {
      try observer.addNotification(notification, forElement: axElement)
    }
    try observer.addNotification(.UIElementDestroyed, forElement: axElement)

    // Fetch attribute values.
    let attributes = axProperties.map({ ($0.delegate as! AXPropertyDelegateType).attribute })
    fetchAttributes(attributes, forElement: axElement, fulfill: fulfill, reject: reject)

    // Can't recover from an error during initialization.
    initPromise.error { error in
      self.notifyInvalid()
    }
  }

  // Initializes the window and returns it as a Promise once it's ready.
  static func initialize(notifier notifier: EventNotifier, axElement: UIElement, observer: Observer) -> Promise<OSXWindowDelegate> {
    return firstly {  // capture thrown errors in promise
      let window = try OSXWindowDelegate(notifier: notifier, axElement: axElement, observer: observer)

      let propertiesInitialized = Array(window.axProperties.map({ $0.initialized }))
      return when(propertiesInitialized).then { _ -> OSXWindowDelegate in
        return window
      }.recover { (error: ErrorType) -> OSXWindowDelegate in
        // Unwrap When errors
        switch error {
        case PromiseKit.Error.When(let index, let wrappedError):
          switch wrappedError {
          case PropertyError.MissingValue, PropertyError.InvalidObject(cause: PropertyError.MissingValue):
            // Add more information
            let propertyDelegate = window.axProperties[index].delegate as! AXPropertyDelegateType
            throw OSXDriverError.MissingAttribute(attribute: propertyDelegate.attribute, onElement: axElement)
          default:
            throw wrappedError
          }
        default:
          throw error
        }
      }
    }
  }

  func handleEvent(event: AXSwift.Notification, observer: Observer) {
    switch event {
    case .UIElementDestroyed:
      valid = false
    default:
      if let property = watchedAxProperties[event] {
        property.refresh()
      } else {
        print("Unknown event on \(self): \(event)")
      }
    }
  }

  func notify<Event: PropertyEventTypeInternal where Event.Object == Window>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    notifier.notify(Event(external: external, object: Window(delegate: self), oldVal: oldValue, newVal: newValue))
  }

  func notifyInvalid() {
    valid = false
  }

  func equalTo(rhs: WindowDelegate) -> Bool {
    if let other = rhs as? OSXWindowDelegate {
      return self.axElement == other.axElement
    } else {
      return false
    }
  }
}
