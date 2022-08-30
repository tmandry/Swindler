import Foundation
import rogue

@main enum Main {
    static func main() async {
        // For some reason Ctrl+C doesn't work without installing this handler (Swift 5.6),
        // I'm guessing some assumptions about using a DispatchQueue main loop or similar.
        signal(SIGINT) { _ in
            exit(130)
        }

        for await app in AppWatcher.launches {
            print(app)
        }
    }
}
