import AppKit

// Renders the 1024px app icon: the Clawd mascot on a cream rounded square.
let side = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
// Flip so Clawd.draw's top-down rows render the right way up.
context.cgContext.translateBy(x: 0, y: CGFloat(side))
context.cgContext.scaleBy(x: 1, y: -1)

let canvas = NSRect(x: 0, y: 0, width: side, height: side)
let tile = canvas.insetBy(dx: 100, dy: 100)
NSColor(srgbRed: 0.96, green: 0.94, blue: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
Clawd.draw(in: tile.insetBy(dx: 110, dy: 110))

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
