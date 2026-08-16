import SwiftUI

/// Die Begrüssung über dem Score — die eine Zeile, die den Stand in Worte fasst.
///
/// Sie steht auf beiden Geräten über dem Score, dem iPhone wie dem iPad.
/// Beide holen sie hier ab, damit die Zeile nur an einer Stelle gepflegt wird:
/// Wer den Ton ändern will oder eine Schwelle verschieben, fasst diese Datei an
/// und keine View.
///
/// Der Ton ist gesetzt: kurz, per du, immer aufbauend. Auch die unterste Stufe
/// spricht dem Nutzer Mut zu, statt zu tadeln oder zu bedauern — Score bewertet
/// die Rechnung, nicht den Menschen.
///
/// Die Länge ist die harte Grenze. Der Vorname hängt hinter der Zeile, und beides
/// zusammen muss auf einem iPhone in eine Zeile passen. Darum liegt jede
/// Formulierung bei höchstens dreizehn Zeichen — so lang wie „Läuft bei dir".
enum DashboardGreeting {

    // MARK: - Stufen

    /// Die Stufe, in der ein Nutzer gerade steht.
    ///
    /// Die Reihenfolge ist die der Schwellen: von „noch nichts da" über den
    /// besten Schnitt bis zum schwächsten.
    enum Stage: Hashable, CaseIterable {
        /// Es ist noch fast nichts erfasst — der Schnitt sagt nichts aus.
        case start
        /// Bis etwa 1,5.
        case excellent
        /// Bis etwa 2,5.
        case good
        /// Bis etwa 3,5.
        case solid
        /// Darunter.
        case onward
    }

    // MARK: - Schwellen

    /// Ab wie vielen erfassten Kursen der Schnitt überhaupt etwas aussagt.
    ///
    /// Darunter steht die Einladung zum Eintragen statt einer Bewertung: Mit
    /// einer einzigen Note ist der errechnete Schnitt eine Zufallszahl, und die
    /// darf nicht wie ein Urteil klingen.
    static let minimumRecordedCourses = 3

    /// Die obere Grenze jeder Stufe, in Abischnitt. Kleiner ist besser.
    ///
    /// Ein Wert gehört zur ersten Stufe, deren Grenze er nicht überschreitet.
    /// Alles darunter fällt auf ``Stage/onward``.
    static let excellentUpperBound = 1.5
    static let goodUpperBound = 2.5
    static let solidUpperBound = 3.5

    /// Welche Stufe zu einem Stand gehört.
    ///
    /// - Parameters:
    ///   - expectedGrade: Der errechnete Abischnitt.
    ///   - recordedCount: Wie viele Kurse überhaupt ein Ergebnis haben.
    static func stage(expectedGrade: Double, recordedCount: Int) -> Stage {
        guard recordedCount >= minimumRecordedCourses else { return .start }
        return switch expectedGrade {
        case ...excellentUpperBound: .excellent
        case ...goodUpperBound: .good
        case ...solidUpperBound: .solid
        default: .onward
        }
    }

    // MARK: - Zeilen

    /// Die Zeilen selbst — die einzige Stelle, an der sie stehen.
    ///
    /// Der Name gehört in den Schlüssel und wird nicht dahinter geklebt: So
    /// entscheidet jede Sprache selbst, wo er steht und ob ein Komma davor
    /// gehört. Deutsch ist die Basissprache, der Schlüssel also zugleich die
    /// deutsche Zeile; das Englische steht im Katalog daneben.
    static func value(for stage: Stage, firstName: String) -> String.LocalizationValue {
        switch stage {
        // Noch nichts erfasst: Die Zeile lädt ein, statt eine Leistung zu
        // bewerten, die es noch gar nicht gibt.
        case .start: "Leg los, \(firstName)"
        case .excellent: "Läuft bei dir, \(firstName)"
        case .good: "Gut unterwegs, \(firstName)"
        case .solid: "Da geht was, \(firstName)"
        // Die unterste Stufe. Sie sagt nicht, dass es schlecht steht, sondern
        // dass es zu schaffen ist.
        case .onward: "Du packst das, \(firstName)"
        }
    }

    /// Die fertige Zeile für eine View.
    ///
    /// Als `Text` und nicht als `String`: Ein freistehender `String(localized:)`
    /// sucht die Übersetzung in der Sprache des Prozesses und nicht in der, die
    /// der Nutzer in Score gewählt hat — auf einem englischen Gerät mit deutsch
    /// gestellter App stünde hier sonst die englische Zeile. Der Umweg über
    /// ``LocalizedStringResource`` nimmt die Sprache ausdrücklich mit.
    @MainActor
    static func text(for stage: Stage, firstName: String) -> Text {
        Text(
            LocalizedStringResource(
                value(for: stage, firstName: firstName),
                locale: AppSettings.shared.locale
            )
        )
    }

    /// Beides in einem Schritt — der Weg, den die Views nehmen.
    @MainActor
    static func text(expectedGrade: Double, recordedCount: Int, firstName: String) -> Text {
        text(
            for: stage(expectedGrade: expectedGrade, recordedCount: recordedCount),
            firstName: firstName
        )
    }
}
