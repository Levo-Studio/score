import SwiftUI
import CoreText
import UIKit

/// Das Typografie-Pairing der Design-Sprache: Archivo für Score, Zahlen und
/// Headlines, Public Sans für Fliesstext, Listen und Buttons.
///
/// Beide Schriften liegen als Variable Fonts im Bundle und werden über
/// `UIAppFonts` in der Info.plist geladen. Der Schlüssel steht dort in einer
/// echten Datei und nicht in einem `INFOPLIST_KEY_`-Build-Setting: Xcode reicht
/// über diese Settings nur eine feste Liste bekannter Schlüssel durch, und
/// `UIAppFonts` gehört nicht dazu.
///
/// Der Schnitt wird immer explizit über die `wght`-Achse aufgelöst und nie über
/// einen geratenen PostScript-Namen. Das ist wichtig, weil Archivo als
/// Voreinstellung auf der Achse nicht 400, sondern 600 stehen hat: ein
/// `Font.custom("Archivo", size:)` ohne Achsenwert liefert also SemiBold statt
/// Regular.
enum ScoreTypography {

    // MARK: - Familien

    private enum Family {
        static let archivo = "Archivo"
        static let publicSans = "Public Sans"
    }

    /// Die `wght`-Achse als CoreText-Kennung. Vier Zeichen, big endian: 'w','g','h','t'.
    private static let weightAxis = 0x77676874

    /// Baut eine `Font` aus Familie, Achsengewicht und Grösse.
    ///
    /// - Parameters:
    ///   - maximumPointSize: Obergrenze für Dynamic Type. Die Design-Datei arbeitet
    ///     mit festen Grössen in sehr eng gesetzten Layouts — der Score steht in einer
    ///     393pt breiten Karte. Ohne Deckel würde die grösste Textgrösse diese Karten
    ///     sprengen. Mit Deckel skaliert der Text mit, bleibt aber im Rahmen.
    private static func font(
        family: String,
        weight: Int,
        size: CGFloat,
        maximumPointSize: CGFloat
    ) -> Font {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                weightAxis: weight
            ]
        ])
        let base = UIFont(descriptor: descriptor, size: size)
        let scaled = UIFontMetrics.default.scaledFont(for: base, maximumPointSize: maximumPointSize)
        return Font(scaled)
    }

    /// Archivo in einem beliebigen Schnitt.
    static func archivo(_ weight: Int, _ size: CGFloat) -> Font {
        font(family: Family.archivo, weight: weight, size: size, maximumPointSize: size * 1.35)
    }

    /// Public Sans in einem beliebigen Schnitt.
    static func publicSans(_ weight: Int, _ size: CGFloat) -> Font {
        font(family: Family.publicSans, weight: weight, size: size, maximumPointSize: size * 1.4)
    }
}

// MARK: - Benannte Stile

extension Font {

    // Archivo — Score, Zahlen, Headlines

    /// Der grosse Score auf dem Dashboard. Grösse variiert je Gerät: 128 auf dem
    /// iPhone, 112 auf dem iPad, 54 in der Fach-Detailansicht.
    static func scoreDisplay(_ size: CGFloat) -> Font { ScoreTypography.archivo(800, size) }

    /// Bildschirm-Überschrift, `800 26px`.
    static let screenTitle = ScoreTypography.archivo(800, 26)

    /// Überschrift in der Willkommens- und Schrittansicht, `800 27px`.
    static let stepTitle = ScoreTypography.archivo(800, 27)

    /// Begrüssung auf dem Dashboard, `800 24px`.
    static let greeting = ScoreTypography.archivo(800, 24)

    /// Kartenüberschrift, `600 13px`.
    static let cardTitle = ScoreTypography.archivo(600, 13)

    /// Kennzahl in der Statistik-Zeile der Score-Karte, `600 17px`.
    static let statValue = ScoreTypography.archivo(600, 17)

    /// Punktzahl am Ende einer Fachzeile, `800 20px`.
    static let rowValue = ScoreTypography.archivo(800, 20)

    /// Beschriftung der Halbjahres-Segmente, `600 12px`.
    static let segmentLabel = ScoreTypography.archivo(600, 12)

    // Public Sans — Fliesstext und UI

    /// Titel einer Listenzeile, `600 13.5px`.
    static let rowTitle = ScoreTypography.publicSans(600, 13.5)

    /// Fliesstext, `400 13.5px`.
    static let bodyText = ScoreTypography.publicSans(400, 13.5)

    /// Meta-Zeile unter einem Zeilentitel, `400 11px`.
    static let meta = ScoreTypography.publicSans(400, 11)

    /// Kleinstes Label über einer Gruppe, `400 10px`.
    static let micro = ScoreTypography.publicSans(400, 10)

    /// Label in der Score-Karte, `500 9.5px`.
    static let cardLabel = ScoreTypography.publicSans(500, 9.5)

    /// Chip- und Segment-Beschriftung, `500 12.5px`.
    static let chipLabel = ScoreTypography.publicSans(500, 12.5)

    /// Beschriftung einer Einstellungszeile, `500 13.5px`.
    static let settingsRowTitle = ScoreTypography.publicSans(500, 13.5)

    /// Wert am rechten Rand einer Einstellungszeile, `500 13px`.
    static let settingsRowValue = ScoreTypography.publicSans(500, 13)

    /// Beschriftung eines primären Buttons, `600 14px`.
    static let buttonLabel = ScoreTypography.publicSans(600, 14)

    /// Beschriftung in der Tab-Bar, `500 9.5px`.
    static let tabLabel = ScoreTypography.publicSans(500, 9.5)

    /// Badge an einem Fachnamen, `500 9px`.
    static let badgeLabel = ScoreTypography.publicSans(500, 9)
}

// MARK: - Laufweite

extension View {

    /// Setzt die Laufweite in `em` statt in Punkt, so wie die Design-Datei sie notiert
    /// (`letter-spacing:-.055em`). Erspart es, an jeder Stelle von Hand umzurechnen.
    func tracking(em: CGFloat, at size: CGFloat) -> some View {
        tracking(em * size)
    }
}
