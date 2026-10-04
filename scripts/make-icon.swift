// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let outputDir = URL(fileURLWithPath: "Resources")
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")

/// macOS icon body: 824 pt rounded square centered on a 1024 canvas, with continuous (squircle) corners.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5 // superellipse exponent: close to Apple's continuous corners
    let a = rect.width / 2, b = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = center.x + a * (cosT >= 0 ? 1 : -1) * pow(abs(cosT), 2 / n)
        let y = center.y + b * (sinT >= 0 ? 1 : -1) * pow(abs(sinT), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Four-pointed sparkle with concave sides.
func sparkle(center: CGPoint, radius: CGFloat, waist: CGFloat = 0.18) -> CGPath {
    let path = CGMutablePath()
    let points = (0..<4).map { i -> CGPoint in
        let angle = CGFloat(i) * .pi / 2 + .pi / 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    path.move(to: points[0])
    for i in 0..<4 {
        let next = points[(i + 1) % 4]
        path.addQuadCurve(to: next, control: CGPoint(
            x: center.x + (points[i].x - center.x + next.x - center.x) * waist,
            y: center.y + (points[i].y - center.y + next.y - center.y) * waist
        ))
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / canvas, y: size / canvas)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)
    let space = CGColorSpaceCreateDeviceRGB()

    // Drop shadow under the body, like system icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: teal at the top to deep blue at the bottom.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.80, blue: 0.70, alpha: 1),
        CGColor(red: 0.09, green: 0.47, blue: 0.86, alpha: 1),
        CGColor(red: 0.12, green: 0.25, blue: 0.62, alpha: 1),
    ] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft light from the top.
    let gloss = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 500)
    let ringRadius: CGFloat = 232
    let ringWidth: CGFloat = 64

    // Ring track.
    ctx.setLineWidth(ringWidth)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    // Used space: three quarters of the ring, from the top clockwise, with a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(red: 0.02, green: 0.12, blue: 0.35, alpha: 0.35))
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 - 1.5 * .pi, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // Sparkles: a big one in the middle, a small one in the ring's open (freed) part.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: CGColor(red: 0.02, green: 0.12, blue: 0.35, alpha: 0.3))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(sparkle(center: center, radius: 128))
    ctx.fillPath()
    ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 1))
    let gapAngle: CGFloat = .pi * 3 / 4
    ctx.addPath(sparkle(center: CGPoint(x: center.x + cos(gapAngle) * ringRadius, y: center.y + sin(gapAngle) * ringRadius), radius: 50))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(points * scale)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let data = drawIcon(size: pixels).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: outputDir.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
