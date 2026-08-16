import Foundation
import SwiftData

/// Die abgeleiteten Werte eines Fachs für ein bestimmtes Halbjahr.
///
/// Fächerliste und Fachansicht brauchen dieselben vier Angaben. Sie hier einmal
/// zu rechnen hält die Views schlank und stellt sicher, dass beide Bildschirme
/// denselben Stand zeigen — vor allem bei `isExcluded`, das sich nur aus dem
/// Vergleich *aller* Kurse ergibt und nicht am einzelnen Fach ablesbar ist.
struct SubjectSummary: Identifiable {

    let subject: Subject

    /// Das Halbjahr, auf das sich `result`, `isActive` und `isExcluded` beziehen.
    let semesterIndex: Int

    /// Das Halbjahresergebnis, oder `nil`, wenn nichts erfasst ist.
    let result: Int?

    /// Der Schnitt des Fachs über alle Halbjahre mit Ergebnis.
    let average: Double?

    /// Ob das Fach in diesem Halbjahr belegt ist.
    let isActive: Bool

    /// Warum dieser Kurs nicht in Block I einfliesst, oder `nil`, wenn er es tut.
    ///
    /// Die Fachansicht braucht den Grund und nicht nur das Ob: „von dir
    /// geklammert" wird anders angezeigt als „automatisch geklammert", und der
    /// Schalter zum Klammern muss wissen, in welchem Zustand er steht.
    let bracketReason: BlockOneCalculator.BracketReason?

    /// Ob der Kurs erfasst ist, aber nicht in Block I einfliesst.
    var isExcluded: Bool { bracketReason != nil }

    /// Ob der Nutzer diesen Kurs selbst geklammert hat.
    var isManuallyBracketed: Bool { bracketReason == .manual }

    /// Ob sich dieser Kurs überhaupt klammern lässt.
    ///
    /// Prüfungsfächer nicht — dort steht der Schalter gesperrt, mit dem Grund
    /// daneben. Ihn wegzulassen wäre schlechter: dann fehlte die Erklärung.
    var allowsBracketing: Bool { !subject.isExamSubject }

    var id: PersistentIdentifier { subject.persistentModelID }
}

/// Rechnet die Kennzahlen der Fächerliste in einem Durchgang.
enum SubjectOverview {

    /// Die Kennzahlen aller Fächer für ein Halbjahr.
    ///
    /// Block I wird genau einmal für den gesamten Bestand gerechnet — die
    /// Auswahl der eingebrachten Kurse ist ein Wettbewerb zwischen den Fächern,
    /// pro Fach liesse sie sich nicht bestimmen.
    static func summaries(of subjects: [Subject], semesterIndex: Int) -> [SubjectSummary] {
        let inputs = subjects.map(SubjectInput.init)
        let reasons = BlockOneCalculator.calculate(for: inputs).bracketReasons

        return zip(subjects, inputs).map { subject, input in
            let semester = input.semesters.first { $0.index == semesterIndex }
            let courseIdentifier = BlockOneCalculator.CourseIdentifier(
                subjectID: input.id,
                semesterIndex: semesterIndex
            )

            return SubjectSummary(
                subject: subject,
                semesterIndex: semesterIndex,
                result: semester.flatMap(SubjectMath.result(for:)),
                average: SubjectMath.subjectAverage(for: input.semesters),
                isActive: subject.isActive(in: semesterIndex),
                bracketReason: reasons[courseIdentifier]
            )
        }
    }

    /// Die Kennzahlen eines einzelnen Fachs, gerechnet im Feld aller anderen.
    static func summary(
        for subject: Subject,
        semesterIndex: Int,
        among subjects: [Subject]
    ) -> SubjectSummary {
        let all = summaries(of: subjects, semesterIndex: semesterIndex)
        return all.first { $0.subject.persistentModelID == subject.persistentModelID }
            ?? SubjectSummary(
                subject: subject,
                semesterIndex: semesterIndex,
                result: nil,
                average: nil,
                isActive: subject.isActive(in: semesterIndex),
                bracketReason: nil
            )
    }
}
