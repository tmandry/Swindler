import Foundation

/// Internal logger.
internal private(set) var log = Log()

private let COLOR_ENABLED = (ProcessInfo().environment["SWINDLER_COLOR"] == "1")

struct StderrOutputStream: TextOutputStream {
  public mutating func write(_ string: String) {
    fputs(string, stderr)
  }
}
var stderrStream = StderrOutputStream()

/// Internal logging methods.
struct Log {
    enum Level {
        case error
        case warn
        case notice
        case info
        case debug
        case trace
    }

    /// Log that something has failed.
    func error(_ out: @autoclosure () -> String) {
        log(out(), level: .error, withColor: .red)
    }
    /// Log that something is amiss which might result in a failure.
    func warn(_ out: @autoclosure () -> String) {
        log(out(), level: .warn, withColor: .yellow)
    }

    /// Log something of moderate interest to the user or administrator.
    func notice(_ out: @autoclosure () -> String) {
        log(out(), level: .notice, withColor: .purple)
    }

    /// Log something purely informational (not visible in production).
    func info(_ out: @autoclosure () -> String) {
#if SWINDLER_DEBUG
        log(out(), level: .info, withColor: .cyan)
#endif
    }

    /// Log debug info (not visible in production).
    func debug(_ out: @autoclosure () -> String) {
#if SWINDLER_DEBUG
        log(out(), level: .debug, withColor: .blue)
#endif
    }

    /// Log more verbose debug info (usually not visible in production or development).
    func trace(_ out: @autoclosure () -> String) {
#if SWINDLER_TRACE
        log(out(), level: .trace, withColor: Color.gray)
#endif
    }

    enum Color: Int8 {
        case red = 31
        case green = 32
        case yellow = 33
        case blue = 34
        case purple = 35
        case cyan = 36
        case gray = 37
    }

    // Log on the given log level, using the given color if XcodeColors is enabled.
    fileprivate func log(_ string: String, level: Level, withColor: Color? = nil) {
        var output = ""
        if let color = withColor, COLOR_ENABLED {
            let escape = "\u{001b}["
            let reset = "\(escape)0m"
            output = "\(escape)\(color.rawValue)m\(string)\(reset)"
        } else {
            output = string
        }
        // stderr seems to get thrown away by `swift test`, so we print to stdout
        // for now.
        // print(output, to: &stderrStream)
        print(output)
    }

}
