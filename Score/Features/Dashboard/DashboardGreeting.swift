import Foundation

/// Die Begrüssung über dem Score — die eine Zeile, die den Stand in Worte fasst.
///
/// Sie steht auf dem iPhone im Dashboard und auf dem iPad in der Kopfleiste.
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

    /// Die fertige Zeile samt Vornamen.
    ///
    /// Der Name steht im Schlüssel und nicht dahinter angeklebt: So entscheidet
    /// jede Sprache selbst, wo er hingehört und ob ein Komma davor steht.
    ///
    /// Übersetzt wird über ``String/scoreLocalized(_:)``, weil hier ein `String`
    /// entsteht und kein `Text` — die in Score gewählte Sprache erreicht einen
    /// freistehenden `String(localized:)` nicht.
    static func text(for stage: Stage, firstName: String) -> String {
        switch stage {
        // Noch nichts erfasst: Die Zeile lädt ein, statt eine Leistung zu
        // bewerten, die es noch gar nicht gibt.
        case .start: String.scoreLocalized("Leg los, \(firstName)")
        case .excellent: String.scoreLocalized("Läuft bei dir, \(firstName)")
        case .good: String.scoreLocalized("Gut unterwegs, \(firstName)")
        case .solid: String.scoreLocalized("Da geht was, \(firstName)")
        // Die unterste Stufe. Sie sagt nicht, dass es schlecht steht, sondern
        // dass es zu schaffen ist.
        case .onward: String.scoreLocalized("Du packst das, \(firstName)")
        }
    }

    /// Beides in einem Schritt — der Weg, den die Views nehmen.
    static func text(expectedGrade: Double, recordedCount: Int, firstName: String) -> String {
        text(
            for: stage(expectedGrade: expectedGrade, recordedCount: recordedCount),
            firstName: firstName
        )
    }
}
