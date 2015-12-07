// This file defines protocols that wrap classes in AXSwift, so we can inject fakes while testing.
// If a method from AXSwift is needed, it can be added to the corresponding protocol.

import AXSwift

/// Protocol that wraps AXSwift.UIElement.
protocol UIElementType: Equatable {
  static var globalMessagingTimeout: Float { get }

  func pid() throws -> pid_t
  func attribute<T>(attribute: Attribute) throws -> T?
  func arrayAttribute<T>(attribute: Attribute) throws -> [T]?
  func setAttribute(attribute: Attribute, value: Any) throws
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any]

  var inspect: String { get }
}
extension AXSwift.UIElement: UIElementType { }

/// Protocol that wraps AXSwift.Observer.
protocol ObserverType {
  typealias UIElement: UIElementType

  init(processID: pid_t, callback: (observer: Self, element: UIElement, notification: AXSwift.Notification) -> ()) throws
  func addNotification(notification: AXSwift.Notification, forElement: UIElement) throws
}
extension AXSwift.Observer: ObserverType {
  typealias UIElement = AXSwift.UIElement
}

/// Protocol that wraps AXSwift.Application.
protocol ApplicationElementType: UIElementType {
  typealias UIElement: UIElementType

  static func all() -> [Self]

  // Until the Swift type system improves, I don't see a way around this.
  var toElement: UIElement { get }
}
extension AXSwift.Application: ApplicationElementType {
  typealias UIElement = AXSwift.UIElement
  var toElement: UIElement { return self }
}
