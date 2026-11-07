import AppKit
import Metal
import QuartzCore
import SpriteKit

/// Draws a SpriteKit scene into a transparent Metal layer, at the frame rate it is asked for, and
/// not at all while paused.
///
/// It replaces `SKView`, which keeps a display link firing at the display's full refresh rate
/// whenever it runs, whatever its `preferredFramesPerSecond`. On screen that cost about 1% CPU
/// before drawing anything (ADR 0011). Here a `CADisplayLink` asks for exactly `framesPerSecond`.
///
/// The display link retains this view, so the view lives as long as its window. Removing it from
/// its window invalidates the link and ends the cycle; dropping the window without that would leak
/// the view, its scene and a link that keeps firing.
@MainActor
final class SceneHostView: NSView {
  /// The scene drawn. Its size follows the view's size.
  let scene: SKScene

  var framesPerSecond = 30 {
    didSet {
      guard framesPerSecond != oldValue else { return }
      applyFrameRate()
    }
  }

  /// Whether drawing is stopped. While paused, the scene doesn't update and nothing runs.
  var isPaused = true {
    didSet {
      guard isPaused != oldValue else { return }
      updateDisplayLink()
    }
  }

  private let renderer: SKRenderer
  private let commandQueue: MTLCommandQueue
  private let metalLayer = CAMetalLayer()
  private var displayLink: CADisplayLink?

  /// Creates a view drawing `scene`, or returns `nil` when the Mac has no Metal device.
  init?(scene: SKScene) {
    guard
      let device = MTLCreateSystemDefaultDevice(),
      let commandQueue = device.makeCommandQueue()
    else { return nil }
    self.scene = scene
    self.commandQueue = commandQueue
    renderer = SKRenderer(device: device)
    renderer.scene = scene
    super.init(frame: .zero)
    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = true
    metalLayer.isOpaque = false
    metalLayer.backgroundColor = .clear
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func makeBackingLayer() -> CALayer {
    metalLayer
  }

  override func layout() {
    super.layout()
    resizeDrawable()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    resizeDrawable()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    displayLink?.invalidate()
    displayLink = nil
    updateDisplayLink()
  }

  // MARK: - Drawing

  private func resizeDrawable() {
    let scale = window?.backingScaleFactor ?? 2
    metalLayer.contentsScale = scale
    metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    if bounds.size != .zero, scene.size != bounds.size {
      scene.size = bounds.size
    }
  }

  private func updateDisplayLink() {
    if displayLink == nil, window != nil {
      let link = displayLink(target: self, selector: #selector(drawFrame(_:)))
      link.add(to: .main, forMode: .common)
      displayLink = link
      applyFrameRate()
    }
    displayLink?.isPaused = isPaused
  }

  private func applyFrameRate() {
    let rate = Float(framesPerSecond)
    displayLink?.preferredFrameRateRange = CAFrameRateRange(
      minimum: rate,
      maximum: rate,
      preferred: rate
    )
  }

  @objc private func drawFrame(_ link: CADisplayLink) {
    guard
      metalLayer.drawableSize != .zero,
      let drawable = metalLayer.nextDrawable(),
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }
    renderer.update(atTime: CACurrentMediaTime())
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    renderer.render(
      withViewport: CGRect(origin: .zero, size: metalLayer.drawableSize),
      commandBuffer: commandBuffer,
      renderPassDescriptor: pass
    )
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}
