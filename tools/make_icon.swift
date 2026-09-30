// Draws the app icon and writes an .icns. Usage: swift tools/make_icon.swift <output.icns>

import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Background squircle (macOS icon grid: 824pt body inset in a 1024 canvas).
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(calibratedWhite: 0.20, alpha: 1), NSColor(calibratedWhite: 0.08, alpha: 1)])!
        .draw(in: bg, angle: -90)

    func symbol(_ name: String, points: CGFloat, colors: [NSColor], in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let fit = min(rect.width / image.size.width, rect.height / image.size.height)
        let w = image.size.width * fit, h = image.size.height * fit
        image.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    // Custom flame: an outer tongue leaning right with a flickering left lick, plus a hot inner core.
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

    let outer = NSBezierPath()
    outer.move(to: pt(500, 205))
    outer.curve(to: pt(292, 430), controlPoint1: pt(380, 205), controlPoint2: pt(292, 300))
    outer.curve(to: pt(372, 640), controlPoint1: pt(292, 530), controlPoint2: pt(335, 590))
    outer.curve(to: pt(355, 548), controlPoint1: pt(360, 610), controlPoint2: pt(352, 580))   // left lick
    outer.curve(to: pt(470, 690), controlPoint1: pt(400, 600), controlPoint2: pt(445, 640))
    outer.curve(to: pt(560, 870), controlPoint1: pt(510, 760), controlPoint2: pt(500, 830))   // main tip
    outer.curve(to: pt(700, 520), controlPoint1: pt(680, 790), controlPoint2: pt(720, 640))
    outer.curve(to: pt(500, 205), controlPoint1: pt(690, 330), controlPoint2: pt(610, 205))
    outer.close()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.10, alpha: 1),
        NSColor(calibratedRed: 0.86, green: 0.16, blue: 0.12, alpha: 1),
    ])!.draw(in: outer, angle: 90)

    let inner = NSBezierPath()
    inner.move(to: pt(505, 250))
    inner.curve(to: pt(400, 390), controlPoint1: pt(440, 250), controlPoint2: pt(400, 310))
    inner.curve(to: pt(520, 620), controlPoint1: pt(400, 480), controlPoint2: pt(470, 540))
    inner.curve(to: pt(610, 400), controlPoint1: pt(600, 560), controlPoint2: pt(615, 480))
    inner.curve(to: pt(505, 250), controlPoint1: pt(605, 310), controlPoint2: pt(565, 250))
    inner.close()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.80, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.30, alpha: 1),
    ])!.draw(in: inner, angle: 90)

    // Dark ring behind the gear so it reads as a separate badge on top of the flame.
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 545 * s, y: 155 * s, width: 280 * s, height: 280 * s)).fill()
    symbol("gearshape.fill", points: 200,
           colors: [NSColor(calibratedWhite: 0.92, alpha: 1)],
           in: NSRect(x: 560 * s, y: 170 * s, width: 250 * s, height: 250 * s))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(task.terminationStatus)
