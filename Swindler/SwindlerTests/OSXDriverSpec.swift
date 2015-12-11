import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class OSXStateSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplicationElement.allApps = [] }
    beforeEach { FakeObserver.observers = [] }

    context("during initialization") {

      it("observes all applications") {
        class MyTestObserver: TestObserver {
          static var numObservers: Int = 0
          required init(processID: pid_t, callback: Callback) throws {
            MyTestObserver.numObservers++
            try super.init(processID: processID, callback: callback)
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement(), TestApplicationElement()]
        let _ = OSXStateDelegate<TestUIElement, TestApplicationElement, MyTestObserver>()

        expect(MyTestObserver.numObservers).to(equal(2), description: "should be 2 observers")
      }

      it("handles applications that cannot be watched") {
        class MyTestObserver: TestObserver {
          override private func addNotification(notification: AXSwift.Notification, forElement: TestUIElement) throws {
            throw AXSwift.Error.CannotComplete
          }
        }

        TestApplicationElement.allApps = [TestApplicationElement()]
        let _ = OSXStateDelegate<TestUIElement, TestApplicationElement, MyTestObserver>()
        // test that it doesn't crash
      }

    }

    context("after initialization") {
      // Set up a state with a single application containing a single window.
      var appElement: TestApplicationElement!
      var windowElement: TestWindowElement!
      var observer: FakeObserver!
      var state: State!
      beforeEach {
        appElement = TestApplicationElement()
        windowElement = TestWindowElement(forApp: appElement)
        windowElement.attrs[.Position] = CGPoint(x: 5, y: 5)
        appElement.attrs[.Windows] = [windowElement as TestUIElement]
        appElement.attrs[.MainWindow] = windowElement
        TestApplicationElement.allApps = [appElement]

        state = State(delegate: OSXStateDelegate<TestUIElement, TestApplicationElement, FakeObserver>())
        observer = FakeObserver.observers.first!
        observer.emit(.WindowCreated, forElement: windowElement)
        expect(state.knownWindows.count).toEventually(equal(1))
      }
      afterEach {
        TestApplicationElement.allApps = []
      }

      // Some of these are higher level versions of unit tests on their respective objects.

      context("when a window is created") {
        beforeEach {
          expect(state.knownWindows).toEventually(haveCount(1))
        }

        it("adds the window to knownWindows") {
          expect(state.knownWindows).to(haveCount(1))
        }

        it("emits WindowCreatedEvent") {
          var callbacks = 0
          state.on { (event: WindowCreatedEvent) in
            callbacks++
          }
          let window = TestWindowElement(forApp: appElement)
          observer.emit(.WindowCreated, forElement: window)
          expect(state.knownWindows).toEventually(haveCount(2))
          expect(callbacks).to(equal(1), description: "callback should be called once")
        }

      }

      context("when a window is destroyed") {

        it("emits WindowDestroyedEvent") {
          var callbacks = 0
          state.on { (event: WindowDestroyedEvent) in
            callbacks++
          }
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
        }

        it("removes the window from knownWindows") {
          observer.emit(.UIElementDestroyed, forElement: windowElement)
          expect(state.knownWindows).toEventually(haveCount(0))
        }

      }

      context("when a window property changes") {

        it("emits a ChangedEvent") {
          var callbacks = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks++
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks).toEventually(equal(1), description: "callback should be called once")
        }

        it("calls multiple event handlers") {
          var callbacks1 = 0
          var callbacks2 = 0
          state.on { (event: WindowPosChangedEvent) in
            callbacks1++
          }
          state.on { (event: WindowPosChangedEvent) in
            callbacks2++
          }
          windowElement.attrs[.Position] = CGPoint(x: 100, y: 100)
          observer.emit(.Moved, forElement: windowElement)
          expect(callbacks1).toEventually(equal(1), description: "callback1 should be called once")
          expect(callbacks2).toEventually(equal(1), description: "callback2 should be called once")
        }

      }

      describe("runningApplications") {
        context("on initialization") {
          it("contains the running applications") {
            expect(state.runningApplications).toEventually(haveCount(1))
          }
        }
      }

    }

  }
}

class TestNotifier: EventNotifier {
  var events: [EventType] = []
  func notify<Event: EventType>(event: Event) {
    events.append(event)
  }

  func getEventsOfType<T: EventType>(type: T.Type) -> [T] {
    return events.flatMap({ $0 as? T })
  }
  func getEventOfType<T: EventType>(type: T.Type) -> T? {
    return getEventsOfType(type).first
  }

