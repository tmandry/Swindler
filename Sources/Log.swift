//import ASLLog

/// Internal logger.
internal private(set) var log = Log()

private let COLOR_ENABLED = (ProcessInfo().environment["SWINDLER_COLOR"] == "1")

struct StderrOutputStream: TextOutputStream {
  public mutating func write(_ string: String) {
    fputs(string, stderr)
  }
}
var stderrStream = StderrOutputStream()

/// Internal logging methods. Uses ASL to log to system console at correct log levels.
struct Log {
    private static var __once: () = {
        //asl_add_log_file(nil, STDERR_FILENO)
        //asl_set_filter(nil, aslFilterMaskUpTo(ASL_LEVEL_DEBUG))
    }()
    static var token: Int = 0
    init() {
        _ = Log.__once
    }

    enum Level {
        case error
        case warn
        case notice
        case info
        case debug
        case trace
    }

    // TODO: filter out logs depending on build settings.

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
        //aslLog(output, level)
        print(output, to: &stderrStream)
    }

}

/*
#define	ASL_FILTER_MASK(level) (1 << (level))
#define	ASL_FILTER_MASK_UPTO(level) ((1 << ((level) + 1)) - 1)
*/

private func aslFilterMaskUpTo(_ level: Int32) -> Int32 {
    return ((1 << (level + 1)) - 1)
}
