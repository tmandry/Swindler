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

        let reactor = try await Reactor()
        await reactor.setLayout(LayoutTall())
        try await reactor.run()
    }
}
