// Draws the FnVoice icon and produces FnVoice/Resources/AppIcon.icns.
// Usage: swift tools/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // macOS shape: 824 pt rounded square centred in 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.32))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.20, green: 0.22, blue: 0.75, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Blue to indigo gradient
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.36, green: 0.62, blue: 1.00, alpha: 1),
        CGColor(red: 0.26, green: 0.36, blue: 0.95, alpha: 1),
        CGColor(red: 0.30, green: 0.18, blue: 0.78, alpha: 1)
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 260, y: 924), end: CGPoint(x: 764, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft highlight at the top
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.26), CGColor(gray: 1, alpha: 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 360, y: 900), endRadius: 620, options: [])
    ctx.restoreGState()

    // Light rim
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 3, dy: 3), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // Sound wave: five rounded bars
    let heights: [CGFloat] = [170, 370, 520, 300, 210]
    let barWidth: CGFloat = 70
    let gap: CGFloat = 46
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (1024 - total) / 2
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(red: 0.08, green: 0.05, blue: 0.40, alpha: 0.35))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    for height in heights {
        let bar = CGRect(x: x, y: 512 - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        x += barWidth + gap
    }
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build-icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset.deletingLastPathComponent())
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let rep = drawIcon(size: CGFloat(points * scale))
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}

let output = root.appendingPathComponent("FnVoice/Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Icon created: \(output.path)" : "iconutil failed")