  func expectEvent<T: EventType>(type: T.Type, file: String = __FILE__, line: UInt = __LINE__) -> T? {
    expect(self.getEventOfType(type), file: file, line: line).toEventuallyNot(beNil(), description: "expected event of type \(type)")
    return self.getEventOfType(type)
  }

  func waitUntilEvent<T: EventType>(type: T.Type, file: String = __FILE__, line: UInt = __LINE__) -> T? {
    var event: T?
    func getEvent() -> Bool {
      event = getEventOfType(type)
      return (event != nil)
    }
    waitUntil(getEvent(), file: file, line: line)
    return event
  }
}

/// Performs the given action on the main thread, synchronously, regardless of the current thread.
func performOnMainThread(action: () -> ()) {
  if NSThread.currentThread().isMainThread {
    action()
  } else {
    dispatch_sync(dispatch_get_main_queue()) {
      action()
    }
  }
}

/// Allows defining adversarial actions when a property is observed.
class AdversaryObserver: FakeObserver {
  static var onNotification: Notification? = nil
  static var handler: Optional<(AdversaryObserver) -> ()> = nil

  /// Call this in beforeEach for any tests that use this class.
  static func reset() {
    onNotification = nil
    handler = nil
  }

  /// Defines code that runs on the main thread before returning from addNotification.
  static func onAddNotification(notification: Notification, handler: (AdversaryObserver) -> ()) {
    onNotification = notification
    self.handler = handler
  }

  override func addNotification(
      notification: AXSwift.Notification, forElement element: TestUIElement) throws {
    try super.addNotification(notification, forElement: element)
    if notification == AdversaryObserver.onNotification {
      performOnMainThread { AdversaryObserver.handler!(self) }
    }
  }
}

/// Allows defining adversarial actions when an attribute is read.
final class AdversaryApplicationElement: TestApplicationElementBase, ApplicationElementType {
  static var allApps: [AdversaryApplicationElement] = []
  static func all() -> [AdversaryApplicationElement] { return AdversaryApplicationElement.allApps }

  var onRead: Optional<(AdversaryApplicationElement) -> ()> = nil
  var watchAttribute: Attribute? = nil
  var alreadyCalled = false

  /// Defines code that runs on the main thread before returning the value of the attribute.
  func onFirstAttributeRead(attribute: Attribute, handler: (AdversaryApplicationElement) -> ()) {
    watchAttribute = attribute
    onRead = handler
    alreadyCalled = false
  }

  override func attribute<T>(attribute: Attribute) throws -> T? {
    let result: T? = try super.attribute(attribute)
    if attribute == watchAttribute && !alreadyCalled {
      performOnMainThread {
        if !self.alreadyCalled {
          self.onRead?(self)
          self.alreadyCalled = true
        }
      }
    }
    return result
  }
  override func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute : Any] {
    let result: [Attribute : Any] = try super.getMultipleAttributes(attributes)
    if let watchAttribute = watchAttribute where attributes.contains(watchAttribute) {
      performOnMainThread {
        if !self.alreadyCalled {
          self.onRead?(self)
          self.alreadyCalled = true
        }
      }
    }
    return result
  }
}

