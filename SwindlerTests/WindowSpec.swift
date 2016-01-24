import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

// The window delegate holds a weak reference to the app delegate, so we use this singleton to ensure
// it doesn't get destroyed. Same for app -> state. See #3.
private let stubApplicationDelegate = StubApplicationDelegate()

class OSXWindowDelegateInitializeSpec: QuickSpec {
  override func spec() {

    typealias WinDelegate = OSXWindowDelegate<TestUIElement, TestApplicationElement, TestObserver>

    var windowElement: TestWindowElement!
    beforeEach {
      TestApplicationElement.allApps = []
      windowElement = TestWindowElement(forApp: TestApplicationElement())
    }

    func initializeWithElement(winElement: TestWindowElement) -> Promise<WinDelegate> {
      return WinDelegate.initialize(
        appDelegate: stubApplicationDelegate, notifier: TestNotifier(), axElement: winElement, observer: TestObserver())
    }

    func initialize() -> Promise<WinDelegate> {
      return initializeWithElement(windowElement)
    }

    it("doesn't leak memory") {
      weak var windowDelegate: WinDelegate?
      waitUntil { done in
        initialize().then { delegate -> () in
          windowDelegate = delegate
          done()
        }
      }
      expect(windowDelegate).to(beNil())
    }

    describe("initialize") {

      it("initializes window properties") { () -> Promise<Void> in
        windowElement.attrs[.Position]   = CGPoint(x: 5, y: 5)
        windowElement.attrs[.Size]       = CGSize(width: 100, height: 100)
        windowElement.attrs[.Title]      = "a window title"
        windowElement.attrs[.Minimized]  = false
        windowElement.attrs[.FullScreen] = false

        return initialize().then { windowDelegate -> () in
          expect(windowDelegate.position.value).to(equal(CGPoint(x: 5, y: 5)))
          expect(windowDelegate.size.value).to(equal(CGSize(width: 100, height: 100)))
          expect(windowDelegate.title.value).to(equal("a window title"))
          expect(windowDelegate.isMinimized.value).to(beFalse())
          expect(windowDelegate.isFullscreen.value).to(beFalse())
        }
      }

      it("stores the ApplicationDelegate in appDelegate") { () -> Promise<Void> in
        return initialize().then { winDelegate in
          expect(winDelegate.appDelegate === stubApplicationDelegate).to(beTrue())
        }
      }

      it("marks the window as valid") { () -> Promise<Void> in
        return initialize().then { windowDelegate -> () in
          expect(windowDelegate.isValid).to(beTrue())
        }
      }

      context("when called with a window that is missing attributes") {
        it("returns an error") { () -> Promise<Void> in
          windowElement.attrs.removeValueForKey(.Position)

          let expectedError = OSXDriverError.MissingAttribute(attribute: .Position, onElement: windowElement)
          return expectToFail(initialize(), with: expectedError)
        }
      }

      context("when called with a window whose subrole is AXUnknown") {
        it("returns an error") { () -> Promise<Void> in
          windowElement.attrs[.Subrole] = "AXUnknown"  // undocumented as a subrole, but very important
          return expectToFail(initialize())
        }
      }

    }

    describe("Window equality") {

      it("returns true for identical WindowDelegates") { () -> Promise<Void> in
        return initialize().then { windowDelegate in
          expect(Window(delegate: windowDelegate)).to(equal(Window(delegate: windowDelegate)))
        }
      }

      it("returns false for different WindowDelegates") { () -> Promise<Void> in
        return initialize().then { windowDelegate1 in
          let windowElement2 = TestWindowElement(forApp: TestApplicationElement())
          return initializeWithElement(windowElement2).then { windowDelegate2 -> () in
            expect(Window(delegate: windowDelegate1)).toNot(equal(Window(delegate: windowDelegate2)))
          }
        }
      }

    }

  }
}

class OSXWindowDelegateNotificationSpec: QuickSpec {
  override func spec() {

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
        return AppDelegate
          .initialize(axElement: appElement, stateDelegate: StubStateDelegate(), notifier: TestNotifier())
          .then { appDelegate -> WinDelegate in
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
            expect(winDelegate.isMinimized.value).toEventually(beTrue())
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
            expect(winDelegate.isMinimized.value).toEventually(beTrue())
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
            expect(winDelegate.isMinimized.value).toEventually(beTrue())
          }
        }
      }

    }

  }
}

class OSXWindowDelegateSpec: QuickSpec {
  override func spec() {

    typealias WinDelegate = OSXWindowDelegate<TestUIElement, TestApplicationElement, TestObserver>

    var windowElement: TestWindowElement!
    var windowDelegate: WinDelegate!
    var notifier: TestNotifier!
    beforeEach {
      windowElement = TestWindowElement(forApp: TestApplicationElement())
      notifier = TestNotifier()
      waitUntil { done in
        WinDelegate.initialize(
            appDelegate: stubApplicationDelegate,
            notifier: notifier,
            axElement: windowElement,
            observer: TestObserver()).then { winDelegate -> () in
          windowDelegate = winDelegate
          done()
        }
      }
    }

    context("when a window is destroyed") {
      it("marks the window as invalid") {
        windowDelegate.handleEvent(.UIElementDestroyed, observer: TestObserver())
        expect(windowDelegate.isValid).toEventually(beFalse())
      }
    }

    context("when the position changes") {
      beforeEach {
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

      describe("title") {
        it("updates when the title changes") {
          windowElement.attrs[.Title] = "updated title"
          windowDelegate.handleEvent(.TitleChanged, observer: TestObserver())
          expect(windowDelegate.title.value).toEventually(equal("updated title"))
        }
      }

      describe("position") {
        it("updates when the window is moved") {
          windowElement.attrs[.Position] = CGPoint(x: 1, y: 1)
          windowDelegate.handleEvent(.Moved, observer: TestObserver())
          expect(windowDelegate.position.value).toEventually(equal(CGPoint(x: 1, y: 1)))
        }
      }

      describe("size") {
        it("updates when the window is resized") {
          windowElement.attrs[.Size] = CGSize(width: 123, height: 123)
          windowDelegate.handleEvent(.Resized, observer: TestObserver())
          expect(windowDelegate.size.value).toEventually(equal(CGSize(width: 123, height: 123)))
        }
      }

      describe("isFullscreen") {
        it("updates when the window is resized") {
          windowElement.attrs[.FullScreen] = true
          windowDelegate.handleEvent(.Resized, observer: TestObserver())
          expect(windowDelegate.isFullscreen.value).toEventually(beTrue())
        }
      }

      describe("isMinimized") {
        it("updates when the window is minimized and restored") {
          windowElement.attrs[.Minimized] = true
          windowDelegate.handleEvent(.WindowMiniaturized, observer: TestObserver())
          expect(windowDelegate.isMinimized.value).toEventually(beTrue())

          windowElement.attrs[.Minimized] = false
          windowDelegate.handleEvent(.WindowDeminiaturized, observer: TestObserver())
          expect(windowDelegate.isMinimized.value).toEventually(beFalse())
        }
      }

    }

  }
}
