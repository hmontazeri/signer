import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SignerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SignModel()

    var body: some Scene {
        WindowGroup("PDF Signer") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1200, minHeight: 700)
                .onOpenURL { model.open($0) }
                .onAppear {
                    if let p = CommandLine.arguments.dropFirst().first(where: { $0.lowercased().hasSuffix(".pdf") }) {
                        model.open(URL(fileURLWithPath: p))
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("PDF öffnen …") { model.openPanel() }.keyboardShortcut("o")
                Button("Unterschriebene PDF speichern …") { model.exportPanel() }
                    .keyboardShortcut("s").disabled(model.document == nil)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: SignModel

    var body: some View {
        HStack(spacing: 0) {
            if model.document != nil {
                PageSidebar().frame(width: 150)
                Divider()
            }
            ZStack {
                PDFContainer(model: model)
                if model.document == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "signature").font(.system(size: 44))
                        Text("PDF hierher ziehen oder öffnen").font(.title3)
                        Button("PDF öffnen …") { model.openPanel() }
                    }
                    .padding(40)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let m = model.message {
                Text(m).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule()).padding(.bottom, 14)
                    .task { try? await Task.sleep(nanoseconds: 4_000_000_000); model.message = nil }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.openPanel() } label: { Label("Öffnen", systemImage: "folder") }
                Picker("Modus", selection: $model.mode) {
                    ForEach(SignModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 190)
                .onChange(of: model.mode) { _, new in
                    model.modeChanged()
                    if new == .phone && !model.phoneConnected { model.showPhone = true }
                }
                Picker("Farbe", selection: $model.inkColor) {
                    ForEach(InkColor.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 130)
                if model.mode == .text {
                    Stepper(value: $model.textSize, in: 8...24) { Text("\(Int(model.textSize)) pt").monospacedDigit() }
                    Button { model.insertDate() } label: { Label("Datum", systemImage: "calendar") }
                        .help("Heutiges Datum einfügen: danach auf die Stelle im Dokument klicken")
                } else {
                    Slider(value: $model.penWidth, in: 1...4).frame(width: 70).help("Strichstärke")
                }
            }
            ToolbarItemGroup {
                Button { model.step(-1) } label: { Label("Zurück", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command).disabled(model.document == nil)
                Text(model.document == nil ? "–" : "\(model.currentPage + 1) / \(model.pageCount)")
                    .monospacedDigit().frame(minWidth: 50)
                Button { model.step(1) } label: { Label("Weiter", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command).disabled(model.document == nil)
            }
            ToolbarItemGroup {
                Button { model.undo() } label: { Label("Rückgängig", systemImage: "arrow.uturn.backward") }
                    .keyboardShortcut("z").disabled(model.document == nil)
                Button { model.clearPage() } label: { Label("Seite leeren", systemImage: "trash") }
                    .disabled(model.document == nil)
                Button { model.showPhone = true } label: {
                    Label("iPhone", systemImage: model.phoneConnected ? "iphone.badge.checkmark" : "qrcode")
                }
                Button { model.exportPanel() } label: { Label("Speichern", systemImage: "square.and.arrow.down") }
                    .disabled(model.document == nil)
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .sheet(isPresented: $model.showPhone) { PhoneSheet(isPresented: $model.showPhone) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.open(url) } }
            }
            return true
        }
    }
}

struct PageSidebar: View {
    @EnvironmentObject var model: SignModel

    var body: some View {
        List(selection: Binding(get: { model.currentPage }, set: { model.go(to: $0) })) {
            ForEach(0..<model.pageCount, id: \.self) { i in
                HStack {
                    Text("Seite \(i + 1)")
                    Spacer()
                    if model.signedPages.contains(i) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .tag(i)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct PhoneSheet: View {
    @EnvironmentObject var model: SignModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("Mit dem iPhone unterschreiben").font(.title2.bold())
            if let url = model.phoneURL, let qr = Self.qr(url) {
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 230, height: 230)
                    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                Text("Kamera-App öffnen, QR-Code scannen, Link in Safari öffnen.\nMac und iPhone müssen im selben WLAN sein.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text(url).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
            } else {
                Text("Keine Netzwerkverbindung gefunden.").foregroundStyle(.red)
            }
            Label(model.phoneConnected ? "iPhone verbunden" : "Warte auf iPhone …",
                  systemImage: model.phoneConnected ? "checkmark.circle.fill" : "hourglass")
                .foregroundStyle(model.phoneConnected ? .green : .secondary)
            Divider()
            Text("Im Dokument im Modus „iPhone“ an die Stelle klicken, wo unterschrieben werden soll. Das Feld erscheint auf dem iPhone, zum Verschieben ziehen.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Text("Feldbreite")
                Slider(value: $model.boxWidth, in: 120...360) { editing in
                    if !editing { model.resizeTarget() }
                }
                .frame(width: 180)
            }
            Button("Fertig") { isPresented = false }.keyboardShortcut(.defaultAction)
        }
        .padding(24).frame(width: 420)
    }

    static func qr(_ s: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width, height: out.extent.height))
    }
}
