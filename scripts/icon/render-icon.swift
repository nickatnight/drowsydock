// Renders an SVG into a macOS .iconset folder, for iconutil.
//
// Usage: swift scripts/icon/render-icon.swift <icon.svg> <out.iconset>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  FileHandle.standardError.write(Data("usage: render-icon.swift <icon.svg> <out.iconset>\n".utf8))
  exit(64)
}
let source = URL(fileURLWithPath: arguments[1])
let iconset = URL(fileURLWithPath: arguments[2])
guard let svg = NSImage(contentsOf: source) else {
  FileHandle.standardError.write(Data("render-icon: can't read \(source.path)\n".utf8))
  exit(1)
}

func write(pixels: Int, to name: String) throws {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { throw CocoaError(.fileWriteUnknown) }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try png.write(to: iconset.appendingPathComponent(name))
}

do {
  try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
  for points in [16, 32, 128, 256, 512] {
    try write(pixels: points, to: "icon_\(points)x\(points).png")
    try write(pixels: points * 2, to: "icon_\(points)x\(points)@2x.png")
  }
} catch {
  FileHandle.standardError.write(Data("render-icon: \(error)\n".utf8))
  exit(1)
}
