// Zeichnet das App-Icon (1024x1024 PNG): Dokument mit Unterschrift auf blauem Verlauf.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Hintergrund: macOS-Icon-Raster (Rand 100px), Superellipse-ähnliche Rundung
let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(bgPath); ctx.setFillColor(NSColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1).cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(red: 0.30, green: 0.55, blue: 1.0, alpha: 1).cgColor,
                               NSColor(red: 0.08, green: 0.16, blue: 0.55, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// Dokument (leicht gedreht)
ctx.saveGState()
ctx.translateBy(x: 512, y: 520)
ctx.rotate(by: -0.07)
let doc = CGRect(x: -215, y: -285, width: 430, height: 570)
let docPath = CGPath(roundedRect: doc, cornerWidth: 28, cornerHeight: 28, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.4).cgColor)
ctx.addPath(docPath); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Textzeilen
ctx.setFillColor(NSColor(white: 0.80, alpha: 1).cgColor)
for (i, w) in [330.0, 330.0, 330.0, 210.0].enumerated() {
    let r = CGRect(x: -165, y: 190 - CGFloat(i) * 52, width: w, height: 18)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
}
// Unterschriftslinie
ctx.setStrokeColor(NSColor(white: 0.70, alpha: 1).cgColor)
ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: -165, y: -165)); ctx.addLine(to: CGPoint(x: 165, y: -165)); ctx.strokePath()

// Unterschrift (variable Strichstärke über viele kurze Segmente)
let pts: [CGPoint] = (0...80).map { i in
    let t = CGFloat(i) / 80
    let x = -170 + 340 * t
    let y = -105 + 70 * sin(t * 15) * (1 - t * 0.55) * (0.5 + 0.5 * cos(t * 3)) + 30 * t
    return CGPoint(x: x, y: y)
}
ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.setStrokeColor(NSColor(red: 0.07, green: 0.14, blue: 0.62, alpha: 1).cgColor)
for i in 1..<pts.count {
    let t = CGFloat(i) / CGFloat(pts.count)
    ctx.setLineWidth(10 + 8 * sin(t * 9) + (1 - t) * 4)
    ctx.move(to: pts[i - 1]); ctx.addLine(to: pts[i]); ctx.strokePath()
}
ctx.restoreGState()

// Kleiner Stift unten rechts
ctx.saveGState()
ctx.translateBy(x: 690, y: 330)
ctx.rotate(by: 0.75)
let pen = CGRect(x: -26, y: -20, width: 52, height: 300)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: NSColor.black.withAlphaComponent(0.4).cgColor)
ctx.addPath(CGPath(roundedRect: pen, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.setFillColor(NSColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1).cgColor); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.move(to: CGPoint(x: -26, y: -20)); ctx.addLine(to: CGPoint(x: 26, y: -20)); ctx.addLine(to: CGPoint(x: 0, y: -80)); ctx.closePath()
ctx.setFillColor(NSColor(red: 0.95, green: 0.85, blue: 0.7, alpha: 1).cgColor); ctx.fillPath()
ctx.move(to: CGPoint(x: -9, y: -58)); ctx.addLine(to: CGPoint(x: 9, y: -58)); ctx.addLine(to: CGPoint(x: 0, y: -80)); ctx.closePath()
ctx.setFillColor(NSColor(red: 0.07, green: 0.14, blue: 0.62, alpha: 1).cgColor); ctx.fillPath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
