# PDF Signer

Kleine macOS-App (Swift, SwiftUI + PDFKit) zum Unterschreiben von PDFs.

- **Maus/Trackpad:** direkt auf die Seite zeichnen (Strichstärke je nach Geschwindigkeit)
- **iPhone:** QR-Code scannen, im Safari mit dem Finger unterschreiben – die Unterschrift landet an der gewählten Stelle im PDF (gleiches WLAN nötig)
- **Text:** Datum, Ort usw. einfügen
- Jede Unterschrift wird frisch gezeichnet; es gibt bewusst kein Stempeln einer gespeicherten Unterschrift
- Export als neue PDF, Unterschriften und Text sind fest eingebrannt

## Download

Unter [Releases](../../releases/latest) die `PDF-Signer-*.zip` laden, entpacken und nach `/Programme` ziehen.

Die App ist nicht notarisiert. Beim ersten Start: Rechtsklick → *Öffnen*, oder im Terminal:

```bash
xattr -cr /Applications/Signer.app
```

## Selbst bauen

Nur die Xcode Command Line Tools sind nötig (macOS 14+):

```bash
./build.sh            # baut build/Signer.app
./build.sh install    # und kopiert nach /Applications
```

Das Icon wird aus `Resources/icon-1024.png` erzeugt (neu zeichnen: `Resources/make-icon.swift`).
