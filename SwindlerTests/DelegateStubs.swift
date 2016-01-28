import PromiseKit
@testable import Swindler

class StubStateDelegate: StateDelegate {
  var runningApplications: [ApplicationDelegate] = []
  var frontmostApplication: WriteableProperty<OfOptionalType<Swindler.Application>>!
  var knownWindows: [WindowDelegate] = []
  var screens: [ScreenDelegate] = []
  func on<Event: EventType>(handler: (Event) -> ()) {}
}

class StubApplicationDelegate: ApplicationDelegate {
  var processID: pid_t!

  var stateDelegate: StateDelegate? = StubStateDelegate()

  var knownWindows: [WindowDelegate] = []

  var mainWindow: WriteableProperty<OfOptionalType<Window>>!
  var focusedWindow: Property<OfOptionalType<Window>>!
  var isFrontmost: WriteableProperty<OfType<Bool>>!
  var isHidden: WriteableProperty<OfType<Bool>>!

  func equalTo(other: ApplicationDelegate) -> Bool { return self === other }
}

class StubWindowDelegate: WindowDelegate {
  var isValid: Bool = true

  var appDelegate: ApplicationDelegate?

  var position: WriteableProperty<OfType<CGPoint>>!
  var size: WriteableProperty<OfType<CGSize>>!
  var title: Property<OfType<String>>!
  var isMinimized: WriteableProperty<OfType<Bool>>!
  var isFullscreen: WriteableProperty<OfType<Bool>>!

  let position_ = StubPropertyDelegate(value: CGPoint.zero)
  let size_ = StubPropertyDelegate(value: CGSize.zero)

  init() {
    let notifier = TestPropertyNotifier()

    position = WriteableProperty(position_, notifier: notifier)
    size = WriteableProperty(size_, notifier: notifier)
  }

  func equalTo(other: WindowDelegate) -> Bool { return self === other }
}

class StubScreenDelegate: ScreenDelegate {
  var frame: CGRect = CGRect.zero
  var applicationFrame: CGRect = CGRect.zero

  init() {}
  init(frame: CGRect) {
    self.frame = frame
    self.applicationFrame = frame
  }

  var debugDescription: String { return "StubScreenDelegate" }

  func equalTo(other: ScreenDelegate) -> Bool { return self === other }
}

class StubPropertyDelegate<T: Equatable>: PropertyDelegate {
  var value: T
  init(value: T) {
    self.value = value
  }

  let lock = NSLock()

  func readValue() throws -> T? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func writeValue(newValue: T) throws {
    lock.lock()
    defer { lock.unlock() }
    value = newValue
  }

  func initialize() -> Promise<T?> {
    return Promise(value)
  }
}
