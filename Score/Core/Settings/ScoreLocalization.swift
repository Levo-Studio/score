import Foundation

extension String {

    /// Wie `String(localized:)`, aber in der Sprache, die der Nutzer **in Score**
    /// gewählt hat.
    ///
    /// `String(localized:)` löst gegen die Sprache des Prozesses auf und weiss
    /// nichts von `AppSettings`. Die App setzt ihre Sprache aber über
    /// `.environment(\.locale, …)` an der Wurzel — das erreicht jedes `Text`,
    /// jedoch keinen freistehenden `String(localized:)`-Aufruf.
    ///
    /// Die Folge war sichtbar: auf einem englisch eingestellten Gerät mit deutsch
    /// gewählter App stand „Nicht gewertet" neben „4 courses", und die Kopfleiste
    /// des iPads zeigte „Overview" über einer sonst deutschen Oberfläche.
    ///
    /// Überall dort, wo ein `String` gebraucht wird und kein `Text` möglich ist —
    /// Titel, zusammengesetzte `AttributedString`s, Werte für Bezeichner — gehört
    /// deshalb dieser Aufruf hin statt `String(localized:)`.
    /// Der Weg führt über ``LocalizedStringResource`` und nicht über
    /// `String(localized:locale:)`: Dessen `locale` bestimmt nur, wie Zahlen und
    /// Daten **innerhalb** des Textes formatiert werden — welche Übersetzung
    /// überhaupt gesucht wird, entscheidet weiterhin die Sprache des Bundles.
    /// Auf einem englischen Gerät mit deutsch gestellter App stand deshalb
    /// „Overview" über einer sonst deutschen Oberfläche. Eine
    /// `LocalizedStringResource` trägt ihre Sprache dagegen bis in die Auflösung.
    static func scoreLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: AppSettings.shared.locale))
    }
}

extension AttributedString {

    /// Dasselbe wie `String.scoreLocalized(_:)`, für zusammengesetzte Texte.
    ///
    /// Gebraucht, wo mehrere Bausteine mit eigenen Pluralen zu einer Zeile
    /// verbunden werden und deshalb kein einzelner `LocalizedStringKey` reicht.
    static func scoreLocalized(_ key: String.LocalizationValue) -> AttributedString {
        AttributedString(localized: LocalizedStringResource(key, locale: AppSettings.shared.locale))
    }
}
