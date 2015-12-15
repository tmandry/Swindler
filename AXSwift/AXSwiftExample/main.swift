import Cocoa

let applicationDelegate = ApplicationDelegate()
let application = NSApplication.sharedApplication()
application.setActivationPolicy(NSApplicationActivationPolicy.Accessory)
application.delegate = applicationDelegate
application.run()