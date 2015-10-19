import Cocoa
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(aNotification: NSNotification) {
    // Get Active Application
    if let application = NSWorkspace.sharedWorkspace().frontmostApplication {
      NSLog("localizedName: \(application.localizedName), processIdentifier: \(application.processIdentifier)")
      let uiApp = Application(application)!
      NSLog("windows: \(try! uiApp.windows())")
      NSLog("attributes: \(try! uiApp.attributes())")
      NSLog("at 0,0: \(try! uiApp.elementAtPosition(0,0))")
      if let bundleIdentifier = application.bundleIdentifier {
        NSLog("bundleIdentifier: \(bundleIdentifier)")
        let windows = try! Application.all(forBundleID: bundleIdentifier).first!.windows()
        NSLog("windows: \(windows)")
      }
    }

    // Get Application by bundleIdentifier
    NSLog("finder:")
    let app = Application.all(forBundleID: "com.apple.finder").first!
    if let role: AnyObject = try! app.attribute("AXRole") {
      NSLog("role: \(role)")
    }
    NSLog("role: \(try! app.role()!)")
    NSLog("windows: \(try! app.windows()!)")
    NSLog("attributes: \(try! app.attributes())")
    if let title: String = try! app.attribute("AXTitle") {
      NSLog("title: \(title)")
    }
    let dict = try! app.getMultipleAttributes("AXRole", "asdf", "AXTitle")
    NSLog("multi: \(dict)")

    NSLog("system wide:")
    let sys = SystemWideElement()
    NSLog("role: \(try! sys.role()!)")
    // NSLog("windows: \(try! sys.windows())")
    NSLog("attributes: \(try! sys.attributes())")

    NSRunningApplication.currentApplication().terminate()
  }
}