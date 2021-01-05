// This file defines protocols that wrap classes in AXSwift, so we can inject fakes while testing.
// If a method from AXSwift is needed, it can be added to the corresponding protocol.

import AXSwift

/// Protocol that wraps AXSwift.UIElement.
public protocol UIElementType: Equatable {
    static var globalMessagingTimeout: Float { get }

    func pid() throws -> pid_t
    func attribute<T>(_ attribute: Attribute) throws -> T?
    func arrayAttribute<T>(_ attribute: Attribute) throws -> [T]?
    func setAttribute(_ attribute: Attribute, value: Any) throws
    func getMultipleAttributes(_ attributes: [AXSwift.Attribute]) throws -> [Attribute: Any]

    var inspect: String { get }
}
extension AXSwift.UIElement: UIElementType {}

/// Protocol that wraps AXSwift.Observer.
public protocol ObserverType {
    associatedtype UIElement: UIElementType
    associatedtype Context

    typealias Callback = (Context, UIElement, AXSwift.AXNotification) -> Void

    init(processID: pid_t, callback: @escaping Callback) throws
    func addNotification(_ notification: AXSwift.AXNotification, forElement: UIElement) throws
    func removeNotification(_ notification: AXSwift.AXNotification, forElement: UIElement) throws
}
extension AXSwift.Observer: ObserverType {
    public typealias UIElement = AXSwift.UIElement
    public typealias Context = AXSwift.Observer
}

/// Protocol that wraps AXSwift.Application.
public protocol ApplicationElementType: UIElementType {
    associatedtype UIElement: UIElementType

    init?(forProcessID processID: pid_t)

    static func all() -> [Self]

    // Until the Swift type system improves, I don't see a way around this.
    var toElement: UIElement { get }
}
extension AXSwift.Application: ApplicationElementType {
    public typealias UIElement = AXSwift.UIElement
    public var toElement: UIElement { return self }
}