class OSXApplicationDelegateInitSpec: QuickSpec {
  override func spec() {

    var notifier: TestNotifier!
    beforeEach {
      notifier = TestNotifier()
    }

    describe("initialize") {
      var appElement: TestApplicationElement!
      beforeEach {
        appElement = TestApplicationElement()
      }

      context("when the application UIElement is invalid") {
        it("resolves to an error") { () -> Promise<Void> in
          appElement.throwInvalid = true
          let promise = OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>.initialize(
            axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the application is missing the Windows attribute") {
        it("resolves to an error") { () -> Promise<Void> in
          appElement.attrs[.Windows] = nil
          let promise = OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>.initialize(
            axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the application is missing a required property attribute") {
        it("resolves to an error") { () -> Promise<Void> in
          appElement.attrs[.Frontmost] = nil
          let promise = OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>.initialize(
            axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the application is missing an optional property attribute") {
        it("succeeds") { () -> Promise<Void> in
          appElement.attrs[.MainWindow] = nil
          let promise = OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>.initialize(
            axElement: appElement, notifier: notifier)
          return expectToSucceed(promise)
        }
      }

      context("when the observer throws an error during initialization") {
        class ThrowingInitObserver: FakeObserver {
          required init(processID: pid_t, callback: Callback) throws {
            try super.init(processID: processID, callback: callback)
            throw AXSwift.Error.Failure
          }
        }

        it("resolves to an error") { () -> Promise<Void> in
          let promise = OSXApplicationDelegate<TestUIElement, TestApplicationElement, ThrowingInitObserver>.initialize(
            axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the observer throws an error during adding notifications") {
        class ThrowingAddObserver: FakeObserver {
          override func addNotification(notification: AXSwift.Notification, forElement element: TestUIElement) throws {
            throw AXSwift.Error.Failure
          }
        }

        it("resolves to an error") { () -> Promise<Void> in
          let promise = OSXApplicationDelegate<TestUIElement, TestApplicationElement, ThrowingAddObserver>.initialize(
            axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

    }

    describe("AXUIElement notifications") {
      var appElement: AdversaryApplicationElement!
      beforeEach {
        appElement = AdversaryApplicationElement()
      }
      beforeEach { AdversaryObserver.reset() }

      typealias AppDelegate = OSXApplicationDelegate<TestUIElement, AdversaryApplicationElement, AdversaryObserver>
      func initializeApp() -> Promise<AppDelegate> {
        return AppDelegate.initialize(axElement: appElement, notifier: notifier)
      }

      context("when a property value changes right before observing it") {

        context("for a regular property") {
          it("is read correctly") { () -> Promise<Void> in
            appElement.attrs[.Frontmost] = false

            AdversaryObserver.onAddNotification(.ApplicationActivated) { _ in
              appElement.attrs[.Frontmost] = true
            }

            return initializeApp().then { appDelegate -> () in
              let app = Swindler.Application(delegate: appDelegate)
              expect(app.frontmost.value).toEventually(beTrue())
            }
          }
        }

        context("for an object property") {
          it("is read correctly") {
            let windowElement = TestWindowElement(forApp: appElement)
            appElement.windows.append(windowElement)
            windowElement.attrs[.Main]    = false
            appElement.attrs[.MainWindow] = nil

            AdversaryObserver.onAddNotification(.MainWindowChanged) { observer in
              windowElement.attrs[.Main]    = true
              appElement.attrs[.MainWindow] = windowElement
            }

            // There's a problem with intermittent failures when wrapping an eventually expectation
            // inside waitUntil, so we have to do this. Currently only affects object properties.
            var app: Swindler.Application!
            waitUntil { done in initializeApp().then { appDelegate -> () in
              app = Swindler.Application(delegate: appDelegate)
              done()
            } }
            expect(app.mainWindow.value).toEventuallyNot(beNil())
          }
        }

      }

      context("when a property value changes right after observing it") {
        // The difference between a property changing before or after observing is simply whether
        // an event is emitted or not.

        context("for a regular property") {
          it("is updated correctly") { () -> Promise<Void> in
            appElement.attrs[.Frontmost] = false

            AdversaryObserver.onAddNotification(.ApplicationActivated) { observer in
              appElement.attrs[.Frontmost] = true
              observer.emit(.ApplicationActivated, forElement: appElement)
            }

            return initializeApp().then { appDelegate -> () in
              let app = Swindler.Application(delegate: appDelegate)
              expect(app.frontmost.value).toEventually(beTrue())
            }
          }
        }

        context("for an object property") {
          it("is updated correctly") {
            let windowElement = TestWindowElement(forApp: appElement)
            appElement.windows.append(windowElement)
            windowElement.attrs[.Main]    = false
            appElement.attrs[.MainWindow] = nil

            AdversaryObserver.onAddNotification(.MainWindowChanged) { observer in
              windowElement.attrs[.Main]    = true
              appElement.attrs[.MainWindow] = windowElement
              observer.emit(.MainWindowChanged, forElement: windowElement)
            }

            var app: Swindler.Application!
            waitUntil { done in initializeApp().then { appDelegate -> () in
              app = Swindler.Application(delegate: appDelegate)
              done()
            } }
            expect(app.mainWindow.value).toEventuallyNot(beNil())
          }
        }

      }

      context("when a property value changes right after reading it") {

        context("for a regular property") {
          it("is updated correctly") { () -> Promise<Void> in
            appElement.attrs[.Frontmost] = false

            var observer: AdversaryObserver?
            AdversaryObserver.onAddNotification(.ApplicationActivated) { obs in
              observer = obs
            }
            appElement.onFirstAttributeRead(.Frontmost) { _ in
              appElement.attrs[.Frontmost] = true
              observer?.emit(.ApplicationActivated, forElement: appElement)
            }

            return initializeApp().then { appDelegate -> () in
              let app = Swindler.Application(delegate: appDelegate)
              expect(app.frontmost.value).toEventually(beTrue())
            }
          }
        }

        context("for an object property") {
          it("is updated correctly") {
            let windowElement = TestWindowElement(forApp: appElement)
            appElement.windows.append(windowElement)
            windowElement.attrs[.Main]    = false
            appElement.attrs[.MainWindow] = nil

            var observer: AdversaryObserver?
            AdversaryObserver.onAddNotification(.MainWindowChanged) { obs in
              observer = obs
            }
            appElement.onFirstAttributeRead(.MainWindow) { _ in
              windowElement.attrs[.Main]    = true
              appElement.attrs[.MainWindow] = windowElement
              observer?.emit(.MainWindowChanged, forElement: appElement)
            }

            var app: Swindler.Application!
            waitUntil { done in initializeApp().then { appDelegate -> () in
              app = Swindler.Application(delegate: appDelegate)
              done()
            } }
            expect(app.mainWindow.value).toEventuallyNot(beNil())
          }
        }

      }
    }

  }
}

class OSXApplicationDelegateSpec: QuickSpec {
  override func spec() {

    var app: Swindler.Application!
    var appDelegate: OSXApplicationDelegate<TestUIElement, AdversaryApplicationElement, FakeObserver>!
    var appElement: AdversaryApplicationElement!
    var notifier: TestNotifier!
    var observer: FakeObserver!

    func initializeApp() {
      waitUntil { done in
        OSXApplicationDelegate<TestUIElement, AdversaryApplicationElement, FakeObserver>.initialize(
          axElement: appElement, notifier: notifier).then { applicationDelegate -> () in
            appDelegate = applicationDelegate
            observer = appDelegate.observer
            app = Swindler.Application(delegate: appDelegate)
            done()
        }
      }
    }

    beforeEach {
      notifier = TestNotifier()
      appElement = AdversaryApplicationElement()
      initializeApp()
    }

    func createWindow(emitEvent emitEvent: Bool = true) -> TestWindowElement {
      let windowElement = TestWindowElement(forApp: appElement)
      appElement.windows.append(windowElement)
      if emitEvent { observer.emit(.WindowCreated, forElement: windowElement) }
      return windowElement
    }

    func getWindowElement(window: Window?) -> TestUIElement? {
      typealias WinDelegate = OSXWindowDelegate<TestUIElement, AdversaryApplicationElement, FakeObserver>
      return ((window?.delegate) as! WinDelegate?)?.axElement
    }

    describe("knownWindows") {
      func getWindowElements(windows: [Window]) -> [TestUIElement] {
        return windows.map({ getWindowElement($0)! })
      }

      context("right after initialization") {

        context("when there are no windows") {
          it("is empty") {
            expect(app.knownWindows).to(beEmpty())
          }
        }

        context("when there are multiple windows") {
          it("contains all windows") {
            let windowElement1 = createWindow(emitEvent: false)
            let windowElement2 = createWindow(emitEvent: false)
            initializeApp()

            expect(getWindowElements(app.knownWindows)).to(contain(windowElement1, windowElement2))
          }
        }

        context("when one window is invalid") {
          it("contains only the valid windows") {
            let validWindowElement   = createWindow(emitEvent: false)
            let invalidWindowElement = createWindow(emitEvent: false)
            invalidWindowElement.throwInvalid = true
            initializeApp()

            expect(getWindowElements(app.knownWindows)).to(contain(validWindowElement))
            expect(getWindowElements(app.knownWindows)).toNot(contain(invalidWindowElement))
          }
        }

      }

      context("when a new window is created") {

        it("adds the window") {
          let windowElement = createWindow()
          expect(getWindowElements(app.knownWindows)).toEventually(contain(windowElement))
        }

        it("does not remove other windows") {
          let windowElement1 = createWindow(emitEvent: false)
          initializeApp()
          let windowElement2 = createWindow()

          waitUntil(getWindowElements(app.knownWindows).contains(windowElement2))
          expect(getWindowElements(app.knownWindows)).to(contain(windowElement1))
        }

      }

      context("when a window is destroyed") {

        it("removes the window") {
          let windowElement = createWindow(emitEvent: false)
          initializeApp()
          observer.emit(.UIElementDestroyed, forElement: windowElement)

          expect(getWindowElements(app.knownWindows)).toEventuallyNot(contain(windowElement))
        }

        it("does not remove other windows") {
          let windowElement1 = createWindow(emitEvent: false)
          let windowElement2 = createWindow(emitEvent: false)
          initializeApp()
          observer.emit(.UIElementDestroyed, forElement: windowElement1)

          waitUntil(!getWindowElements(app.knownWindows).contains(windowElement1))
          expect(getWindowElements(app.knownWindows)).to(contain(windowElement2))
        }

      }
    }

    // mainWindow is quite a bit more complicated than other properties, so we explicitly test it
    // here.
    describe("mainWindow") {

      context("when there is no initial main window") {
        it("initially equals nil") {
          expect(appElement.attrs[.MainWindow]).to(beNil())
          expect(app.mainWindow.value).to(beNil())
        }
      }

      context("when there is an initial main window") {
        it("equals the main window") {
          let windowElement = createWindow(emitEvent: false)
          windowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow] = windowElement
          initializeApp()

          expect(getWindowElement(app.mainWindow.value)).to(equal(windowElement))
        }
      }

      context("when a window becomes main") {
        var windowElement: TestWindowElement!
        beforeEach {
          windowElement = createWindow()
          windowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow] = windowElement
          observer.emit(.MainWindowChanged, forElement: windowElement)
        }

        it("updates the value") {
          expect(getWindowElement(app.mainWindow.value)).toEventually(equal(windowElement))
        }

        it("emits an ApplicationMainWindowChangedEvent with correct values") {
          if let event = notifier.expectEvent(ApplicationMainWindowChangedEvent.self) {
            // expect(event.application).to(equal(app))
            expect(event.external).to(beTrue())
            expect(event.oldVal).to(beNil())
            expect(getWindowElement(event.newVal)).to(equal(windowElement))
          }
        }

        // TODO: timeout on reading .Role
      }

      context("when a new window becomes the main window") {
        it("updates the value") {
          let windowElement = createWindow(emitEvent: false)
          windowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow] = windowElement

          // Usually we get the MWC notification before WindowCreated. Simply doing dispatch_async
          // to wait for WindowCreated doesn't always work, so we defeat that here.
          observer.emit(.MainWindowChanged, forElement: windowElement)
          dispatch_async(dispatch_get_main_queue()) {
            dispatch_async(dispatch_get_main_queue()) {
              observer.emit(.WindowCreated, forElement: windowElement)
            }
          }

          expect(getWindowElement(app.mainWindow.value)).toEventually(equal(windowElement))
        }
      }

      context("when the application switches to having no main window") {
        var mainWindowElement: TestWindowElement!
        beforeEach {
          mainWindowElement = createWindow()
          mainWindowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow] = mainWindowElement
          initializeApp()
        }

        it("becomes nil") {
          appElement.attrs[.MainWindow] = nil
          observer.emit(.MainWindowChanged, forElement: appElement)
          expect(app.mainWindow.value).toEventually(beNil())
        }

        context("because the main window closes") {
          it("becomes nil") {
            // TODO: what if it's just destroyed?
            appElement.attrs[.MainWindow] = nil
            observer.emit(.UIElementDestroyed, forElement: mainWindowElement)
            observer.emit(.MainWindowChanged, forElement: appElement)
            expect(app.mainWindow.value).toEventually(beNil())
          }
        }

        context("and the passed application element doesn't equal our stored application element") {
          // Because shit happens. Finder does this.
          it("becomes nil") {
            let otherAppElement = TestUIElement()
            otherAppElement.processID = appElement.processID
            otherAppElement.attrs = appElement.attrs
            assert(appElement != otherAppElement)

            appElement.attrs[.MainWindow] = nil
            observer.doEmit(.MainWindowChanged, watchedElement: appElement, passedElement: otherAppElement)
            expect(app.mainWindow.value).toEventually(beNil())
          }
        }

        // TODO: timeout on reading .Role
      }

      context("when a new window becomes main then closes before reading the attribute") {
        it("updates the value correctly") {
          let lastingWindowElement      = createWindow(emitEvent: false)
          appElement.attrs[.MainWindow] = nil
          initializeApp()

          let closingWindowElement = createWindow(emitEvent: false)
          closingWindowElement.throwInvalid = true

          appElement.windows = appElement.windows.filter({ $0 != closingWindowElement })
          appElement.attrs[.MainWindow]     = lastingWindowElement
          lastingWindowElement.attrs[.Main] = true

          observer.emit(.MainWindowChanged, forElement: closingWindowElement)
          observer.emit(.WindowCreated, forElement: closingWindowElement)
          observer.emit(.UIElementDestroyed, forElement: closingWindowElement)
          observer.emit(.MainWindowChanged, forElement: lastingWindowElement)

          expect(getWindowElement(app.mainWindow.value)).toEventually(equal(lastingWindowElement))

          // It should only emit the event for lastingWindowElement.
          expect(notifier.getEventsOfType(ApplicationMainWindowChangedEvent.self)).toEventually(haveCount(1))
          if let event = notifier.getEventOfType(ApplicationMainWindowChangedEvent.self) {
            expect(getWindowElement(event.newVal)).to(equal(lastingWindowElement))
          }
        }
      }

      context("when a new window becomes main then closes after reading the attribute") {
        it("updates the value correctly") {
          let lastingWindowElement      = createWindow(emitEvent: false)
          appElement.attrs[.MainWindow] = nil
          initializeApp()

          let closingWindowElement = createWindow(emitEvent: false)
          closingWindowElement.attrs[.Main] = true
          appElement.attrs[.MainWindow]     = closingWindowElement

          appElement.onFirstAttributeRead(.MainWindow) { _ in
            appElement.windows = appElement.windows.filter({ $0 != closingWindowElement })
            appElement.attrs[.MainWindow]     = lastingWindowElement
            lastingWindowElement.attrs[.Main] = true
            observer.emit(.UIElementDestroyed, forElement: closingWindowElement)
            observer.emit(.MainWindowChanged, forElement: lastingWindowElement)
          }

          observer.emit(.MainWindowChanged, forElement: closingWindowElement)
          observer.emit(.WindowCreated, forElement: closingWindowElement)

          expect(getWindowElement(app.mainWindow.value)).toEventually(equal(lastingWindowElement))

          // It should only emit the event for lastingWindowElement.
          expect(notifier.getEventsOfType(ApplicationMainWindowChangedEvent.self)).toEventually(haveCount(1))
          if let event = notifier.getEventOfType(ApplicationMainWindowChangedEvent.self) {
            expect(getWindowElement(event.newVal)).to(equal(lastingWindowElement))
          }
        }
      }

    }

    describe("frontmost") {

      context("when an application becomes frontmost") {
        it("updates") {
          appElement.attrs[.Frontmost] = true
          observer.emit(.ApplicationActivated, forElement: appElement)
          expect(app.frontmost.value).toEventually(beTrue())
        }
      }

      context("when an application loses frontmost status") {
        it("updates") {
          appElement.attrs[.Frontmost] = true
          initializeApp()
          observer.emit(.ApplicationDeactivated, forElement: appElement)
          expect(app.frontmost.value).toEventually(beTrue())
        }
      }

    }

    context("when a window is created") {
      var windowElement: TestWindowElement!
      beforeEach {
        windowElement = createWindow()
      }

      it("watches for events on the window") {
        notifier.waitUntilEvent(WindowCreatedEvent.self)
        expect(observer.watchedElements[windowElement]).toNot(beNil())
      }

      it("emits WindowCreatedEvent") {
        if let event = notifier.expectEvent(WindowCreatedEvent.self) {
          expect(getWindowElement(event.window)).to(equal(windowElement))
        }
      }

      it("marks the WindowCreatedEvent as external") {
        if let event = notifier.waitUntilEvent(WindowCreatedEvent.self) {
          expect(event.external).to(beTrue())
        }
      }

    }

    context("when a window is destroyed") {
      var windowElement: TestWindowElement!
      beforeEach {
        windowElement = createWindow()
        notifier.waitUntilEvent(WindowCreatedEvent.self)
        observer.emit(.UIElementDestroyed, forElement: windowElement)
      }

      it("emits WindowDestroyedEvent") {
        if let event = notifier.expectEvent(WindowDestroyedEvent.self) {
          expect(getWindowElement(event.window)).to(equal(windowElement))
        }
      }

      it("marks the WindowDestroyedEvent as external") {
        if let event = notifier.waitUntilEvent(WindowDestroyedEvent.self) {
          expect(event.external).to(beTrue())
        }
      }

    }

  }
}

/// Allows defining adversarial actions when an attribute is read.
class AdversaryWindowElement: TestWindowElement {
  var onRead: Optional<() -> ()> = nil
  var watchAttribute: Attribute? = nil
  var alreadyCalled = false

  /// Defines code that runs on the main thread before returning the value of the attribute.
  func onAttributeFirstRead(attribute: Attribute, handler: () -> ()) {
    watchAttribute = attribute
    onRead = handler
    alreadyCalled = false
  }

  override func attribute<T>(attribute: Attribute) throws -> T? {
    let result: T? = try super.attribute(attribute)
    if attribute == watchAttribute {
      performOnMainThread {
        if !self.alreadyCalled {
          self.onRead?()
          self.alreadyCalled = true
        }
      }
    }
    return result
  }
  override func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute : Any] {
    let result: [Attribute : Any] = try super.getMultipleAttributes(attributes)
    if let watchAttribute = watchAttribute where attributes.contains(watchAttribute) {
      performOnMainThread {
        if !self.alreadyCalled {
          self.onRead?()
          self.alreadyCalled = true
        }
      }
    }
    return result
  }
}

class OSXWindowDelegateSpec: QuickSpec {
  override func spec() {

    typealias WinDelegate = OSXWindowDelegate<TestUIElement, TestApplicationElement, TestObserver>
    func initializeWithElement(windowElement: TestUIElement) -> Promise<WinDelegate> {
      return WinDelegate.initialize(
        notifier: TestNotifier(), axElement: windowElement, observer: TestObserver())
    }

    beforeEach { TestApplicationElement.allApps = [] }

    describe("initialize") {

      it("initializes window properties") { () -> Promise<Void> in
        let windowElement = TestWindowElement(forApp: TestApplicationElement())
        windowElement.attrs[.Position]  = CGPoint(x: 5, y: 5)
        windowElement.attrs[.Size]      = CGSize(width: 100, height: 100)
        windowElement.attrs[.Title]     = "a window title"
        windowElement.attrs[.Minimized] = false

        return initializeWithElement(windowElement).then { windowDelegate -> () in
          expect(windowDelegate.pos.value).to(equal(CGPoint(x: 5, y: 5)))
          expect(windowDelegate.size.value).to(equal(CGSize(width: 100, height: 100)))
          expect(windowDelegate.title.value).to(equal("a window title"))
          expect(windowDelegate.minimized.value).to(beFalse())
        }
      }

      it("marks the window as valid") { () -> Promise<Void> in
        let windowElement = TestWindowElement(forApp: TestApplicationElement())
        return initializeWithElement(windowElement).then { windowDelegate -> () in
          expect(windowDelegate.valid).to(beTrue())
        }
      }

      context("when called with a window that is missing attributes") {
        it("returns an error") { () -> Promise<Void> in
          let windowElement = TestWindowElement(forApp: TestApplicationElement())
          windowElement.attrs.removeValueForKey(.Position)

          let expectedError = OSXDriverError.MissingAttribute(attribute: .Position, onElement: windowElement)
          return expectToFail(initializeWithElement(windowElement), with: expectedError)
        }
      }

      describe("AXUIElement notifications") {
        beforeEach { AdversaryObserver.reset() }

        // Because observers only have one callback per application, they are owned by the
        // application delegate and window notifications are forwarded on, so to fully test this we
        // have to test the interaction between the two.

        typealias AppDelegate = OSXApplicationDelegate<TestUIElement, TestApplicationElement, AdversaryObserver>
        typealias WinDelegate = OSXWindowDelegate<TestUIElement, TestApplicationElement, AdversaryObserver>

        var appElement: TestApplicationElement!
        var windowElement: AdversaryWindowElement!
        beforeEach {
          appElement = TestApplicationElement()
          windowElement = AdversaryWindowElement(forApp: appElement)
          appElement.windows.append(windowElement)
        }

        var observer: AdversaryObserver!
        func initialize() -> Promise<WinDelegate> {
          return AppDelegate.initialize(axElement: appElement, notifier: TestNotifier()).then { appDelegate -> WinDelegate in
            observer = appDelegate.observer
            guard let winDelegate = appDelegate.knownWindows.first as! WinDelegate? else {
              throw TestError("Window delegate was not initialized by application delegate")
            }
            return winDelegate
          }
        }

        context("when a property value changes right before observing it") {
          it("is read correctly") { () -> Promise<Void> in
            windowElement.attrs[.Minimized] = false

            AdversaryObserver.onAddNotification(.WindowMiniaturized) { _ in
              windowElement.attrs[.Minimized] = true
            }

            return initialize().then { winDelegate -> () in
              let window = Window(delegate: winDelegate)
              expect(window.minimized.value).toEventually(beTrue())
            }
          }
        }

        context("when a property value changes right after observing it") {
          // The difference between a property changing before or after observing is simply whether
          // an event is emitted or not.
          it("is updated correctly") { () -> Promise<Void> in
            windowElement.attrs[.Minimized] = false

            AdversaryObserver.onAddNotification(.WindowMiniaturized) { observer in
              observer.emit(.WindowMiniaturized, forElement: windowElement)
              dispatch_async(dispatch_get_main_queue()) {
                windowElement.attrs[.Minimized] = true
              }
            }

            return initialize().then { winDelegate -> () in
              let window = Window(delegate: winDelegate)
              expect(window.minimized.value).toEventually(beTrue())
            }
          }
        }

        context("when a property value changes right after reading it") {
          it("is updated correctly") { () -> Promise<Void> in
            windowElement.attrs[.Minimized] = false

            var observer: AdversaryObserver?
            AdversaryObserver.onAddNotification(.WindowMiniaturized) { obs in
              observer = obs
            }
            windowElement.onAttributeFirstRead(.Minimized) {
              windowElement.attrs[.Minimized] = true
              observer?.emit(.WindowMiniaturized, forElement: windowElement)
            }

            return initialize().then { winDelegate -> () in
              let window = Window(delegate: winDelegate)
              expect(window.minimized.value).toEventually(beTrue())
            }
          }
        }

      }
    }

    context("when a window is destroyed") {
      it("marks the window as invalid") { () -> Promise<Void> in
        let windowElement = TestWindowElement(forApp: TestApplicationElement())
        return initializeWithElement(windowElement).then { windowDelegate -> () in
          windowDelegate.handleEvent(.UIElementDestroyed, observer: TestObserver())
          expect(windowDelegate.valid).toEventually(beFalse())
        }
      }
    }

    context("when the position changes") {
      var notifier: TestNotifier!
      var windowElement: TestWindowElement!
      var windowDelegate: WinDelegate!
      beforeEach {
        notifier = TestNotifier()
        windowElement = TestWindowElement(forApp: TestApplicationElement())
        waitUntil { done in
          return WinDelegate.initialize(
              notifier: notifier, axElement: windowElement, observer: TestObserver()
          ).then { delegate -> () in
            windowDelegate = delegate
            done()
          }
        }

        windowElement.attrs[.Position] = CGPoint(x: 500, y: 500)
        windowDelegate.handleEvent(.Moved, observer: TestObserver())
      }

      func getWindowElement(window: Window?) -> TestUIElement? {
        return ((window?.delegate) as! WinDelegate?)?.axElement
      }

      it("emits a WindowPosChangedEvent") {
        if let event = notifier.expectEvent(WindowPosChangedEvent.self) {
          expect(getWindowElement(event.window)).to(equal(windowElement))
        }
      }

      it("marks the event as external") {
        if let event = notifier.waitUntilEvent(WindowPosChangedEvent.self) {
          expect(event.external).to(beTrue())
        }
      }

    }

    describe("property updates") {
      var window: Window!
      var windowDelegate: WinDelegate!
      var windowElement: TestWindowElement!
      beforeEach {
        waitUntil { done in
          windowElement = TestWindowElement(forApp: TestApplicationElement())
          initializeWithElement(windowElement).then { winDelegate -> () in
            windowDelegate = winDelegate
            window = Window(delegate: windowDelegate)
            done()
          }
        }
      }

      describe("title") {
        it("updates when the title changes") {
          windowElement.attrs[.Title] = "updated title"
          windowDelegate.handleEvent(.TitleChanged, observer: TestObserver())
          expect(window.title.value).toEventually(equal("updated title"))
        }
      }

      describe("pos") {
        it("updates when the position changes") {
          windowElement.attrs[.Position] = CGPoint(x: 1, y: 1)
          windowDelegate.handleEvent(.Moved, observer: TestObserver())
          expect(window.pos.value).toEventually(equal(CGPoint(x: 1, y: 1)))
        }
      }

      describe("size") {
        it("updates when the size changes") {
          windowElement.attrs[.Size] = CGSize(width: 123, height: 123)
          windowDelegate.handleEvent(.Resized, observer: TestObserver())
          expect(window.size.value).toEventually(equal(CGSize(width: 123, height: 123)))
        }
      }

      describe("minimized") {
        it("updates when the window is minimized and restored") {
          windowElement.attrs[.Minimized] = true
          windowDelegate.handleEvent(.WindowMiniaturized, observer: TestObserver())
          expect(window.minimized.value).toEventually(beTrue())

          windowElement.attrs[.Minimized] = false
          windowDelegate.handleEvent(.WindowDeminiaturized, observer: TestObserver())
          expect(window.minimized.value).toEventually(beFalse())
        }
      }

    }

  }
}
