import Foundation

extension String {

    /// Wie `String(localized:)`, aber ausdrücklich gegen die Sprache von Score
    /// und nicht gegen die des Prozesses.
    ///
    /// Score ist einsprachig deutsch, die Auflösung gegen ``ScoreLocale/german``
    /// ist trotzdem keine Formsache: `String(localized:)` sucht die Übersetzung
    /// in der Sprache, auf die sich Prozess und Bundle geeinigt haben. Auf einem
    /// englisch eingestellten Gerät hängt das an der Entwicklungsregion des
    /// Bundles — eine Annahme, die man nicht in jedem Aufruf mitdenken will.
    /// Eine ``LocalizedStringResource`` trägt ihre Sprache dagegen bis in die
    /// Auflösung hinein.
    ///
    /// Überall dort, wo ein `String` gebraucht wird und kein `Text` möglich ist —
    /// Titel, zusammengesetzte `AttributedString`s, Werte für Bezeichner — gehört
    /// deshalb dieser Aufruf hin statt `String(localized:)`.
    static func scoreLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: ScoreLocale.german))
    }
}

extension AttributedString {

    /// Dasselbe wie `String.scoreLocalized(_:)`, für zusammengesetzte Texte.
    ///
    /// Gebraucht, wo mehrere Bausteine mit eigenen Pluralen zu einer Zeile
    /// verbunden werden und deshalb kein einzelner `LocalizedStringKey` reicht.
    static func scoreLocalized(_ key: String.LocalizationValue) -> AttributedString {
        AttributedString(localized: LocalizedStringResource(key, locale: ScoreLocale.german))
    }
}
