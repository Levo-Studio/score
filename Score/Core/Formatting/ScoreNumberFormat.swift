import Foundation

/// Zahlen so, wie sie im Zeugnis stehen.
///
/// Score rechnet in Punkten und Noten — beides schreibt man in Deutschland mit
/// Komma. Die Formatierung hängt deshalb bewusst an einem festen deutschen
/// Gebietsschema und nicht an dem des Geräts: ein „12.4" wäre in einem
/// Notenkontext schlicht falsch, auch auf einem englisch eingestellten iPhone.
/// Die Rechnung ist die des baden-württembergischen Abiturs und wird in dieser
/// Schreibweise gelesen.
enum ScoreNumberFormat {

    private static let german = Locale(identifier: "de_DE")

    /// Der Strich, der „kein Wert" bedeutet — nicht „null Punkte".
    ///
    /// Der Unterschied ist wichtig: ein Halbjahr ohne erfasste Leistung hat kein
    /// Ergebnis, und 0 Punkte wären eine ganz andere Aussage.
    static let placeholder = "–"

    /// Derselbe Strich für Noten, die immer eine Nachkommastelle zeigen.
    static let gradePlaceholder = "–,–"

    // MARK: - Punkte

    /// Eine Punktzahl mit einer Nachkommastelle, etwa „12,4".
    static func points(_ value: Double?) -> String {
        guard let value else { return placeholder }
        return decimal(value)
    }

    /// Ein ganzes Halbjahresergebnis, etwa „13".
    static func points(_ value: Int?) -> String {
        guard let value else { return placeholder }
        return value.formatted(.number.locale(german))
    }

    // MARK: - Noten

    /// Eine Note mit einer Nachkommastelle, etwa „1,8".
    static func grade(_ value: Double?) -> String {
        guard let value else { return gradePlaceholder }
        return decimal(value)
    }

    // MARK: - Allgemein

    /// Eine Zahl mit fester Nachkommastelle und Komma.
    ///
    /// - Parameter fractionDigits: Schnitte stehen mit einer Nachkommastelle,
    ///   ganze Punktzahlen ohne.
    static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(german))
    }

    /// Wie `decimal(_:fractionDigits:)`, liefert bei `nil` aber den Platzhalter.
    static func decimal(_ value: Double?, fractionDigits: Int = 1) -> String {
        guard let value else { return placeholder }
        return decimal(value, fractionDigits: fractionDigits)
    }

    /// Eine vorzeichenbehaftete Veränderung, etwa „+1,2".
    static func signedDecimal(_ value: Double) -> String {
        (value > 0 ? "+" : "") + decimal(value)
    }

    /// Eine Veränderung mit Richtungspfeil, etwa „↑ 0,2".
    ///
    /// Positiv heisst „besser". Was „besser" bedeutet, hängt von der Grösse ab —
    /// bei Noten ist kleiner besser, bei Punkten grösser — deshalb entscheidet
    /// der Aufrufer über das Vorzeichen und übergibt den Wert bereits so, dass
    /// grösser gleich besser ist.
    ///
    /// Unterhalb von 0,05 wird kein Trend gezeigt: eine Veränderung, die sich in
    /// der angezeigten Nachkommastelle nicht niederschlägt, ist keine.
    static func trend(_ delta: Double?) -> String {
        guard let delta, abs(delta) >= 0.05 else { return placeholder }
        let arrow = delta > 0 ? "↑" : "↓"
        return "\(arrow) \(decimal(abs(delta)))"
    }
}
