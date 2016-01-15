import AXSwift
import PromiseKit

/// Implements WindowDelegate using the AXUIElement API.
final class OSXWindowDelegate<
  UIElement: UIElementType, ApplicationElement: ApplicationElementType, Observer: ObserverType
  where Observer.UIElement == UIElement, ApplicationElement.UIElement == UIElement
>: WindowDelegate, PropertyNotifier {
  typealias Object = Window

  private weak var notifier: EventNotifier?
  private var initialized: Promise<Void>!

  let axElement: UIElement

  private(set) var isValid: Bool = true

  private var axProperties: [PropertyType]!
  private var watchedAxProperties: [AXSwift.Notification: [PropertyType]]!

  weak var appDelegate: ApplicationDelegate?

  var position: WriteableProperty<OfType<CGPoint>>!
  var size: WriteableProperty<OfType<CGSize>>!
  var title: Property<OfType<String>>!
  var isMinimized: WriteableProperty<OfType<Bool>>!
  var isFullscreen: WriteableProperty<OfType<Bool>>!

  private init(appDelegate: ApplicationDelegate, notifier: EventNotifier?, axElement: UIElement, observer: Observer) throws {
    self.appDelegate = appDelegate
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
    isFullscreen = WriteableProperty(AXPropertyDelegate(axElement, .FullScreen, initPromise),
      notifier: self)

    axProperties = [
      position,
      size,
      title,
      isMinimized,
      isFullscreen
    ]

    // Map notifications on this element to the corresponding property.
    watchedAxProperties = [
      .Moved:                 [position],
      .Resized:               [size, isFullscreen],
      .TitleChanged:          [title],
      .WindowMiniaturized:    [isMinimized],
      .WindowDeminiaturized:  [isMinimized]
    ]

    // Start watching for notifications.
    let notifications = watchedAxProperties.keys + [
      .UIElementDestroyed
    ]
    let watched = watchWindowElement(axElement, observer: observer, notifications: notifications)

    // Fetch attribute values.
    let attributes = axProperties.map({ ($0.delegate as! AXPropertyDelegateType).attribute }) + [
      .Subrole
    ]
    fetchAttributes(attributes, forElement: axElement, after: watched, fulfill: fulfill, reject: reject)

    // Ignore windows with the "AXUnknown" role. This (undocumented) role shows up in several places,
    // including Chrome tooltips and OS X fullscreen transitions.
    let subroleChecked = initPromise.then { attributeValues -> () in
      if attributeValues[.Subrole] as! String? == "AXUnknown" {
        log.debug("Window \(axElement) has subrole AXUnknown, unwatching")
        self.unwatchWindowElement(axElement, observer: observer, notifications: notifications)
        throw OSXDriverError.WindowIgnored(element: axElement)
      }
    }

    initialized =
      when(initializeProperties(axProperties, ofElement: axElement).asVoid(), subroleChecked)
      .recover(unwrapWhenErrors)
  }

  private func watchWindowElement(element: UIElement, observer: Observer, notifications: [Notification]) -> Promise<Void> {
    return Promise<Void>().thenInBackground { () -> () in
      for notification in notifications {
        try traceRequest(self.axElement, "addNotification", notification) {
          try observer.addNotification(notification, forElement: self.axElement)
        }
      }
    }
  }

  private func unwatchWindowElement(element: UIElement, observer: Observer, notifications: [Notification]) {
    Promise<Void>().thenInBackground { () -> () in
      for notification in notifications {
        try traceRequest(self.axElement, "removeNotification", notification) {
          try observer.removeNotification(notification, forElement: self.axElement)
        }
      }
    }
  }

  // Initializes the window and returns it as a Promise once it's ready.
  static func initialize(
      appDelegate appDelegate: ApplicationDelegate,
      notifier: EventNotifier?,
      axElement: UIElement,
      observer: Observer
  ) -> Promise<OSXWindowDelegate> {
    return firstly {  // capture thrown errors in promise
      let window = try OSXWindowDelegate(
          appDelegate: appDelegate, notifier: notifier, axElement: axElement, observer: observer)
      return window.initialized.then { return window }
    }
  }

  func handleEvent(event: AXSwift.Notification, observer: Observer) {
    switch event {
    case .UIElementDestroyed:
      isValid = false
    default:
      if let properties = watchedAxProperties[event] {
        properties.forEach{ $0.refresh() }
      } else {
        log.debug("Unknown event on \(self): \(event)")
      }
    }
  }

  func notify<Event: PropertyEventType where Event.Object == Window>(event: Event.Type, external: Bool, oldValue: Event.PropertyType, newValue: Event.PropertyType) {
    guard let window = Window(delegate: self) else {
      // Application terminated already; shouldn't send events.
      return
    }
    notifier?.notify(Event(external: external, object: window, oldValue: oldValue, newValue: newValue))
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
