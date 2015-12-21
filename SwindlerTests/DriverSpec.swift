import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

/// Tests that integrate the whole OS X driver instead of testing just one piece.
class OSXDriverSpec: QuickSpec {
  override func spec() {

    beforeEach { TestApplicationElement.allApps = [] }
    beforeEach { FakeObserver.observers = [] }

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

      state = State(delegate: OSXStateDelegate<TestUIElement, TestApplicationElement, FakeObserver>(
        appObserver: StubApplicationObserver()))
      observer = FakeObserver.observers.first!
      observer.emit(.WindowCreated, forElement: windowElement)
      expect(state.knownWindows.count).toEventually(equal(1))
    }

    context("when a window is created") {
      beforeEach {
        waitUntil(state.knownWindows.count == 1)
      }

      it("adds the window to knownWindows") {
        expect(state.knownWindows).to(haveCount(1))
      }

      it("has an application property equal to the application of the window") {
        waitUntil(state.runningApplications.count == 1)
        expect(state.knownWindows.first!.application).to(equal(state.runningApplications.first!))
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

  }
}
