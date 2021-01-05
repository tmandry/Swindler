import AXSwift
import PromiseKit

/// Implements PropertyDelegate using the AXUIElement API.
class AXPropertyDelegate<T: Equatable, UIElement: UIElementType>: PropertyDelegate {
    typealias InitDict = [AXSwift.Attribute: Any]
    public let axElement: UIElement
    let attribute: AXSwift.Attribute
    let initPromise: Promise<InitDict>

    init(_ axElement: UIElement, _ attribute: AXSwift.Attribute, _ initPromise: Promise<InitDict>) {
        self.axElement = axElement
        self.attribute = attribute
        self.initPromise = initPromise
    }

    func readFilter(_ value: T?) -> T? {
        return value
    }

    func readValue() throws -> T? {
        do {
            let value: T? = try traceRequest(axElement, "attribute", attribute) {
                try axElement.attribute(attribute)
            }
            return readFilter(value)
        } catch AXSwift.AXError.cannotComplete {
            // If messaging timeout unspecified, we'll pass -1.
            var time = UIElement.globalMessagingTimeout
            if time == 0 {
                time = -1.0
            }
            throw PropertyError.timeout(time: TimeInterval(time))
        } catch AXSwift.AXError.invalidUIElement {
            log.debug("Got invalidUIElement for element \(axElement) "
                    + "when attempting to read \(attribute)")
            throw PropertyError.invalidObject(cause: AXSwift.AXError.invalidUIElement)
        } catch let error {
            unexpectedError(error)
            throw PropertyError.invalidObject(cause: error)
        }
    }

    func writeValue(_ newValue: T) throws {
        do {
            return try traceRequest(axElement, "setAttribute", attribute, newValue) {
                try axElement.setAttribute(attribute, value: newValue)
            }
        } catch AXSwift.AXError.illegalArgument {
            throw PropertyError.illegalValue
        } catch AXSwift.AXError.cannotComplete {
            // If messaging timeout unspecified, we'll pass -1.
            var time = UIElement.globalMessagingTimeout
            if time == 0 {
                time = -1.0
            }
            throw PropertyError.timeout(time: TimeInterval(time))
        } catch AXSwift.AXError.failure {
            throw PropertyError.failure(cause: AXSwift.AXError.failure)
        } catch AXSwift.AXError.invalidUIElement {
            log.debug("Got invalidUIElement for element \(axElement) "
                    + "when attempting to write \(attribute)")
            throw PropertyError.invalidObject(cause: AXSwift.AXError.invalidUIElement)
        } catch let error {
            unexpectedError(error)
            throw PropertyError.invalidObject(cause: error)
        }
    }

    func initialize() -> Promise<T?> {
        return initPromise.map { dict in
            guard let value = dict[self.attribute] else {
                return nil
            }
            return self.readFilter(Optional(value as! T))
        }.recover { error -> Promise<T?> in
            switch error {
            case AXSwift.AXError.cannotComplete:
                // If messaging timeout unspecified, we'll pass -1.
                var time = UIElement.globalMessagingTimeout
                if time == 0 {
                    time = -1.0
                }
                throw PropertyError.timeout(time: TimeInterval(time))
            default:
                log.debug("Got error while initializing attribute \(self.attribute) "
                        + "for element \(self.axElement)")
                throw PropertyError.invalidObject(cause: error)
            }
        }
    }
}

// Non-generic protocols of generic types make it easy to store (or cast) objects.

protocol AXPropertyDelegateType {
    var attribute: AXSwift.Attribute { get }
}
extension AXPropertyDelegate: AXPropertyDelegateType {}

protocol PropertyType {
    func issueRefresh()
    var delegate: Any { get }
    var initialized: Promise<Void>! { get }
}
extension Property: PropertyType {
    func issueRefresh() {
        refresh()
    }
}

/// Asynchronously fetches all the element attributes.
func fetchAttributes<UIElement: UIElementType>(_ attributeNames: [Attribute],
                                               forElement axElement: UIElement,
                                               after: Promise<Void>,
                                               seal: Resolver<[Attribute: Any]>) {
    // Issue a request in the background.
    after.done(on: .global()) {
        let attributes = try traceRequest(axElement, "getMultipleAttributes", attributeNames) {
            try axElement.getMultipleAttributes(attributeNames)
        }
        seal.fulfill(attributes)
    }.catch { error in
        seal.reject(error)
    }
}

/// Returns a promise that resolves when all the provided properties are initialized.
/// Adds additional error information for AXPropertyDelegates.
func initializeProperties(_ properties: [PropertyType]) -> Promise<Void> {
    let propertiesInitialized: [Promise<Void>] = Array(properties.map({ $0.initialized }))
    return when(fulfilled: propertiesInitialized)
}

/// Tracks how long `requestFunc` takes, and logs it if needed.
/// - Parameter object: The object the request is being made on (usually, a UIElement).
func traceRequest<T>(
    _ object: Any,
    _ request: String,
    _ arg1: Any,
    _ arg2: Any? = nil,
    requestFunc: () throws -> T
) throws -> T {
    var result: T?
    var error: Error?

    let start = Date()
    do {
        result = try requestFunc()
    } catch let err {
        error = err
    }
    let end = Date()

    let elapsed = end.timeIntervalSince(start)
    log.trace({ () -> String in
        // This closure won't be evaluated if tracing is disabled.
        let formatElapsed = String(format: "%.1f", elapsed * 1000)
        let formatArgs = (arg2 == nil) ? "\(arg1)" : "\(arg1), \(arg2!)"
        let formatResult = (error == nil) ? "responded with \(result!)" : "failed with \(error!)"
        return "\(request)(\(formatArgs)) on \(object) \(formatResult) in \(formatElapsed)ms"
    }())
    // TODO: if more than some threshold, log as info

    if let error = error {
        throw error
    }
    return result!
}
