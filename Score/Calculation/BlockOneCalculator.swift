import Foundation

/// Die Auswahl der Kurse für Block I und der daraus folgende Schnitt.
///
/// ## Die Regel
///
/// Das Abitur in Baden-Württemberg besteht aus zwei Blöcken. Block I sind die
/// Halbjahresergebnisse der Kursstufe, Block II die Prüfungen. Score rechnet
/// Block I.
///
/// In Block I gehen **42 Halbjahresergebnisse** ein:
///
/// - **12 aus den drei Leistungsfächern.** Jedes Leistungsfach bringt alle vier
///   Halbjahre mit. Sie sind gesetzt und lassen sich nicht abwählen.
/// - **30 aus den übrigen Fächern.** Davon sind die Kernfächer — Deutsch,
///   Mathematik, die Fremdsprache, Geschichte, Gemeinschaftskunde und eine
///   Naturwissenschaft — nicht ausschliessbar. Sie zählen, wie sie stehen.
///
/// Die Plätze, die nach den Kernfächern übrig bleiben, füllt Score mit den
/// **besten verfügbaren Basisfach-Ergebnissen**. Wer mehr belegt hat als nötig,
/// wird die schwächsten Kurse los — genau das ist der Sinn der Regel.
///
/// ## Warum die Auswahl das eigentliche Problem ist
///
/// Die Rechnung selbst ist ein Mittelwert. Interessant ist, *welche* Kurse
/// hineingehen. Ein sehr gutes Basisfach kann ein schwaches verdrängen, ein
/// schwaches Kernfach dagegen nie — deshalb sind Kernfächer und Basisfächer im
/// Datenmodell zwei verschiedene Typen und nicht bloss ein Namensabgleich.
///
/// ## Abweichung von der amtlichen Regel
///
/// Die amtliche Fassung kennt zusätzlich zwei doppelt gewertete Leistungsfächer
/// und rechnet mit 40 Ergebnissen durch 48. Diese App folgt bewusst der
/// vereinfachten Fassung aus dem Prototyp der Design-Datei: 42 Ergebnisse ohne
/// Doppelwertung. Das ist eine Produktentscheidung, kein Versehen.
enum BlockOneCalculator {

    /// Wie viele Halbjahresergebnisse insgesamt eingebracht werden.
    static let totalCourseCount = 42

    /// Wie viele davon aus den Nicht-Leistungsfächern kommen.
    ///
    /// 42 gesamt minus die 12 Kurse der drei Leistungsfächer.
    static let nonAdvancedCourseCount = 30

    /// Ein einzelnes Halbjahresergebnis, wie es in die Auswahl eingeht.
    struct Course: Sendable, Equatable, Identifiable {
        /// Fach und Halbjahr zusammen — eindeutig über alle Kurse.
        var id: CourseIdentifier
        var points: Int
        var kind: SubjectKind
    }

    /// Verweist auf ein Halbjahr eines Fachs.
    struct CourseIdentifier: Sendable, Equatable, Hashable {
        var subjectID: String
        var semesterIndex: Int

        init(subjectID: String, semesterIndex: Int) {
            self.subjectID = subjectID
            self.semesterIndex = semesterIndex
        }
    }

    /// Das Ergebnis der Rechnung.
    struct Outcome: Sendable, Equatable {
        /// Der erwartete Abischnitt, 1,0 bis 4,0.
        var expectedGrade: Double
        /// Die Punktsumme für Block I.
        var blockOnePoints: Int
        /// Der Punkteschnitt der eingebrachten Kurse.
        var averagePoints: Double
        /// Die Kurse, die eingebracht werden.
        var includedCourses: [CourseIdentifier]
        /// Die Kurse, die erfasst sind, aber nicht in den Score einfliessen.
        var excludedCourses: Set<CourseIdentifier>
        /// Wie viele Kurse eingebracht werden.
        var includedCount: Int { includedCourses.count }
        /// Wie viele Kurse überhaupt ein Ergebnis haben.
        var recordedCount: Int
    }

    // MARK: - Rechnung

    /// Wählt die Kurse aus und rechnet Block I.
    static func calculate(for subjects: [SubjectInput]) -> Outcome {
        let courses = availableCourses(in: subjects)

        // Leistungsfächer sind gesetzt, alle zwölf Kurse.
        let advanced = courses.filter { $0.kind == .leistungsfach }

        // Kernfächer sind ebenfalls gesetzt, zählen aber gegen die 30 Plätze.
        let mandatory = courses.filter { $0.kind == .kernfach }

        // Basisfächer konkurrieren um die restlichen Plätze — bestes Ergebnis zuerst.
        // Bei Gleichstand entscheidet die Kennung, damit die Auswahl stabil bleibt
        // und nicht bei jedem Aufruf zwischen zwei gleich guten Kursen springt.
        let optional = courses
            .filter { $0.kind == .basisfach }
            .sorted { left, right in
                if left.points != right.points { return left.points > right.points }
                if left.id.subjectID != right.id.subjectID {
                    return left.id.subjectID < right.id.subjectID
                }
                return left.id.semesterIndex < right.id.semesterIndex
            }

        let freeSlots = max(0, nonAdvancedCourseCount - mandatory.count)
        let selected = optional.prefix(freeSlots)
        let dropped = optional.dropFirst(freeSlots)

        let included = advanced + mandatory + selected
        let averagePoints = included.isEmpty
            ? 0
            : Double(included.reduce(0) { $0 + $1.points }) / Double(included.count)

        return Outcome(
            expectedGrade: expectedGrade(forAveragePoints: averagePoints),
            blockOnePoints: Int((averagePoints * Double(totalCourseCount)).rounded()),
            averagePoints: averagePoints,
            includedCourses: included.map(\.id),
            excludedCourses: Set(dropped.map(\.id)),
            recordedCount: courses.count
        )
    }

    /// Sammelt alle Halbjahre, die ein Ergebnis haben.
    ///
    /// Nicht belegte Halbjahre und solche ohne erfasste Leistung fallen hier schon
    /// heraus — sie sind kein Kurs mit 0 Punkten, sondern schlicht kein Kurs.
    static func availableCourses(in subjects: [SubjectInput]) -> [Course] {
        subjects.flatMap { subject in
            subject.semesters.compactMap { semester in
                guard let points = SubjectMath.result(for: semester) else { return nil }
                return Course(
                    id: CourseIdentifier(
                        subjectID: subject.id,
                        semesterIndex: semester.index
                    ),
                    points: points,
                    kind: subject.kind
                )
            }
        }
    }

    /// Rechnet den Punkteschnitt in den erwarteten Abischnitt um.
    ///
    /// Dieselbe Umrechnung wie bei einer einzelnen Note, aber auf 4,0 gedeckelt:
    /// wer Block I besteht, kann nicht schlechter als 4,0 herauskommen.
    static func expectedGrade(forAveragePoints points: Double) -> Double {
        min(4, max(1, 17.0 / 3.0 - points / 3.0))
    }
}
