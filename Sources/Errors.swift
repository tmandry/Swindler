import AXSwift
import PromiseKit

enum OSXDriverError: Error {
    case missingAttribute(attribute: AXSwift.Attribute, onElement: Any)
    case unknownWindow(element: Any)
    case windowIgnored(element: Any)
    case runningApplicationNotFound(processID: pid_t)
    case screensNotAvailable
}

// Handle unexpected errors with detailed logging, and abort when in debug mode.
func unexpectedError(_ error: String, file: String = #file, line: Int = #line) {
    log.error("unexpected error: \(error) at \(file):\(line)")
    assertionFailure()
}

func unexpectedError<UIElement: UIElementType>(
    _ error: String, onElement element: UIElement, file: String = #file, line: Int = #line) {
    let application = ((try? NSRunningApplication(processIdentifier: element.pid())) as NSRunningApplication??)
    log.error("unexpected error: \(error) on element: \(element) of application: "
            + "\(String(describing: application)) at \(file):\(line)")
    assertionFailure()
}

func unexpectedError(_ error: Error, file: String = #file, line: Int = #line) {
    unexpectedError(String(describing: error), file: file, line: line)
}

func unexpectedError<UIElement: UIElementType>(
    _ error: Error, onElement element: UIElement, file: String = #file, line: Int = #line) {
    unexpectedError(String(describing: error), onElement: element, file: file, line: line)
}
