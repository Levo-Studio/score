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

    /// Masse einer Ablesezeile: je Spalte ein Wert über seiner Beschriftung,
    /// die Spalten durch eine Haarlinie getrennt.
    ///
    /// Die Form gibt es zweimal — in der Fusszeile der Score-Karte und in der
    /// Gewichtung des Fach-Editors. Die Werte stehen deshalb hier und nicht in
    /// einem der beiden Bauteile.
    enum Readout {
        /// Abstand zwischen einem Wert und seiner Beschriftung darunter.
        static let valueLabelSpacing: CGFloat = 6

        /// Einzug einer Spalte hinter der Haarlinie.
        static let columnInset: CGFloat = 14

        /// Luft über und unter einer Spalte.
        ///
        /// Sie gibt der senkrechten Haarlinie ihre Höhe: ohne sie endete der
        /// Strich bündig an Ober- und Unterkante des Textes und sähe aus wie
        /// ein zufälliger Rest.
        static let columnPadding: CGFloat = Spacing.sm

        /// Wie weit ein Wert schrumpfen darf, bevor er umbricht.
        ///
        /// Bei sehr grosser Schrift steht in einer schmalen Spalte sonst „60 …"
        /// statt „60 %". Weiter als hier soll er nicht schrumpfen — darunter
        /// wird die Zahl kleiner als ihre eigene Beschriftung.
        static let minimumScale: CGFloat = 0.7
    }

    /// Die Stärke einer Haarlinie — Kartenkante, Trenner, Spaltenstrich.
    static let hairline: CGFloat = 1

    /// Seitlicher Rand eines Bildschirms auf dem iPhone.
    static let screenPadding: CGFloat = 20

    /// Freiraum unter dem Inhalt, damit die schwebende Tab-Bar nichts verdeckt.
    static let tabBarClearance: CGFloat = 150

    /// Der seitliche Rand der schwebenden Tab-Bar.
    ///
    /// Enger als ``screenPadding``: Die Leiste ist ein eigenes Element über dem
    /// Inhalt und kein Teil davon. Auf denselben Rand gesetzt wirkte sie wie
    /// eine weitere Karte in der Spalte, statt darüber zu schweben — Apple
    /// setzt seine schwebenden Leisten aus demselben Grund enger.
    static let tabBarInset: CGFloat = 16

    /// Der Abstand der Tab-Bar zum unteren Sicherheitsbereich.
    ///
    /// Null: Der Sicherheitsbereich trägt am Home-Indikator bereits gut dreissig
    /// Punkt. Ein weiterer Abstand darüber schob die Leiste sichtbar zu hoch in
    /// den Inhalt hinein.
    static let tabBarBottomInset: CGFloat = 0

    /// Mindestgrösse einer Tap-Fläche.
    static let minimumTapTarget: CGFloat = 44

    /// Die Höhe eines Chips.
    ///
    /// Ein gefüllter Chip trägt 11 Punkt Polsterung über und unter seiner 12,5er
    /// Zeile; das ergibt weniger als die Mindest-Tap-Fläche, und die hebt ihn auf
    /// dieses Mass. Der Wert steht hier, weil ihn nicht nur `ScoreChip` braucht:
    /// Der gestrichelte „Eigenes Fach"-Tag muss in **jedem** Zustand genau so
    /// hoch sein, auch wenn in ihm ein Textfeld und ein „OK" stehen.
    static let chipHeight: CGFloat = minimumTapTarget

    /// Die Breite eines mittigen Blattes.
    ///
    /// Die Vorlage setzt für das Eingabe-Sheet 520 Punkt. Auf dem iPhone bleibt
    /// davon die Bildschirmbreite abzüglich der Ränder — dort ist der Wert also
    /// nur die Obergrenze.
    static let overlaySheetWidth: CGFloat = 520

    /// Der Rand, den ein mittiges Blatt zum Bildschirm hält.
    static let overlaySheetInset: CGFloat = Spacing.lg
}
