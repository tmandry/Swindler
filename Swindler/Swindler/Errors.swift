import AXSwift
import PromiseKit

enum OSXDriverError: ErrorType {
  case MissingAttribute(attribute: AXSwift.Attribute, onElement: UIElementType)
  case UnknownWindow(element: UIElementType)
}

func unwrapWhenErrors<T>(error: ErrorType) throws -> Promise<T> {
  switch error {
  case PromiseKit.Error.When(_, let wrappedError):
    throw wrappedError
  default:
    throw error
  }
}

// Handle unexpected errors with detailed logging, and abort when in debug mode.
func unexpectedError(error: String, file: String = __FILE__, line: Int = __LINE__) {
  print("unexpected error: \(error) at \(file):\(line)")
  assertionFailure()
}

func unexpectedError<UIElement: UIElementType>(
  error: String, onElement element: UIElement, file: String = __FILE__, line: Int = __LINE__) {
    let application = try? NSRunningApplication(processIdentifier: element.pid())
    print("unexpected error: \(error) on element: \(element) of application: \(application) at \(file):\(line)")
    assertionFailure()
}

func unexpectedError(error: ErrorType, file: String = __FILE__, line: Int = __LINE__) {
  unexpectedError(String(error), file: file, line: line)
}

func unexpectedError<UIElement: UIElementType>(
  error: ErrorType, onElement element: UIElement, file: String = __FILE__, line: Int = __LINE__) {
    unexpectedError(String(error), onElement: element, file: file, line: line)
}
