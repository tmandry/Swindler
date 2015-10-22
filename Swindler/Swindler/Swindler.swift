public protocol State {
  var visibleWindows: [Window] { get }
}

public protocol Window {
  var pos: CGPoint { get set }
  var size: CGSize { get set }
  var rect: CGRect { get set }
}

extension Window {
  // Convenience parameter
  var rect: CGRect {
    get { return CGRect(origin: pos, size: size) }
    set {
      pos = newValue.origin
      size = newValue.size
    }
  }
}
