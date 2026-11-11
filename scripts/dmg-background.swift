import AppKit

// Coordinates match the Finder window and icon positions in package-dmg.sh.
let size = NSSize(width: 660, height: 440)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 660, pixelsHigh: 440,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    fatalError("Unable to allocate background bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.99, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(
        in: NSRect(x: 20, y: y, width: 620, height: 44),
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    )
}

text("Disk Awake", y: 355, font: .systemFont(ofSize: 30, weight: .bold), color: .black)
text("Drag the app to Applications to install", y: 310,
     font: .systemFont(ofSize: 19, weight: .medium), color: .darkGray)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 285, y: 235))
arrow.line(to: NSPoint(x: 375, y: 235))
arrow.move(to: NSPoint(x: 357, y: 253))
arrow.line(to: NSPoint(x: 375, y: 235))
arrow.line(to: NSPoint(x: 357, y: 217))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
NSColor.systemBlue.setStroke()
arrow.stroke()
text("Kéo ứng dụng vào Applications để cài đặt", y: 70,
     font: .systemFont(ofSize: 18, weight: .medium), color: .darkGray)
NSGraphicsContext.restoreGraphicsState()
guard CommandLine.arguments.count == 2,
      let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Usage: swift dmg-background.swift output.png")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
