import AppKit

/// The Claude Code mascot, drawn from the terminal half-block art:
///
///      ▐▛███▜▌
///     ▝▜█████▛▘
///       ▘▘ ▝▝
///
/// Each grid cell is a terminal quadrant, so it is twice as tall as it is wide.
enum Clawd {
    static let orange = NSColor(srgbRed: 215 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)

    private static let grid = [
        "...XXXXXXXXXXXX...",
        "...XX.XXXXXX.XX...",
        ".XXXXXXXXXXXXXXXX.",
        "...XXXXXXXXXXXX...",
        "....X.X....X.X....",
    ]

    static var columns: Int { grid[0].count }
    static var rows: Int { grid.count }

    /// Fills the mascot into `rect` (flipped coordinates), keeping its aspect ratio.
    static func draw(in rect: NSRect, color: NSColor = orange) {
        let pixel = min(rect.width / CGFloat(columns), rect.height / CGFloat(rows * 2))
        let origin = NSPoint(
            x: rect.midX - pixel * CGFloat(columns) / 2,
            y: rect.midY - pixel * CGFloat(rows)
        )
        let path = NSBezierPath()
        for (y, row) in grid.enumerated() {
            for (x, cell) in row.enumerated() where cell == "X" {
                path.appendRect(NSRect(
                    x: origin.x + CGFloat(x) * pixel,
                    y: origin.y + CGFloat(y) * pixel * 2,
                    width: pixel,
                    height: pixel * 2
                ))
            }
        }
        color.setFill()
        path.fill()
    }

    static func image(pixel: CGFloat, color: NSColor = orange) -> NSImage {
        let size = NSSize(width: CGFloat(columns) * pixel, height: CGFloat(rows * 2) * pixel)
        return NSImage(size: size, flipped: true) { rect in
            draw(in: rect, color: color)
            return true
        }
    }
}
