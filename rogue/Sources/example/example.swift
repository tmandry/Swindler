import Cocoa
import Foundation
import rogue

@main enum Main {
    static func main() async throws {
        // For some reason Ctrl+C doesn't work without installing this handler (Swift 5.6),
        // I'm guessing some assumptions about using a DispatchQueue main loop or similar.
        signal(SIGINT) { _ in
            exit(130)
        }

        // for await app in AppWatcher.launches {
        //     print(app)
        // }

        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
        application.run()
    }
}

public class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        Task {
            let reactor = try await Reactor()
            await reactor.setLayout(LayoutTall())
            try await reactor.setup()
        }
    }
}
