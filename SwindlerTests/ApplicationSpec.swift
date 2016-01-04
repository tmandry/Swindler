import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

class OSXApplicationDelegateInitializeSpec: QuickSpec {
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

      typealias AppDelegate = OSXApplicationDelegate<TestUIElement, TestApplicationElement, FakeObserver>

      context("when the application UIElement is invalid") {
        it("resolves to an error") { () -> Promise<Void> in
          appElement.throwInvalid = true
          let promise = AppDelegate.initialize(axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the application is missing the Windows attribute") {
        it("resolves to an error") { () -> Promise<Void> in
          appElement.attrs[.Windows] = nil
          let promise = AppDelegate.initialize(axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the application is missing a required property attribute") {
        it("resolves to an error") { () -> Promise<Void> in
          appElement.attrs[.Frontmost] = nil
          let promise = AppDelegate.initialize(axElement: appElement, notifier: notifier)
          return expectToFail(promise)
        }
      }

      context("when the application is missing an optional property attribute") {
        it("succeeds") { () -> Promise<Void> in
          appElement.attrs[.MainWindow] = nil
          let promise = AppDelegate.initialize(axElement: appElement, notifier: notifier)
          return expectToSucceed(promise)
        }
      }

      it("doesn't leak") {
        weak var appDelegate: AppDelegate?
        waitUntil { done in
          AppDelegate.initialize(axElement: appElement, notifier: notifier).then { delegate -> () in
            appDelegate = delegate
            done()
          }
        }
        expect(appDelegate).to(beNil())
      }

      it("doesn't leak the notifier") {
        weak var notifier: TestNotifier?
        var appDelegate: AppDelegate?
        waitUntil { done in
          let n = TestNotifier()
          notifier = n
          AppDelegate.initialize(axElement: appElement, notifier: n).then { delegate -> () in
            appDelegate = delegate
            done()
          }
        }
        expect(appDelegate).toNot(beNil())
        expect(notifier).to(beNil())
      }

      context("when there is a window") {
        it("doesn't leak memory") {
          let windowElement = TestWindowElement(forApp: appElement)
          appElement.windows.append(windowElement)

          weak var appDelegate: AppDelegate?
          waitUntil { done in
            AppDelegate.initialize(axElement: appElement, notifier: notifier).then { delegate -> () in
              expect(delegate.knownWindows).to(haveCount(1))
              appDelegate = delegate
              done()
            }
          }
          expect(appDelegate).to(beNil())
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

  }
}

class OSXApplicationDelegateNotificationSpec: QuickSpec {
  override func spec() {

    describe("AXUIElement notifications") {
      var appElement: AdversaryApplicationElement!
      var notifier: TestNotifier!
      beforeEach {
        appElement = AdversaryApplicationElement()
        notifier = TestNotifier()
      }
      beforeEach { AdversaryObserver.reset() }

      typealias AppDelegate = OSXApplicationDelegate<TestUIElement, AdversaryApplicationElement, AdversaryObserver>
      func initializeApp() -> AppDelegate {
        // Initializing the app synchronously avoids problems with intermittent failures caused by
        // Quick/Nimble and simplifies tests.
        var appDelegate: AppDelegate?
        waitUntil { done in
          AppDelegate.initialize(axElement: appElement, notifier: notifier).then { appDel -> () in
            appDelegate = appDel
            done()
          }
        }
        return appDelegate!
      }

      context("when a property value changes right before observing it") {

        context("for a regular property") {
          it("is read correctly") {
            appElement.attrs[.Frontmost] = false

            AdversaryObserver.onAddNotification(.ApplicationActivated) { _ in
              appElement.attrs[.Frontmost] = true
            }

            let app = Swindler.Application(delegate: initializeApp())
            expect(app.isFrontmost.value).toEventually(beTrue())
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

            let app = Swindler.Application(delegate: initializeApp())
            expect(app.mainWindow.value).toEventuallyNot(beNil())
          }
        }

      }

      context("when a property value changes right after observing it") {
        // The difference between a property changing before or after observing is simply whether
        // an event is emitted or not.

        context("for a regular property") {
          it("is updated correctly") {
            appElement.attrs[.Frontmost] = false

            AdversaryObserver.onAddNotification(.ApplicationActivated) { observer in
              appElement.attrs[.Frontmost] = true
              observer.emit(.ApplicationActivated, forElement: appElement)
            }

            let app = Swindler.Application(delegate: initializeApp())
            expect(app.isFrontmost.value).toEventually(beTrue())
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

            let app = Swindler.Application(delegate: initializeApp())
            expect(app.mainWindow.value).toEventuallyNot(beNil())
          }
        }

      }

      context("when a property value changes right after reading it") {

        context("for a regular property") {
          it("is updated correctly") {
            appElement.attrs[.Frontmost] = false

            var observer: AdversaryObserver?
            AdversaryObserver.onAddNotification(.ApplicationActivated) { obs in
              observer = obs
            }
            appElement.onFirstAttributeRead(.Frontmost) { _ in
              appElement.attrs[.Frontmost] = true
              observer?.emit(.ApplicationActivated, forElement: appElement)
            }

            let app = Swindler.Application(delegate: initializeApp())
            expect(app.isFrontmost.value).toEventually(beTrue())
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

            let app = Swindler.Application(delegate: initializeApp())
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
          axElement: appElement, notifier: notifier
        ).then { applicationDelegate -> () in
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

    func createWindow(
      emitEvent emitEvent: Bool = true,
      windowElement element: TestWindowElement? = nil
    ) -> TestWindowElement {
      let windowElement = element ?? TestWindowElement(forApp: appElement)
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
            expect(event.application).to(equal(app))
            expect(event.external).to(beTrue())
            expect(event.oldValue).to(beNil())
            expect(getWindowElement(event.newValue)).to(equal(windowElement))
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

      context("when a window is assigned") {

        var windowElement: TestWindowElement!
        var window: Window!
        var setPromise: Promise<Window?>!
        func createAndSetMainWindow(element: TestWindowElement) {
          windowElement = element
          createWindow(windowElement: element)
          waitUntil(app.knownWindows.count == 1)
          window = app.knownWindows.first!
          setPromise = app.mainWindow.set(window)
        }

        context("when the app complies") {
          beforeEach {
            createAndSetMainWindow(TestWindowElement(forApp: appElement))
          }

          it("changes the main window") {
            expect(windowElement.attrs[.Main] as! Bool?).toEventually(beTrue())
          }

          it("returns the new main window in the promise") { () -> Promise<Void> in
            return setPromise.then { newMainWindow in
              expect(newMainWindow).to(equal(window))
            }
          }

        }

        context("when the app refuses to make the window main") {
          class MyWindowElement: TestWindowElement {
            override func setAttribute(attribute: Attribute, value: Any) throws {
              if attribute == .Main { return }
              else { try super.setAttribute(attribute, value: value) }
            }
          }
          beforeEach {
            createAndSetMainWindow(MyWindowElement(forApp: appElement))
          }

          it("returns the old value in the promise") { () -> Promise<Void> in
            return setPromise.then { newMainWindow in
              expect(newMainWindow).to(beNil())
            }
          }

        }

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
            expect(getWindowElement(event.newValue)).to(equal(lastingWindowElement))
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
            expect(getWindowElement(event.newValue)).to(equal(lastingWindowElement))
          }
        }
      }

    }

    describe("focusedWindow") {

      context("when there is no initial focused window") {
        it("equals nil") {
          expect(appElement.attrs[.FocusedWindow]).to(beNil())
          expect(app.focusedWindow.value).to(beNil())
        }
      }

      context("when there is an initial focused window") {
        it("equals the main window") {
          let windowElement = createWindow(emitEvent: false)
          windowElement.attrs[.Focused] = true
          appElement.attrs[.FocusedWindow] = windowElement
          initializeApp()

          expect(getWindowElement(app.focusedWindow.value)).to(equal(windowElement))
        }
      }

      context("when a window becomes focused") {
        var windowElement: TestWindowElement!
        beforeEach {
          windowElement = createWindow()
          windowElement.attrs[.Focused] = true
          appElement.attrs[.FocusedWindow] = windowElement
          observer.emit(.FocusedWindowChanged, forElement: windowElement)
        }

        it("updates the value") {
          expect(getWindowElement(app.focusedWindow.value)).toEventually(equal(windowElement))
        }

         it("emits an ApplicationFocusedWindowChangedEvent with correct values") {
           if let event = notifier.expectEvent(ApplicationFocusedWindowChangedEvent.self) {
             expect(event.application).to(equal(app))
             expect(event.external).to(beTrue())
             expect(event.oldValue).to(beNil())
             expect(getWindowElement(event.newValue)).to(equal(windowElement))
           }
         }

      }
    }

    describe("isFrontmost") {
      context("when an application becomes frontmost") {
        beforeEach {
          appElement.attrs[.Frontmost] = true
          observer.emit(.ApplicationActivated, forElement: appElement)
        }

        it("updates") {
          expect(app.isFrontmost.value).toEventually(beTrue())
        }

        it("emits ApplicationIsFrontmostChangedEvent") {
          notifier.expectEvent(ApplicationIsFrontmostChangedEvent.self)
        }

      }

      context("when an application loses frontmost status") {
        beforeEach {
          appElement.attrs[.Frontmost] = true
          initializeApp()
          appElement.attrs[.Frontmost] = false
          observer.emit(.ApplicationDeactivated, forElement: appElement)
        }

        it("updates") {
          expect(app.isFrontmost.value).toEventually(beTrue())
        }

        it("emits ApplicationIsFrontmostChangedEvent") {
          notifier.expectEvent(ApplicationIsFrontmostChangedEvent.self)
        }

      }
    }

    describe("isHidden") {
      context("when an application hides") {
        beforeEach {
          appElement.attrs[.Hidden] = true
          observer.emit(.ApplicationHidden, forElement: appElement)
        }

        it("updates") {
          expect(app.isHidden.value).toEventually(beTrue())
        }

        it("emits ApplicationIsHiddenChangedEvent") {
          notifier.expectEvent(ApplicationIsHiddenChangedEvent.self)
        }

      }

      context("when an application unhides") {
        beforeEach {
          appElement.attrs[.Hidden] = true
          initializeApp()
          appElement.attrs[.Hidden] = false
          observer.emit(.ApplicationShown, forElement: appElement)
        }

        it("updates") {
          expect(app.isHidden.value).toEventually(beFalse())
        }

        it("emits ApplicationIsHiddenChangedEvent") {
          notifier.expectEvent(ApplicationIsHiddenChangedEvent.self)
        }

      }
    }

    describe("Application equality") {

      it("returns true for identical app delegates") {
        expect(app).to(equal(Application(delegate: appDelegate)))
      }

      it("returns false for different app delegates") { () -> Promise<Void> in
        let otherAppElement = AdversaryApplicationElement()
        return OSXApplicationDelegate<TestUIElement, AdversaryApplicationElement, FakeObserver>.initialize(
          axElement: otherAppElement, notifier: notifier).then { otherAppDelegate -> () in
            expect(app).toNot(equal(Application(delegate: otherAppDelegate)))
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
