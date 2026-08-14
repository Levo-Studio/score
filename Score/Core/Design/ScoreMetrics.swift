import Foundation

/// Radien und Abstände der Design-Sprache.
///
/// Die Design-Datei legt beides als feste Leiter fest — „12 CHIPS · 18 ROWS ·
/// 22 CARDS · 34 SCORE" und „SPACING 4 · 8 · 12 · 16 · 20 · 26". Alles im Code
/// greift auf diese Werte zu, damit keine krummen Zwischengrössen entstehen.
enum ScoreMetrics {

    /// Eckenradien, nach Bauteil benannt statt nach Zahl.
    enum Radius {
        /// Chips, Segmente, kleine Kacheln.
        static let chip: CGFloat = 12
        /// Listenzeilen und Fachzeilen.
        static let row: CGFloat = 18
        /// Segmentleisten und kleinere Gruppen.
        static let group: CGFloat = 16
        /// Karten und Gruppen.
        static let card: CGFloat = 22
        /// Die grosse Score-Karte auf dem Dashboard.
        static let score: CGFloat = 34
        /// Die schwebende Tab-Bar.
        static let tabBar: CGFloat = 26
        /// Die Glow-Karte der Fachansicht und die Oberkante des Eingabe-Sheets.
        static let sheet: CGFloat = 28
        /// Vollrund, für Pillen und Schalter.
        static let pill: CGFloat = 99
    }

    /// Die Abstandsleiter.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 26
    }

    /// Seitlicher Rand eines Bildschirms auf dem iPhone.
    static let screenPadding: CGFloat = 20

    /// Freiraum unter dem Inhalt, damit die schwebende Tab-Bar nichts verdeckt.
    static let tabBarClearance: CGFloat = 150

    /// Mindestgrösse einer Tap-Fläche.
    static let minimumTapTarget: CGFloat = 44
}
