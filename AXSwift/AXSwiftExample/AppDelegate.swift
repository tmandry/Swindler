import Cocoa
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Check that we have permission
    guard UIElement.isProcessTrusted(withPrompt: true) else {
      NSLog("No accessibility API permission, exiting")
      NSRunningApplication.current().terminate()
      return
    }

    // Get Active Application
    if let application = NSWorkspace.shared().frontmostApplication {
      NSLog("localizedName: \(String(describing: application.localizedName)), processIdentifier: \(application.processIdentifier)")
      let uiApp = Application(application)!
      NSLog("windows: \(String(describing: try! uiApp.windows()))")
      NSLog("attributes: \(try! uiApp.attributes())")
      NSLog("at 0,0: \(String(describing: try! uiApp.elementAtPosition(0,0)))")
      if let bundleIdentifier = application.bundleIdentifier {
        NSLog("bundleIdentifier: \(bundleIdentifier)")
        let windows = try! Application.allForBundleID(bundleIdentifier).first!.windows()
        NSLog("windows: \(String(describing: windows))")
      }
    }

    // Get Application by bundleIdentifier
    let app = Application.allForBundleID("com.apple.finder").first!
    NSLog("finder: \(app)")
    NSLog("role: \(try! app.role()!)")
    NSLog("windows: \(try! app.windows()!)")
    NSLog("attributes: \(try! app.attributes())")
    if let title: String = try! app.attribute(.title) {
      NSLog("title: \(title)")
    }
    NSLog("multi: \(try! app.getMultipleAttributes(["AXRole", "asdf", "AXTitle"]))")
    NSLog("multi: \(try! app.getMultipleAttributes(.role, .title))")

    // Try to set an unsettable attribute
    if let window = try! app.windows()?.first {
      do {
        try window.setAttribute(.title, value: "my title")
        let newTitle: String = try! window.attribute(.title)!
        NSLog("title set; result = \(newTitle)")
      } catch {
        NSLog("error caught trying to set title of window: \(error)")
      }
    }

    NSLog("system wide:")
    NSLog("role: \(try! systemWideElement.role()!)")
    // NSLog("windows: \(try! sys.windows())")
    NSLog("attributes: \(try! systemWideElement.attributes())")

    NSRunningApplication.current().terminate()
  }
}
