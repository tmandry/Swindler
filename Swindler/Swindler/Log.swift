import ASLLog

/// Internal logger.
internal private(set) var log = Log()

/// Internal logging methods. Uses ASL to log to system console at correct log levels.
struct Log {
  static var token: dispatch_once_t = 0
  init() {
    dispatch_once(&Log.token) {
      asl_add_log_file(nil, STDERR_FILENO)
      asl_set_filter(nil, aslFilterMaskUpTo(ASL_LEVEL_DEBUG))
    }
  }

  // TODO: filter out logs depending on build settings.

  /// Log that something has failed.
  func error(@autoclosure log: () -> (String)) {
    aslLog(log(), ASL_LEVEL_ERR)
  }

  /// Log that something is amiss which might result in a failure.
  func warn(@autoclosure log: () -> (String)) {
    aslLog(log(), ASL_LEVEL_WARNING)
  }

  /// Log something of moderate interest to the user or administrator.
  func notice(@autoclosure log: () -> (String)) {
    aslLog(log(), ASL_LEVEL_NOTICE)
  }

  /// Log something purely informational (not visible in production).
  func info(@autoclosure log: () -> (String)) {
    aslLog(log(), ASL_LEVEL_INFO)
  }

  /// Log debug info (not visible in production).
  func debug(@autoclosure log: () -> (String)) {
    aslLog(log(), ASL_LEVEL_DEBUG)
  }

  /// Log more verbose debug info (usually not visible in production or development).
  func trace(@autoclosure log: () -> (String)) {
    aslLog(log(), ASL_LEVEL_DEBUG)
  }

}

/*
#define	ASL_FILTER_MASK(level) (1 << (level))
#define	ASL_FILTER_MASK_UPTO(level) ((1 << ((level) + 1)) - 1)
*/

private func aslFilterMaskUpTo(level: Int32) -> Int32 {
  return ((1 << ((level) + 1)) - 1)
}
