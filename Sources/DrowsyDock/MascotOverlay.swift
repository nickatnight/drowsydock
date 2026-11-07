import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// Shows the cat on the Dock: the cat in a small window at the perch, and the veil in a second
/// window over the whole Dock.
///
/// Two windows rather than one Dock-sized window, so that an animating cat redraws only its own
/// small canvas. The Dock window is ordered out whenever it has nothing to draw.
@MainActor
final class MascotOverlay {
  /// The size of the cat's window, which `DockTracker` places at the perch.
  static let spriteSize = CatRenderer.canvasSize

  // Room around the Dock for effects that rise above the icons.
  private static let canvasMargin: CGFloat = 48

  // The spec's cap for looping states. Short one-shots run at the same rate.
  private static let framesPerSecond = 30

  private let catScene = MascotScene()
  private let catWindow: OverlayWindow
  private let canvasScene = DockCanvasScene()
  private let canvasWindow: OverlayWindow
  private var presentation = OverlayPresentation.hidden
  private var mood: MascotMood?

  init() {
    catWindow = OverlayWindow(contentView: Self.transparentView(presenting: catScene))
    canvasWindow = OverlayWindow(contentView: Self.transparentView(presenting: canvasScene))
  }

  /// Moves, fades or hides the overlay as the Dock tracker decides.
  func present(_ presentation: OverlayPresentation) {
    self.presentation = presentation
    update()
  }

  /// Shows `mood`, or nothing when it is `nil` (no battery).
  func show(_ mood: MascotMood?) {
    self.mood = mood
    update()
  }

  private func update() {
    guard let mood else {
      hide()
      return
    }
    let perch: DockPerch
    let dock: DockGeometry
    let isFaded: Bool
    switch presentation {
    case .hidden:
      hide()
      return
    case .shown(let shownPerch, let shownDock):
      (perch, dock, isFaded) = (shownPerch, shownDock, false)
    case .fadedOut(let fadedPerch, let fadedDock):
      (perch, dock, isFaded) = (fadedPerch, fadedDock, true)
    }

    let pose = MascotPose(for: mood.settledState)
    catScene.rest(in: mood.settledState, facing: perch.facing)
    catScene.setActive(!isFaded)
    place(catWindow, at: perch.frame, isFaded: isFaded)

    guard pose.veilOpacity > 0 else {
      canvasWindow.hide()
      return
    }
    let canvas = dock.frame.insetBy(dx: -Self.canvasMargin, dy: -Self.canvasMargin)
      .intersection(dock.screenFrame)
    canvasScene.layOut(dockFrame: dock.frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY))
    canvasScene.setVeil(opacity: pose.veilOpacity)
    place(canvasWindow, at: canvas, isFaded: isFaded)
  }

  private func place(_ window: OverlayWindow, at frame: CGRect, isFaded: Bool) {
    if isFaded {
      window.fadeOut(at: frame)
    } else {
      window.show(at: frame)
    }
  }

  private func hide() {
    catScene.setActive(false)
    catWindow.hide()
    canvasWindow.hide()
  }

  private static func transparentView(presenting scene: SKScene) -> SKView {
    let view = SKView()
    view.allowsTransparency = true
    view.preferredFramesPerSecond = framesPerSecond
    view.presentScene(scene)
    return view
  }
}
