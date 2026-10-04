import AppKit
import Foundation

let directory = URL(fileURLWithPath: "assets/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ size: Int) -> Data {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  let ctx = NSGraphicsContext.current!.cgContext
  ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  let background = NSBezierPath(
    roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
  NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.23, alpha: 1),
    ending: NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.12, alpha: 1))!.draw(
      in: background, angle: -60)
  NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
  background.lineWidth = 3
  background.stroke()
  let ring = NSBezierPath(ovalIn: NSRect(x: 218, y: 218, width: 588, height: 588))
  ring.lineWidth = 12
  NSColor(calibratedRed: 0.40, green: 0.93, blue: 0.76, alpha: 0.25).setStroke()
  ring.stroke()
  for blade in 0..<3 {
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: CGFloat(blade) * 2 * CGFloat.pi / 3)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: -28, y: 58))
    path.curve(
      to: NSPoint(x: 35, y: 272), controlPoint1: NSPoint(x: -115, y: 170),
      controlPoint2: NSPoint(x: -110, y: 292))
    path.curve(
      to: NSPoint(x: 158, y: 92), controlPoint1: NSPoint(x: 180, y: 260),
      controlPoint2: NSPoint(x: 232, y: 160))
    path.curve(
      to: NSPoint(x: 50, y: 26), controlPoint1: NSPoint(x: 122, y: 47),
      controlPoint2: NSPoint(x: 72, y: 44))
    path.close()
    NSGradient(
      starting: NSColor(calibratedRed: 0.43, green: 0.96, blue: 0.78, alpha: 1),
      ending: NSColor(calibratedRed: 0.12, green: 0.70, blue: 0.60, alpha: 1))!.draw(
        in: path, angle: 45)
    ctx.restoreGState()
  }
  NSColor(calibratedRed: 0.50, green: 0.99, blue: 0.82, alpha: 1).setFill()
  NSBezierPath(ovalIn: NSRect(x: 468, y: 468, width: 88, height: 88)).fill()
  NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.18, alpha: 1).setFill()
  NSBezierPath(ovalIn: NSRect(x: 493, y: 493, width: 38, height: 38)).fill()
  image.unlockFocus()
  let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
  return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
  try render(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
  try render(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
