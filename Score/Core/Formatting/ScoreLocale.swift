import Foundation

/// Die Locale, gegen die Score übersetzt und formatiert.
///
/// Score ist einsprachig deutsch. Trotzdem steht hier eine feste Locale und
/// nicht die des Geräts, denn beides sind zwei verschiedene Dinge: Die
/// Übersetzung kommt aus dem String-Katalog, der nur noch Deutsch führt, die
/// Formatierung von Zahlen und Daten dagegen aus Foundation und richtete sich
/// bisher nach der Systemsprache.
///
/// Ohne diese Festlegung stünde auf einem englisch eingestellten iPhone in der
/// Kopfzeile des Dashboards „Thursday, Aug 14" über einer sonst deutschen
/// Oberfläche, und „vor 2 Minuten" hiesse „2 minutes ago". Eine App, die
/// durchgehend deutsch spricht, formatiert auch durchgehend deutsch.
enum ScoreLocale {

    /// `de_DE` und nicht das blosse `de`: Die Region entscheidet über
    /// Dezimaltrennzeichen und Datumsreihenfolge, die Sprache allein tut das
    /// nicht.
    static let german = Locale(identifier: "de_DE")
}
