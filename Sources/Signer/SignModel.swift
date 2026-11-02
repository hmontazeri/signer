import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

final class SignModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case mouse = "Maus"
        case phone = "iPhone"
        case text = "Text"
        var id: String { rawValue }
    }

    struct Target { var id: Int; var page: Int; var rect: CGRect }

    @Published var document: PDFDocument?
    @Published var fileURL: URL?
    @Published var currentPage = 0
    @Published var signedPages = Set<Int>()
    @Published var mode: Mode = .mouse
    @Published var inkColor = InkColor.blue
    @Published var penWidth: CGFloat = 1.8
    @Published var boxWidth: CGFloat = 210
    @Published var textSize: CGFloat = 11
    var pendingText: String?
    @Published var target: Target?
    @Published var phoneLastSeen: Date?
    @Published var serverReady = false
    @Published var message: String?
    @Published var showPhone = false { didSet { if showPhone { ensureServer() } } }

    weak var pdfView: SigPDFView?
    let server = PhoneServer()

    private var inks: [Int: PageInk] = [:]
    private var nextGroup = 1
    private var nextTargetID = 1
    private var lastBoxCenter: CGPoint?
    private var live: (page: PDFPage, points: [CGPoint], times: [Double])?

    init() {
        server.handler = { [weak self] req in
            guard let self else { return .text("gone", status: 500) }
            return await self.handle(req)
        }
        server.onReady = { [weak self] in self?.serverReady = true }
    }

    private var serverStarted = false
    /// Der Server läuft erst, wenn iPhone-Modus oder QR-Fenster gebraucht werden.
    func ensureServer() {
        guard !serverStarted else { return }
        serverStarted = true
        server.start()
    }

    var phoneURL: String? {
        guard serverReady, let ip = PhoneServer.lanIPv4() else { return nil }
        return "http://\(ip):\(server.port)/?t=\(server.token)"
    }

    var pageCount: Int { document?.pageCount ?? 0 }
    var phoneConnected: Bool { phoneLastSeen.map { Date().timeIntervalSince($0) < 4 } ?? false }

    // MARK: Datei

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.pdf]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { open(url) }
    }

    func open(_ url: URL) {
        guard let doc = PDFDocument(url: url) else { message = "Konnte PDF nicht öffnen."; return }
        clearTarget()
        inks = [:]
        signedPages = []
        nextGroup = 1
        lastBoxCenter = nil
        fileURL = url
        document = doc
        currentPage = 0
        message = nil
    }

    func exportPanel() {
        guard let url = fileURL else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.pdf]
        p.directoryURL = url.deletingLastPathComponent()
        p.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + " - unterschrieben.pdf"
        guard p.runModal() == .OK, let out = p.url else { return }
        do {
            try export(to: out)
            message = "Gespeichert: \(out.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            message = "Export fehlgeschlagen."
        }
    }

    /// Schreibt eine neue PDF: Originalseiten unverändert, Unterschriften als Vektoren eingebrannt.
    func export(to url: URL) throws {
        guard let doc = document else { return }
        var first = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &first, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            var box = page.bounds(for: .mediaBox)
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            if let ref = page.pageRef { ctx.drawPDFPage(ref) }
            if let ink = inks[i] { Ink.draw(ink.strokes, in: ctx); Ink.drawTexts(ink.texts, in: ctx) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    // MARK: Navigation

    func go(to index: Int) {
        guard let doc = document, let page = doc.page(at: index) else { return }
        pdfView?.go(to: page)
        // Im iPhone-Modus wandert das Zielfeld an dieselbe Stelle der neuen Seite.
        guard mode == .phone, index != target?.page else { return }
        clearTarget()
        if !signedPages.contains(index), let c = lastBoxCenter { placeTarget(on: page, center: c) }
    }

    func step(_ d: Int) { go(to: min(max(currentPage + d, 0), pageCount - 1)) }

    /// Beim Scrollen: nur die aktuelle Seite merken.
    func pageChanged(to index: Int) {
        guard index != currentPage, index >= 0 else { return }
        currentPage = index
    }

    func modeChanged() {
        if mode == .phone { ensureServer() } else { clearTarget() }
        if mode == .phone, target == nil, let c = lastBoxCenter, !signedPages.contains(currentPage),
           let page = document?.page(at: currentPage) {
            placeTarget(on: page, center: c)
        }
    }

    // MARK: Text

    func textItem(on pageIndex: Int, at p: CGPoint) -> TextItem? {
        inks[pageIndex]?.texts.last { $0.rect.insetBy(dx: -4, dy: -4).contains(p) }
    }

    func removeText(_ id: UUID, pageIndex: Int) {
        inks[pageIndex]?.texts.removeAll { $0.id == id }
        refresh(pageIndex)
    }

    /// Legt Text ab (neu oder als bearbeitete Fassung von `existing`). Leerer Text löscht.
    func commitText(pageIndex: Int, existing: TextItem?, origin: CGPoint, text: String) {
        let ink = ink(for: pageIndex)
        if let e = existing { ink.texts.removeAll { $0.id == e.id } }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var group = existing?.group ?? 0
            if existing == nil { group = nextGroup; nextGroup += 1 }
            ink.texts.append(TextItem(origin: existing?.origin ?? origin, text: trimmed,
                                      size: existing?.size ?? textSize,
                                      color: existing?.color ?? inkColor.cgColor, group: group))
        }
        refresh(pageIndex)
    }

    func insertDate() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        pendingText = f.string(from: Date())
        message = "Datum bereit – klicke auf die Stelle im Dokument."
    }

    // MARK: Zeichnen mit der Maus

    func mouseDown(page: PDFPage, at p: CGPoint, time: Double) {
        switch mode {
        case .mouse:
            live = (page, [p], [time])
            updateLive()
        case .phone:
            placeTarget(on: page, center: p)
        case .text:
            break
        }
    }

    func mouseDragged(page: PDFPage, at p: CGPoint, time: Double) {
        switch mode {
        case .mouse:
            guard live != nil else { return }
            live!.points.append(p)
            live!.times.append(time)
            updateLive()
        case .phone:
            if let t = target, t.page == document?.index(for: page) {
                moveTarget(to: p)
            }
        case .text:
            break
        }
    }

    func mouseUp() {
        switch mode {
        case .mouse:
            guard let l = live, let idx = document?.index(for: l.page) else { return }
            let ann = ink(for: idx)
            if var s = ann.live {
                s.group = nextGroup
                nextGroup += 1
                ann.strokes.append(s)
            }
            ann.live = nil
            live = nil
            refresh(idx)
        case .phone:
            if target != nil { target!.id = nextID() }
        case .text:
            break
        }
    }

    private func updateLive() {
        guard let l = live, let idx = document?.index(for: l.page) else { return }
        let ann = ink(for: idx)
        ann.live = InkStroke(points: l.points,
                             widths: Ink.widths(points: l.points, times: l.times, base: penWidth),
                             color: inkColor.cgColor, group: 0)
        refresh(idx)
    }

    // MARK: Seiten-Annotationen

    private func ink(for index: Int) -> PageInk {
        if let a = inks[index] { return a }
        let a = PageInk()
        inks[index] = a
        return a
    }

    private func refresh(_ index: Int) {
        if let i = inks[index], !(i.strokes.isEmpty && i.texts.isEmpty) { signedPages.insert(index) } else { signedPages.remove(index) }
        repaint()
    }

    func repaint() { pdfView?.overlay?.needsDisplay = true }

    /// Wird vom Overlay aufgerufen; `ctx` hat bereits die Seiten→Ansicht-Transformation.
    func paintOverlay(_ ctx: CGContext, pageIndex: Int) {
        if let ink = inks[pageIndex] {
            Ink.draw(ink.strokes + (ink.live.map { [$0] } ?? []), in: ctx)
            Ink.drawTexts(ink.texts, in: ctx)
        }
        if let t = target, t.page == pageIndex { Ink.drawTarget(t.rect, in: ctx) }
    }

    func undo() {
        guard let ann = inks[currentPage] else { return }
        guard let g = (ann.strokes.map(\.group) + ann.texts.map(\.group)).max() else { return }
        ann.strokes.removeAll { $0.group == g }
        ann.texts.removeAll { $0.group == g }
        refresh(currentPage)
    }

    func clearPage() {
        guard let ann = inks[currentPage] else { return }
        ann.strokes = []
        ann.texts = []
        refresh(currentPage)
    }

    // MARK: iPhone-Zielfeld

    private func nextID() -> Int { defer { nextTargetID += 1 }; return nextTargetID }

    private func rect(on page: PDFPage, center: CGPoint) -> CGRect {
        let mb = page.bounds(for: .mediaBox)
        let w = boxWidth, h = boxWidth / 3
        var r = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        r.origin.x = min(max(r.minX, mb.minX + 4), mb.maxX - w - 4)
        r.origin.y = min(max(r.minY, mb.minY + 4), mb.maxY - h - 4)
        return r
    }

    func placeTarget(on page: PDFPage, center: CGPoint) {
        guard let idx = document?.index(for: page) else { return }
        let r = rect(on: page, center: center)
        target = Target(id: nextID(), page: idx, rect: r)
        lastBoxCenter = CGPoint(x: r.midX, y: r.midY)
        repaint()
    }

    private func moveTarget(to center: CGPoint) {
        guard let t = target, let page = document?.page(at: t.page) else { return }
        let r = rect(on: page, center: center)
        target!.rect = r
        lastBoxCenter = CGPoint(x: r.midX, y: r.midY)
        repaint()
    }

    /// Breite des Feldes geändert (Regler im iPhone-Fenster)
    func resizeTarget() {
        guard target != nil, let c = lastBoxCenter else { return }
        moveTarget(to: c)
        target!.id = nextID()
    }

    func clearTarget() {
        target = nil
        repaint()
    }

    // MARK: HTTP (iPhone)

    private func handle(_ req: HTTPRequest) async -> HTTPResponse {
        guard server.isValid(token: req.query["t"]) else { return .text("Forbidden", status: 403) }
        switch (req.method, req.path) {
        case ("GET", "/"):
            return .text(PhonePage.html, type: "text/html; charset=utf-8")
        case ("GET", "/api/state"):
            return await MainActor.run { stateResponse() }
        case ("GET", "/api/preview"):
            return await MainActor.run { previewResponse() }
        case ("POST", "/api/sign"):
            return await MainActor.run { signResponse(req.body) }
        default:
            return .text("Not found", status: 404)
        }
    }

    private func stateResponse() -> HTTPResponse {
        phoneLastSeen = Date()
        var s: [String: Any] = ["pages": pageCount, "doc": fileURL?.deletingPathExtension().lastPathComponent ?? "",
                                "ink": inkColor.hex, "active": false]
        if let t = target {
            s["active"] = true
            s["id"] = t.id
            s["page"] = t.page + 1
            s["aspect"] = t.rect.width / t.rect.height
        }
        return .json(s)
    }

    private func previewResponse() -> HTTPResponse {
        guard let t = target, let page = document?.page(at: t.page),
              let png = Self.renderRegion(page: page, rect: t.rect, scale: 4) else {
            return .text("none", status: 404)
        }
        return HTTPResponse(status: 200, contentType: "image/png", body: png)
    }

    private func signResponse(_ body: Data) -> HTTPResponse {
        guard let t = target, let doc = document, let page = doc.page(at: t.page),
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              (obj["id"] as? Int) == t.id,
              let raw = obj["strokes"] as? [[[Double]]] else {
            return .json(["ok": false])
        }
        let ann = ink(for: t.page)
        let group = nextGroup
        nextGroup += 1
        var added = false
        for s in raw where !s.isEmpty && s.allSatisfy({ $0.count >= 3 }) {
            let pts = s.map { CGPoint(x: t.rect.minX + CGFloat($0[0]) * t.rect.width,
                                      y: t.rect.maxY - CGFloat($0[1]) * t.rect.height) }
            let times = s.map { $0[2] / 1000 }
            ann.strokes.append(InkStroke(points: pts,
                                         widths: Ink.widths(points: pts, times: times, base: penWidth),
                                         color: inkColor.cgColor, group: group))
            added = true
        }
        guard added else { return .json(["ok": false]) }
        refresh(t.page)
        clearTarget()
        _ = page
        return .json(["ok": true])
    }

    static func renderRegion(page: PDFPage, rect: CGRect, scale: CGFloat) -> Data? {
        let w = Int(rect.width * scale), h = Int(rect.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let ref = page.pageRef else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.drawPDFPage(ref)
        guard let img = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }
}
