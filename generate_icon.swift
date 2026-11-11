import AppKit
import Foundation

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.22

    // Background rounded squircle gradient
    let bgPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.96, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.78, alpha: 1.0)
    ])!
    gradient.draw(in: bgPath, angle: -65)

    // Inner calendar sheet
    let sheetRect = cardRect.insetBy(dx: size * 0.12, dy: size * 0.12)
    let sheetPath = NSBezierPath(roundedRect: sheetRect, xRadius: size * 0.12, yRadius: size * 0.12)
    NSColor.white.withAlphaComponent(0.95).setFill()
    sheetPath.fill()

    // Red top banner
    let bannerHeight = sheetRect.height * 0.28
    let bannerRect = NSRect(
        x: sheetRect.minX,
        y: sheetRect.maxY - bannerHeight,
        width: sheetRect.width,
        height: bannerHeight
    )
    NSGraphicsContext.saveGraphicsState()
    sheetPath.addClip()
    NSColor(calibratedRed: 0.89, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
    bannerRect.fill()
    NSGraphicsContext.restoreGraphicsState()

    // "12.12" text on sheet
    let titleFont = NSFont.systemFont(ofSize: size * 0.21, weight: .heavy)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.24, alpha: 1.0)
    ]
    let text = "12.12" as NSString
    let textSize = text.size(withAttributes: titleAttrs)
    let textPoint = NSPoint(
        x: sheetRect.midX - textSize.width / 2,
        y: sheetRect.minY + (sheetRect.height - bannerHeight - textSize.height) / 2
    )
    text.draw(at: textPoint, withAttributes: titleAttrs)

    // Header label "备考"
    let headerFont = NSFont.systemFont(ofSize: size * 0.105, weight: .bold)
    let headerAttrs: [NSAttributedString.Key: Any] = [
        .font: headerFont,
        .foregroundColor: NSColor.white
    ]
    let header = "备考" as NSString
    let hSize = header.size(withAttributes: headerAttrs)
    header.draw(
        at: NSPoint(x: bannerRect.midX - hSize.width / 2, y: bannerRect.midY - hSize.height / 2),
        withAttributes: headerAttrs
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let outputDir = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in specs {
    if let data = renderIcon(pixelSize: px) {
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
        try data.write(to: url)
    }
}
