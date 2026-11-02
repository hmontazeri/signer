import AppKit
import PDFKit

enum InkColor: String, CaseIterable, Identifiable {
    case blue = "Blau"
    case black = "Schwarz"

    var id: String { rawValue }

    var cgColor: CGColor {
        switch self {
        case .blue: return CGColor(red: 0.07, green: 0.14, blue: 0.55, alpha: 1)
        case .black: return CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        }
    }

    var hex: String {
        switch self {
        case .blue: return "#12238c"
        case .black: return "#0d0d12"
        }
    }
}

struct InkStroke {
    var points: [CGPoint]
    var widths: [CGFloat]
    var color: CGColor
    var group: Int
}

enum Ink {
    /// Strichbreite aus der Zeichengeschwindigkeit: langsam = dicker, schnell = dünner.
    static func widths(points: [CGPoint], times: [Double], base: CGFloat) -> [CGFloat] {
        var out: [CGFloat] = []
        var w = base
        for i in points.indices {
            var target = base
            if i > 0 {
                let dt = max(times[i] - times[i - 1], 0.001)
                let v = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) / dt
                target = base * (1.35 - 0.85 * min(v, 900) / 900)
            }
            w = i == 0 ? target : w * 0.7 + target * 0.3
            out.append(w)
        }
        return out
    }

    static func draw(_ strokes: [InkStroke], in ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for s in strokes {
            let p = s.points, w = s.widths
            guard p.count == w.count, !p.isEmpty else { continue }
            ctx.setStrokeColor(s.color)
            ctx.setFillColor(s.color)
            if p.count == 1 {
                let r = w[0] / 2
                ctx.fillEllipse(in: CGRect(x: p[0].x - r, y: p[0].y - r, width: w[0], height: w[0]))
                continue
            }
            func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            let n = p.count
            if n == 2 {
                ctx.setLineWidth(w[1])
                ctx.move(to: p[0]); ctx.addLine(to: p[1]); ctx.strokePath()
                continue
            }
            ctx.setLineWidth(w[0])
            ctx.move(to: p[0]); ctx.addLine(to: mid(p[0], p[1])); ctx.strokePath()
            for i in 1..<(n - 1) {
                ctx.setLineWidth(w[i])
                ctx.move(to: mid(p[i - 1], p[i]))
                ctx.addQuadCurve(to: mid(p[i], p[i + 1]), control: p[i])
                ctx.strokePath()
            }
            ctx.setLineWidth(w[n - 1])
            ctx.move(to: mid(p[n - 2], p[n - 1])); ctx.addLine(to: p[n - 1]); ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

/// Alle Striche einer Seite (Seitenkoordinaten), plus der Strich, der gerade gezeichnet wird.
final class PageInk {
    var strokes: [InkStroke] = []
    var texts: [TextItem] = []
    var live: InkStroke?
}

/// Eingetippter Text (Datum, Ort …). `origin` ist die untere linke Ecke in Seitenkoordinaten.
struct TextItem {
    var id = UUID()
    var origin: CGPoint
    var text: String
    var size: CGFloat
    var color: CGColor
    var group: Int

    static func font(_ size: CGFloat) -> NSFont { NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size) }

    var attributed: NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: TextItem.font(size),
            .foregroundColor: NSColor(cgColor: color) ?? NSColor.black,
        ])
    }

    var rect: CGRect { CGRect(origin: origin, size: attributed.size()) }
}

extension Ink {
    static func drawTexts(_ items: [TextItem], in ctx: CGContext) {
        guard !items.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for t in items { t.attributed.draw(at: t.origin) }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Gestrichelter Rahmen: hier landet die Unterschrift vom iPhone.
    static func drawTarget(_ rect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.10).cgColor)
        ctx.setStrokeColor(NSColor.systemOrange.cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }
}
