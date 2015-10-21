import Cocoa
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(aNotification: NSNotification) {
    // Check that we have permission
    guard UIElement.isProcessTrusted(withPrompt: true) else {
      NSLog("No accessibility API permission, exiting")
      NSRunningApplication.currentApplication().terminate()
      return
    }

    // Get Active Application
    if let application = NSWorkspace.sharedWorkspace().frontmostApplication {
      NSLog("localizedName: \(application.localizedName), processIdentifier: \(application.processIdentifier)")
      let uiApp = Application(application)!
      NSLog("windows: \(try! uiApp.windows())")
      NSLog("attributes: \(try! uiApp.attributes())")
      NSLog("at 0,0: \(try! uiApp.elementAtPosition(0,0))")
      if let bundleIdentifier = application.bundleIdentifier {
        NSLog("bundleIdentifier: \(bundleIdentifier)")
        let windows = try! Application.allForBundleID(bundleIdentifier).first!.windows()
        NSLog("windows: \(windows)")
      }
    }

    // Get Application by bundleIdentifier
    let app = Application.allForBundleID("com.apple.finder").first!
    NSLog("finder: \(app)")
    NSLog("role: \(try! app.role()!)")
    NSLog("windows: \(try! app.windows()!)")
    NSLog("attributes: \(try! app.attributes())")
    if let title: String = try! app.attribute(.Title) {
      NSLog("title: \(title)")
    }
    NSLog("multi: \(try! app.getMultipleAttributes(["AXRole", "asdf", "AXTitle"]))")
    NSLog("multi: \(try! app.getMultipleAttributes(.Role, .Title))")

    NSLog("system wide:")
    NSLog("role: \(try! systemWideElement.role()!)")
    // NSLog("windows: \(try! sys.windows())")
    NSLog("attributes: \(try! systemWideElement.attributes())")

    NSRunningApplication.currentApplication().terminate()
  }
}