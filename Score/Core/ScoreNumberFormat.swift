import Foundation

/// Zahlen so, wie sie im Zeugnis stehen.
///
/// Score rechnet in Punkten und Noten — beides schreibt man in Deutschland mit
/// Komma. Die Formatierung hängt deshalb bewusst an einem festen deutschen
/// Gebietsschema und nicht an dem des Geräts: ein „12.4" wäre in einem
/// Notenkontext schlicht falsch, auch auf einem englisch eingestellten iPhone.
enum ScoreNumberFormat {

    private static let german = Locale(identifier: "de_DE")

    /// Der Strich, der „kein Wert" bedeutet — nicht „null Punkte".
    static let placeholder = "–"

    /// Derselbe Strich für Noten, die immer eine Nachkommastelle zeigen.
    static let gradePlaceholder = "–,–"

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

    /// Eine Note mit einer Nachkommastelle, etwa „1,8".
    static func grade(_ value: Double?) -> String {
        guard let value else { return gradePlaceholder }
        return decimal(value)
    }

    /// Eine vorzeichenbehaftete Veränderung, etwa „+1,2".
    static func signedDecimal(_ value: Double) -> String {
        (value > 0 ? "+" : "") + decimal(value)
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(german))
    }
}
