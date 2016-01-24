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

  var knownWindows: [WindowDelegate] { return [] }

  var mainWindow: WriteableProperty<OfOptionalType<Window>>!
  var focusedWindow: Property<OfOptionalType<Window>>!
  var isFrontmost: WriteableProperty<OfType<Bool>>!
  var isHidden: WriteableProperty<OfType<Bool>>!

  func equalTo(other: ApplicationDelegate) -> Bool { return false }
}
