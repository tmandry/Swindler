//
//  AppDelegate.swift
//  SwindlerExample
//
//  Created by Tyler Mandry on 10/20/15.
//  Copyright © 2015 Tyler Mandry. All rights reserved.
//

import Cocoa
import Swindler

func dispatchAfter(delay: NSTimeInterval, block: dispatch_block_t) {
  let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC)))
  dispatch_after(time, dispatch_get_main_queue(), block)
}

class AppDelegate: NSObject, NSApplicationDelegate {

  var swindler: Swindler.StateType!

  func applicationDidFinishLaunching(aNotification: NSNotification) {
    swindler = Swindler.state
    swindler.on { (event: WindowCreatedEvent) in
      let window = event.window
      print("new window: \(window)")
    }
    swindler.on { (event: WindowPosChangedEvent) in
      print("Pos changed from \(event.oldVal) to \(event.newVal), external: \(event.external)")
    }
    swindler.on { (event: WindowSizeChangedEvent) in
      print("Size changed from \(event.oldVal) to \(event.newVal), external: \(event.external)")
    }
    swindler.on { (event: WindowDestroyedEvent) in
      print("window destroyed: \(event.window)")
    }

    dispatchAfter(10.0) {
      for window in self.swindler.visibleWindows {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
          print("resizing \(window.title)")
          window.size.value = CGSize(width: 200, height: 200)
          print("done with \(window.title), valid: \(window.valid)")
        }
      }
    }
  }

  func applicationWillTerminate(aNotification: NSNotification) {
    // Insert code here to tear down your application
  }

}
