import AppKit
import DockOverlayKit
import DrowsyDockCore
import os

/// Shows the cat on the Dock: the cat in a small window at the perch, and the veil and the crowd
/// effect in a second window over the whole Dock.
@MainActor
final class MascotOverlay {
  /// The size of the cat's window, which `DockTracker` places at the perch.
  static let spriteSize = CatRenderer.canvasSize

  private static let canvasMargin: CGFloat = 48

  private static let logger = Logger(subsystem: "com.drowsydock.DrowsyDock", category: "mascot")

  private let catScene = MascotScene()
  private let catWindow: OverlayWindow
  private let canvasScene = DockCanvasScene()
  private let canvasWindow: OverlayWindow
  private var presentation = OverlayPresentation.hidden
  private var mood: MascotMood?
  private var isCrowdEffectPlaying = false

  init() {
    let catHost = SceneHostView(scene: catScene)
    let canvasHost = SceneHostView(scene: canvasScene)
    catScene.host = catHost
    canvasScene.host = canvasHost
    catWindow = OverlayWindow(contentView: catHost ?? Self.noMetalView())
    canvasWindow = OverlayWindow(contentView: canvasHost ?? Self.noMetalView())
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

  /// Plays the crowd effect over the Dock's icons. Returns `false`, playing nothing, when the
  /// overlay isn't fully shown, because nobody would see it.
  func playCrowdEffect() -> Bool {
    guard mood != nil, case .shown(_, let dock) = presentation else { return false }
    isCrowdEffectPlaying = true
    update()
    let canvas = Self.canvasFrame(around: dock)
    let icons = dock.iconFramesAlongDock.map { $0.offsetBy(dx: -canvas.minX, dy: -canvas.minY) }
    canvasScene.playCrowdEffect(over: icons, orientation: dock.orientation) { [weak self] in
      self?.isCrowdEffectPlaying = false
      self?.update()
    }
    return true
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
      catScene.show(mood, facing: nil)
      return
    case .shown(let shownPerch, let shownDock):
      (perch, dock, isFaded) = (shownPerch, shownDock, false)
    case .fadedOut(let fadedPerch, let fadedDock):
      (perch, dock, isFaded) = (fadedPerch, fadedDock, true)
    }

    catScene.setActive(!isFaded)
    catScene.show(mood, facing: perch.facing)
    place(catWindow, at: perch.frame, isFaded: isFaded)

    if isFaded {
      stopCrowdEffect()
    }
    let pose = MascotPose(for: mood.settledState)
    guard pose.veilOpacity > 0 || isCrowdEffectPlaying else {
      canvasWindow.hide(fading: true)
      return
    }
    let canvas = Self.canvasFrame(around: dock)
    canvasScene.layOut(
      background: dock.backgroundFrame.offsetBy(dx: -canvas.minX, dy: -canvas.minY),
      cornerRadius: dock.backgroundCornerRadius
    )
    canvasScene.setVeil(opacity: pose.veilOpacity)
    place(canvasWindow, at: canvas, isFaded: isFaded)
  }

  private static func canvasFrame(around dock: DockGeometry) -> CGRect {
    dock.backgroundFrame.insetBy(dx: -canvasMargin, dy: -canvasMargin)
      .intersection(dock.screenFrame)
  }

  private func stopCrowdEffect() {
    isCrowdEffectPlaying = false
    canvasScene.stopCrowdEffect()
  }

  private func place(_ window: OverlayWindow, at frame: CGRect, isFaded: Bool) {
    if isFaded {
      window.fadeOut(at: frame)
    } else {
      window.show(at: frame)
    }
  }

  private func hide() {
    stopCrowdEffect()
    catScene.setActive(false)
    catWindow.hide()
    canvasWindow.hide()
  }

  // Every Mac that runs macOS 14 has a Metal device.
  private static func noMetalView() -> NSView {
    logger.error("No Metal device, so the cat can't be drawn")
    return NSView()
  }
}
