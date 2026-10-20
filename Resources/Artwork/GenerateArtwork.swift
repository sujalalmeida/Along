import AppKit

// Original vector artwork. Rebuild PNG/ICNS assets with Scripts/generate-artwork.sh.
func png(width: Int, height: Int, scale: Int = 1, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func icon() {
    let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.19, green: 0.21, blue: 0.25, alpha: 1),
               ending: NSColor(srgbRed: 0.075, green: 0.085, blue: 0.11, alpha: 1))!.draw(in: base, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    let strip = NSBezierPath(roundedRect: NSRect(x: 150, y: 258, width: 724, height: 508), xRadius: 30, yRadius: 30)
    strip.addClip()
    for (x, width, active) in [(CGFloat(60), CGFloat(200), false), (CGFloat(302), CGFloat(340), true), (CGFloat(684), CGFloat(280), false)] {
        let card = NSBezierPath(roundedRect: NSRect(x: x, y: 262, width: width, height: 500), xRadius: 36, yRadius: 36)
        if active {
            NSGradient(starting: NSColor(srgbRed: 1, green: 0.68, blue: 0.35, alpha: 1),
                       ending: NSColor(srgbRed: 0.92, green: 0.36, blue: 0.19, alpha: 1))!.draw(in: card, angle: -90)
        } else { NSColor(srgbRed: 0.82, green: 0.84, blue: 0.86, alpha: 1).setFill(); card.fill() }
        NSColor.black.withAlphaComponent(active ? 0.12 : 0.08).setFill()
        NSBezierPath(roundedRect: NSRect(x: x + 20, y: 674, width: width - 40, height: 5), xRadius: 2, yRadius: 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent("Along.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let data = png(width: pixels, height: pixels) {
            NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            icon()
        }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try png(width: 1024, height: 1024, draw: icon).write(to: root.appendingPathComponent("AppIcon.png"))
try png(width: 640, height: 370) {
    NSColor(srgbRed: 0.96, green: 0.955, blue: 0.94, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 640, height: 370).fill()
    text("Along", x: 42, y: 306, size: 28, color: .init(white: 0.14, alpha: 1), weight: .semibold)
    text("Drag Along into Applications.", x: 43, y: 278, size: 15, color: .init(white: 0.4, alpha: 1))
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 292, y: 170)); arrow.line(to: NSPoint(x: 368, y: 170))
    arrow.move(to: NSPoint(x: 356, y: 180)); arrow.line(to: NSPoint(x: 368, y: 170)); arrow.line(to: NSPoint(x: 356, y: 160))
    arrow.lineWidth = 2.5; arrow.lineCapStyle = .round
    NSColor(srgbRed: 0.88, green: 0.40, blue: 0.22, alpha: 1).setStroke(); arrow.stroke()
    text("Then open Along from Applications.", x: 43, y: 60, size: 14, color: .init(white: 0.4, alpha: 1))
    text("Free and open source.  •  macOS 13 or later", x: 43, y: 38, size: 12, color: .init(white: 0.5, alpha: 1))
}.write(to: root.appendingPathComponent("InstallerBackground.png"))
