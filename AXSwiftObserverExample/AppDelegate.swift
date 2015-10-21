import Cocoa
import AXSwift

class AppDelegate: NSObject, NSApplicationDelegate {

  var observer: Observer!

  func applicationDidFinishLaunching(aNotification: NSNotification) {
    let app = Application.all(forBundleID: "com.apple.finder").first!

    do {
      try startWatcher(app)
    } catch let error {
      NSLog("Error: Could not watch app [\(app)]: \(error)")
      abort()
    }
  }

  func startWatcher(app: Application) throws {
    let pid = try! app.pid()
    
    var updated = false
    observer = try Observer(processID: pid) { (observer: Observer, element: UIElement, event: Notification) in
      print("\(element): \(event)")

      // Watch events on new windows
      if event == .WindowCreated {
        do {
          try observer.addNotification(element, notification: .UIElementDestroyed)
          try observer.addNotification(element, notification: .Moved)
        } catch let error {
          NSLog("Error: Could not watch [\(element)]: \(error)")
        }
      }

      // Group simultaneous events together with --- lines
      if !updated {
        updated = true
        // Set this code to run after the current run loop, which is dispatching all notifications.
        dispatch_async(dispatch_get_main_queue()) {
          print("---")
          updated = false
        }
      }
    }

    try observer.addNotification(app, notification: .WindowCreated)
    try observer.addNotification(app, notification: .MainWindowChanged)
  }

  func applicationWillTerminate(aNotification: NSNotification) {
    // Insert code here to tear down your application
  }

}
