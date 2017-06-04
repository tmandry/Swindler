import Cocoa
import AXSwift

class AppDelegate: NSObject, NSApplicationDelegate {

  var observer: Observer!

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let app = Application.allForBundleID("com.apple.finder").first!

    do {
      try startWatcher(app)
    } catch let error {
      NSLog("Error: Could not watch app [\(app)]: \(error)")
      abort()
    }
  }

  func startWatcher(_ app: Application) throws {
    var updated = false
    observer = app.createObserver() { (observer: Observer, element: UIElement, event: AXNotification, info: [String: AnyObject]?) in
      var elementDesc: String!
      if let role = try? element.role()!, role == .Window {
        elementDesc = "\(element) \"\(try! (element.attribute(.Title) as String?)!)\""
      } else {
        elementDesc = "\(element)"
      }
      print("\(event) on \(elementDesc); info: \(info ?? [:])")

      // Watch events on new windows
      if event == .WindowCreated {
        do {
          try observer.addNotification(.UIElementDestroyed, forElement: element)
          try observer.addNotification(.Moved, forElement: element)
        } catch let error {
          NSLog("Error: Could not watch [\(element)]: \(error)")
        }
      }

      // Group simultaneous events together with --- lines
      if !updated {
        updated = true
        // Set this code to run after the current run loop, which is dispatching all notifications.
        DispatchQueue.main.async() {
          print("---")
          updated = false
        }
      }
    }

    try observer.addNotification(.WindowCreated, forElement: app)
    try observer.addNotification(.MainWindowChanged, forElement: app)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

}
