import CoreGraphics
import Foundation
import Metal
import SpriteKit

/// Draws a SpriteKit scene into a Metal texture the way `SceneHostView` draws it on screen, at a
/// scene time the test sets: 2 pixels per point, on the system's default Metal device.
///
/// Time only moves when the test calls `advance(by:)`, in steps of 1/60 s. Between steps the main
/// queue runs, because SpriteKit delivers `SKAction.run(_:queue:)` blocks there, as it does
/// between frames in the app.
@MainActor
final class OffscreenRenderer {
  static let scale = 2

  private static let step = 1.0 / 60

  let scene: SKScene
  private(set) var time: TimeInterval = 0

  private let device: any MTLDevice
  private let commandQueue: any MTLCommandQueue
  private let renderer: SKRenderer

  /// Starts drawing `scene` at scene time 0. Pass `size` for a scene whose size follows its view's,
  /// such as `DockCanvasScene`.
  init(scene: SKScene, size: CGSize? = nil) {
    // Every Mac that runs macOS 14 has a Metal device.
    device = MTLCreateSystemDefaultDevice()!
    commandQueue = device.makeCommandQueue()!
    renderer = SKRenderer(device: device)
    self.scene = scene
    if let size, scene.size != size {
      scene.size = size
    }
    renderer.scene = scene
    renderer.update(atTime: time)
  }

  /// Moves scene time on by `seconds`.
  func advance(by seconds: TimeInterval) {
    Self.advance([self], by: seconds)
  }

  /// Moves several renderers' scene time on together, step by step, so that work one scene sends
  /// to the main queue lands between the same frames for all of them.
  static func advance(_ renderers: [OffscreenRenderer], by seconds: TimeInterval) {
    guard let first = renderers.first else { return }
    let end = first.time + seconds
    while first.time < end - 1e-9 {
      let time = min(first.time + step, end)
      for renderer in renderers {
        renderer.time = time
        renderer.renderer.update(atTime: time)
      }
      drainMainQueue()
    }
  }

  /// Runs the work already waiting on the main queue, such as SpriteKit completion blocks and
  /// main-actor tasks that a test clock has just woken.
  static func drainMainQueue() {
    RunLoop.main.run(until: Date())
  }

  /// Returns the frame at the current time, drawn over `backdrop`, an opaque RGB colour. Pass `nil`
  /// to keep the scene's transparency, for compositing.
  func render(over backdrop: (red: UInt8, green: UInt8, blue: UInt8)?) -> Bitmap {
    let width = Int(scene.size.width) * Self.scale
    let height = Int(scene.size.height) * Self.scale
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .managed
    // A texture of a valid size and format, and a command buffer from a live queue.
    let texture = device.makeTexture(descriptor: descriptor)!
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor =
      backdrop.map {
        MTLClearColor(
          red: Double($0.red) / 255,
          green: Double($0.green) / 255,
          blue: Double($0.blue) / 255,
          alpha: 1
        )
      } ?? MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    renderer.render(
      withViewport: CGRect(x: 0, y: 0, width: width, height: height),
      commandBuffer: commandBuffer,
      renderPassDescriptor: pass
    )
    let blit = commandBuffer.makeBlitCommandEncoder()!
    blit.synchronize(resource: texture)
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    var bgra = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(
      &bgra,
      bytesPerRow: width * 4,
      from: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0
    )
    var rgba = bgra
    for start in stride(from: 0, to: rgba.count, by: 4) {
      rgba[start] = bgra[start + 2]
      rgba[start + 2] = bgra[start]
    }
    return Bitmap(width: width, height: height, pixels: rgba)
  }
}
