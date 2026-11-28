extension Duration {
  /// The duration in seconds, as the `TimeInterval` that SpriteKit and AppKit take.
  public var inSeconds: Double {
    let (seconds, attoseconds) = components
    return Double(seconds) + Double(attoseconds) / 1e18
  }
}
