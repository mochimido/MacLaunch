import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 512)
        transform.concat()
        let outer = NSBezierPath(roundedRect: NSRect(x: 26, y: 26, width: 460, height: 460), xRadius: 108, yRadius: 108)
        NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.30, alpha: 1).setFill()
        outer.fill()
        for (index, point) in [NSPoint(x: 121, y: 272), NSPoint(x: 272, y: 272), NSPoint(x: 121, y: 121), NSPoint(x: 272, y: 121)].enumerated() {
            (index == 1 ? NSColor(calibratedRed: 0.76, green: 0.88, blue: 0.66, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)).setFill()
            NSBezierPath(roundedRect: NSRect(origin: point, size: NSSize(width: 119, height: 119)), xRadius: 25, yRadius: 25).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
