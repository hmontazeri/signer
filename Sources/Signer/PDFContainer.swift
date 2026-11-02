import AppKit
import PDFKit
import SwiftUI

/// Liegt transparent über dem PDFView und zeichnet Striche, Texte und Zielrahmen aller sichtbaren Seiten.
final class InkOverlay: NSView {
    weak var pdfView: PDFView?
    weak var model: SignModel?

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let pdf = pdfView, let model,
              let doc = pdf.document else { return }
        for page in pdf.visiblePages {
            let idx = doc.index(for: page)
            guard idx != NSNotFound else { continue }
            let o = pdf.convert(CGPoint.zero, from: page)
            let x = pdf.convert(CGPoint(x: 1, y: 0), from: page)
            let y = pdf.convert(CGPoint(x: 0, y: 1), from: page)
            ctx.saveGState()
            ctx.clip(to: pdf.convert(page.bounds(for: .cropBox), from: page))
            ctx.concatenate(CGAffineTransform(a: x.x - o.x, b: x.y - o.y, c: y.x - o.x, d: y.y - o.y, tx: o.x, ty: o.y))
            model.paintOverlay(ctx, pageIndex: idx)
            ctx.restoreGState()
        }
    }
}

final class SigPDFView: PDFView, NSTextFieldDelegate {
    weak var model: SignModel?
    private var activePage: PDFPage?
    private(set) var overlay: InkOverlay?
    private var scrollObserver: NSObjectProtocol?

    private struct Editing {
        var page: PDFPage
        var pageIndex: Int
        var existing: TextItem?
        var origin: CGPoint
        var field: NSTextField
    }
    private var editing: Editing?

    // MARK: Aufbau

    func installOverlay(model: SignModel) {
        registerForDraggedTypes([.fileURL])
        let o = InkOverlay(frame: bounds)
        o.autoresizingMask = [.width, .height]
        o.pdfView = self
        o.model = model
        addSubview(o)
        overlay = o
    }

    /// Beim Scrollen (Trackpad/Mausrad) muss das Overlay mitgezeichnet werden.
    func observeScrolling() {
        guard let clip = documentView?.enclosingScrollView?.contentView else { return }
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in self?.overlay?.needsDisplay = true }
    }

    override func layout() {
        super.layout()
        overlay?.needsDisplay = true
    }

    override func resetCursorRects() {
        if model?.document != nil { addCursorRect(bounds, cursor: model?.mode == .text ? .iBeam : .crosshair) }
    }

    // MARK: Drag & Drop

    private func droppedPDF(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { $0.pathExtension.lowercased() == "pdf" }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedPDF(sender) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedPDF(sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedPDF(sender) else { return false }
        DispatchQueue.main.async { [weak self] in self?.model?.open(url) }
        return true
    }

    // MARK: Maus

    override func mouseDown(with event: NSEvent) {
        guard let model, model.document != nil else { return super.mouseDown(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        endEditing(commit: true)
        guard let page = page(for: p, nearest: true) else { return }
        if model.mode == .text {
            beginEditing(page: page, at: convert(p, to: page))
            return
        }
        activePage = page
        model.mouseDown(page: page, at: convert(p, to: page), time: event.timestamp)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let page = activePage else { return super.mouseDragged(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        model.mouseDragged(page: page, at: convert(p, to: page), time: event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        guard let model, activePage != nil else { return super.mouseUp(with: event) }
        activePage = nil
        model.mouseUp()
    }

    // MARK: Text eingeben

    private func beginEditing(page: PDFPage, at p: CGPoint) {
        guard let model, let doc = document else { return }
        let idx = doc.index(for: page)
        let existing = model.textItem(on: idx, at: p)
        let size = existing?.size ?? model.textSize
        let origin = existing?.origin ?? CGPoint(x: p.x, y: p.y - size * 0.6)
        let initial = existing?.text ?? model.pendingText ?? ""
        model.pendingText = nil
        if let e = existing { model.removeText(e.id, pageIndex: idx) }

        let scale = scaleFactor
        let f = NSTextField(string: initial)
        f.font = TextItem.font(size * scale)
        f.textColor = NSColor(cgColor: existing?.color ?? model.inkColor.cgColor)
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = true
        f.backgroundColor = NSColor.white.withAlphaComponent(0.92)
        f.focusRingType = .none
        f.delegate = self
        let o = convert(origin, from: page)
        let h = (TextItem.font(size * scale).ascender - TextItem.font(size * scale).descender) + 4
        f.frame = NSRect(x: o.x - 2, y: o.y - 2, width: max(180, f.intrinsicContentSize.width + 30), height: h)
        addSubview(f)
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectedRange = NSRange(location: (initial as NSString).length, length: 0)
        editing = Editing(page: page, pageIndex: idx, existing: existing, origin: origin, field: f)
    }

    func endEditing(commit: Bool) {
        guard let e = editing else { return }
        editing = nil
        let text = e.field.stringValue
        e.field.delegate = nil
        e.field.removeFromSuperview()
        window?.makeFirstResponder(self)
        if commit {
            model?.commitText(pageIndex: e.pageIndex, existing: e.existing, origin: e.origin, text: text)
        } else if let old = e.existing {
            model?.commitText(pageIndex: e.pageIndex, existing: nil, origin: old.origin, text: old.text)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { endEditing(commit: true); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { endEditing(commit: false); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        DispatchQueue.main.async { [weak self] in self?.endEditing(commit: true) }
    }
}

struct PDFContainer: NSViewRepresentable {
    @ObservedObject var model: SignModel

    func makeNSView(context: Context) -> SigPDFView {
        let v = SigPDFView()
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.autoScales = true
        v.backgroundColor = .underPageBackgroundColor
        v.model = model
        model.pdfView = v
        v.installOverlay(model: model)
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: v, queue: .main
        ) { [weak model, weak v] _ in
            guard let model, let v, let page = v.currentPage, let idx = v.document?.index(for: page) else { return }
            model.pageChanged(to: idx)
            model.repaint()
        }
        context.coordinator.scaleObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged, object: v, queue: .main
        ) { [weak model] _ in model?.repaint() }
        return v
    }

    func updateNSView(_ v: SigPDFView, context: Context) {
        if v.document !== model.document {
            v.document = model.document
            v.autoScales = true
            v.window?.invalidateCursorRects(for: v)
            DispatchQueue.main.async { v.observeScrolling() }
        }
        v.window?.invalidateCursorRects(for: v)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var observer: NSObjectProtocol?; var scaleObserver: NSObjectProtocol? }
}
