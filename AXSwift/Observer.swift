/// Observers watch for events on an application's UI elements.
///
/// Events are received as part of the application's default run loop.
///
/// - seeAlso: `UIElement` for a list of exceptions that can be thrown.
public class Observer {
  public typealias Callback =
    (observer: Observer, element: UIElement, notification: Notification) -> Void
  public typealias CallbackWithInfo =
    (observer: Observer, element: UIElement, notification: Notification, info: [String: AnyObject]?) -> Void

  let axObserver: AXObserver!
  let callback: Callback?
  let callbackWithInfo: CallbackWithInfo?

  /// Creates and starts an observer on the given `processID`.
  public init(processID: pid_t, callback: Callback) throws {
    var axObserver: AXObserver?
    let error = AXObserverCreate(processID, internalCallback, &axObserver)

    self.axObserver       = axObserver
    self.callback         = callback
    self.callbackWithInfo = nil

    guard error == .Success else {
      throw error
    }
    assert(axObserver != nil)

    start()
  }

  /// Creates and starts an observer on the given `processID`.
  ///
  /// Use this initializer if you want the extra user info provided with notifications.
  /// - seeAlso: [UserInfo Keys for Posting Accessibility Notifications](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/UserInfo_Keys_for_Posting_Accessibility_Notifications)
  public init(processID: pid_t, callback: CallbackWithInfo) throws {
    var axObserver: AXObserver?
    let error = AXObserverCreateWithInfoCallback(processID, internalCallback, &axObserver)

    self.axObserver       = axObserver
    self.callback         = nil
    self.callbackWithInfo = callback

    guard error == .Success else {
      throw error
    }
    assert(axObserver != nil)

    start()
  }

  /// Starts watching for events. You don't need to call this method unless you use `stop()`.
  ///
  /// If the observer has already been started, this method does nothing.
  public func start() {
    CFRunLoopAddSource(
      NSRunLoop.currentRunLoop().getCFRunLoop(),
      AXObserverGetRunLoopSource(axObserver).takeUnretainedValue(),
      kCFRunLoopDefaultMode)
  }

  /// Stops sending events to your callback until the next call to `start`.
  ///
  /// If the observer has already been started, this method does nothing.
  ///
  /// - important: Events will still be queued in the target process until the Observer is started
  ///              again or destroyed. If you don't want them, create a new Observer.
  public func stop() {
    CFRunLoopRemoveSource(
      NSRunLoop.currentRunLoop().getCFRunLoop(),
      AXObserverGetRunLoopSource(axObserver).takeUnretainedValue(),
      kCFRunLoopDefaultMode)
  }

  /// Adds a notification for the observer to watch.
  ///
  /// - parameter element: The element to watch for the notification on. Must belong to the application
  ///                      this observer was created on.
  /// - parameter notification: The name of the notification to watch for.
  /// - seeAlso: [Notificatons](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/c/data/NSAccessibilityAnnouncementRequestedNotification)
  /// - note: The underlying API returns an error if the notification is already added, but that
  ///         error is not passed on for consistency with `start()` and `stop()`.
  /// - throws: `Error.NotificationUnsupported`: The element does not support notifications (note
  ///           that the system-wide element does not support notifications).
  public func addNotification(element: UIElement, notification: Notification) throws {
    let selfPtr = UnsafeMutablePointer<Observer>(Unmanaged.passUnretained(self).toOpaque())
    let error = AXObserverAddNotification(axObserver, element.element, notification.rawValue, selfPtr)
    guard error == .Success || error == .NotificationAlreadyRegistered else {
      throw error
    }
  }

  /// Removes a notification from the observer.
  ///
  /// - parameter element: The element to stop watching the notification on.
  /// - parameter notification: The name of the notification to stop watching.
  /// - note: The underlying API returns an error if the notification is not present, but that
  ///         error is not passed on for consistency with `start()` and `stop()`.
  /// - throws: `Error.NotificationUnsupported`: The element does not support notifications (note
  ///           that the system-wide element does not support notifications).
  public func removeNotification(element: UIElement, notification: Notification) throws {
    let error = AXObserverRemoveNotification(axObserver, element.element, notification.rawValue)
    guard error == .Success || error == .NotificationNotRegistered else {
      throw error
    }
  }
}

private func internalCallback(axObserver: AXObserver,
                              axElement: AXUIElement,
                              notification: CFString,
                              userData: UnsafeMutablePointer<Void>) {
  let observer = Unmanaged<Observer>.fromOpaque(COpaquePointer(userData)).takeUnretainedValue()
  let element  = UIElement(axElement)
  let notif    = Notification(rawValue: notification as String)!
  observer.callback!(observer: observer, element: element, notification: notif)
}

private func internalCallback(axObserver: AXObserver,
                              axElement: AXUIElement,
                              notification: CFString,
                              cfInfo: CFDictionary,
                              userData: UnsafeMutablePointer<Void>) {
  let observer = Unmanaged<Observer>.fromOpaque(COpaquePointer(userData)).takeUnretainedValue()
  let element  = UIElement(axElement)
  let info     = cfInfo as NSDictionary? as! [String: AnyObject]?
  let notif    = Notification(rawValue: notification as String)!
  observer.callbackWithInfo!(observer: observer, element: element, notification: notif, info: info)
}
