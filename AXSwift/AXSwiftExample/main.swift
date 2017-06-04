import Cocoa

let applicationDelegate = ApplicationDelegate()
let application = NSApplication.shared()
application.setActivationPolicy(NSApplicationActivationPolicy.accessory)
application.delegate = applicationDelegate
application.run()
