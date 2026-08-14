import Foundation

/// Zahlformatierung für die gesamte Oberfläche.
///
/// Score zeigt Noten und Schnitte immer mit Dezimalkomma — „1,8", nie „1.8".
/// Das ist keine Frage der Gerätesprache: die Rechnung ist die des baden-
/// württembergischen Abiturs und wird in dieser Schreibweise gelesen. Deshalb
/// wird bewusst nicht `Locale.current` verwendet, sondern hart auf Komma gesetzt.
enum ScoreNumberFormat {

    /// Steht überall dort, wo noch kein Wert vorliegt.
    static let placeholder = "–"

    /// Formatiert eine Zahl mit fester Nachkommastelle und Komma.
    ///
    /// - Parameter fractionDigits: Nachkommastellen. Schnitte stehen mit einer,
    ///   Punktzahlen ohne.
    static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        String(format: "%.\(fractionDigits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Wie `decimal(_:fractionDigits:)`, liefert bei `nil` aber den Platzhalter.
    static func decimal(_ value: Double?, fractionDigits: Int = 1) -> String {
        guard let value else { return placeholder }
        return decimal(value, fractionDigits: fractionDigits)
    }

    /// Eine Veränderung mit Richtungspfeil, etwa „↑ 0,2".
    ///
    /// Positiv heisst „besser" — die Bedeutung von „besser" hängt von der Grösse
    /// ab, deshalb entscheidet der Aufrufer über das Vorzeichen und übergibt den
    /// Wert bereits so, dass grösser gleich besser ist.
    static func trend(_ delta: Double?) -> String {
        guard let delta, abs(delta) >= 0.05 else { return placeholder }
        let arrow = delta > 0 ? "↑" : "↓"
        return "\(arrow) \(decimal(abs(delta)))"
    }
}
