import SwiftUI
import UIKit

/// Die Farbwerte der Score-Design-Sprache, 1:1 aus der Design-Datei.
///
/// Jeder Token existiert in einer hellen und einer dunklen Variante und wird als
/// dynamische `Color` aufgeloest. Dadurch folgt die gesamte Oberfläche automatisch
/// dem Farbschema — auch dann, wenn der Nutzer es in den Einstellungen manuell
/// über `preferredColorScheme` überschreibt.
///
/// Die Namen entsprechen den CSS-Custom-Properties des Prototyps, damit sich Design
/// und Code gegeneinander lesen lassen:
/// `--bg` → `background`, `--sf` → `surface`, `--sf2` → `fill`, `--ink2` → `inkSecondary`.
enum ScorePalette {

    // MARK: - Flächen

    /// `--bg` — der Grund, auf dem alles liegt.
    static let background = Color(light: 0xF1F3F2, dark: 0x0A0D0C)

    /// `--sf` — Karten, Zeilen, Sheets.
    static let surface = Color(light: 0xFFFFFF, dark: 0x151817)

    /// `--sf2` — gefüllte Felder innerhalb einer Karte, iPad-Sidebar.
    static let fill = Color(light: 0xE7EAE9, dark: 0x1B1F1E)

    // MARK: - Text

    /// `--ink` — primärer Text.
    static let ink = Color(light: 0x101413, dark: 0xEDF1EF)

    /// `--ink2` — sekundärer Text, Meta-Zeilen, inaktive Zustände.
    static let inkSecondary = Color(light: 0x6B7370, dark: 0x7E8784)

    // MARK: - Linien

    /// `--line` — Kartenränder und Trenner.
    static let line = Color(light: 0x101413, lightAlpha: 0.10, dark: 0xEDF1EF, darkAlpha: 0.12)

    /// `--line2` — gestrichelte Ränder, kräftigere Trenner.
    static let lineStrong = Color(light: 0x101413, lightAlpha: 0.22, dark: 0xEDF1EF, darkAlpha: 0.24)

    // MARK: - Akzent

    /// `--acc` — das Petrol der Marke.
    static let accent = Color(light: 0x1C6B6E, dark: 0x4EA3A6)

    /// `--accInk` — Text auf Akzentflächen.
    static let accentInk = Color(light: 0xF1F3F2, dark: 0x06100F)

    /// `--accSoft` — mittlerer Halt des Skalen-Verlaufs, in beiden Schemata gleich.
    static let accentSoft = Color(0x4EA3A6, alpha: 0.5)

    // MARK: - Score-Karte
    //
    // Die Glow-Karte hat einen eigenen Satz Tokens, weil sie im Dunkeln nicht die
    // normale Surface-Farbe nutzt, sondern einen Tick dunkler steht als ihre Umgebung.

    /// `--scoreBg`
    static let scoreBackground = Color(light: 0xFFFFFF, dark: 0x0F1413)

    /// `--scoreInk`
    static let scoreInk = Color(light: 0x101413, dark: 0xEDF1EF)

    /// `--scoreInk2`
    static let scoreInkSecondary = Color(light: 0x101413, lightAlpha: 0.52, dark: 0xEDF1EF, darkAlpha: 0.50)

    /// `--scoreLine`
    static let scoreLine = Color(light: 0x101413, lightAlpha: 0.12, dark: 0xEDF1EF, darkAlpha: 0.14)

    /// `--glowC` — die Farbe des radialen Scheins hinter dem Score.
    static let glow = Color(light: 0x1C6B6E, lightAlpha: 0.20, dark: 0x4EA3A6, darkAlpha: 0.42)

    // MARK: - Glas

    /// `--glass` — Füllung der Liquid-Glass-Tab-Bar hinter dem Blur.
    static let glass = Color(light: 0xFFFFFF, lightAlpha: 0.66, dark: 0x151817, darkAlpha: 0.62)

    /// `--glassLine` — Kante der Tab-Bar.
    static let glassLine = Color(light: 0x101413, lightAlpha: 0.08, dark: 0xEDF1EF, darkAlpha: 0.10)

    // MARK: - Status

    /// `--warn` — Löschen, Warnungen, nicht gewertete Kurse.
    static let warn = Color(light: 0xB4534A, dark: 0xC97A70)

    /// `--trk` — Hintergrund von Fortschrittsbalken.
    static let track = Color(light: 0x101413, lightAlpha: 0.14, dark: 0xEDF1EF, darkAlpha: 0.18)

    // MARK: - Fachfarben

    /// Die sechs wählbaren Fachfarben. Sie sind bewusst in beiden Schemata identisch,
    /// damit ein Fach beim Wechsel von Hell auf Dunkel wiedererkennbar bleibt.
    static let subjectColors: [Color] = subjectColorValues.map { Color($0) }

    /// Dieselben Werte als Rohzahl — so werden sie im Datenmodell abgelegt.
    static let subjectColorValues: [UInt32] = [
        0x1C6B6E,   // Petrol
        0x3E7CA6,   // Blau
        0x5A7A61,   // Grün
        0x8A6A4A,   // Braun
        0xB4534A,   // Rot
        0x7A6EA6    // Violett
    ]
}

// MARK: - Hex-Initialisierer

extension Color {

    /// Baut eine Farbe aus einem RGB-Hexwert, optional mit Deckkraft.
    nonisolated init(_ hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Baut eine Farbe, die je nach Farbschema zwischen zwei Hexwerten wechselt.
    nonisolated init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let alpha = traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}
