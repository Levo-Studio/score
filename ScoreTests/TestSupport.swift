import Foundation
@testable import Score

/// Vergleicht zwei Fliesskommazahlen mit einer für Notenrechnungen sinnvollen
/// Toleranz.
///
/// Die erwarteten Werte in den Tests sind von Hand ausgerechnet und teilweise
/// periodisch (etwa 17/3). Ein exakter Vergleich würde an der letzten Stelle
/// scheitern, ohne dass die Rechnung falsch wäre.
func isClose(_ value: Double, _ expected: Double, tolerance: Double = 0.0001) -> Bool {
    abs(value - expected) <= tolerance
}

// MARK: - Aufbau von Testfällen

/// Ein Halbjahr mit genau einer schriftlichen Leistung.
///
/// Eine einzelne automatisch gewichtete Leistung bekommt 100 % und damit ist das
/// Halbjahresergebnis exakt die eingetragene Punktzahl. So lassen sich die Tests
/// zur Kursauswahl über die gewünschten Punktzahlen schreiben, ohne die Rechnung
/// innerhalb des Fachs mitzudenken.
func semester(_ index: Int, points: Int) -> SemesterInput {
    SemesterInput(index: index, entries: [GradeInput(points: points, kind: .written)])
}

/// Ein Fach, dessen Halbjahre der Reihe nach die angegebenen Punktzahlen ergeben.
func subject(
    _ id: String,
    _ kind: SubjectKind,
    points: [Int],
    limit: Int? = nil
) -> SubjectInput {
    SubjectInput(
        id: id,
        kind: kind,
        semesters: points.enumerated().map { semester($0.offset, points: $0.element) },
        maximumContributedCourses: limit
    )
}

/// Ein Fach mit vier Halbjahren derselben Punktzahl.
func subject(
    _ id: String,
    _ kind: SubjectKind,
    allPoints: Int,
    limit: Int? = nil
) -> SubjectInput {
    subject(id, kind, points: Array(repeating: allPoints, count: 4), limit: limit)
}

extension BlockOneCalculator.CourseIdentifier {
    /// Kurzschreibweise für Erwartungen wie `course("wbf-b", 2)`.
    init(_ subjectID: String, _ semesterIndex: Int) {
        self.init(subjectID: subjectID, semesterIndex: semesterIndex)
    }
}

func course(_ subjectID: String, _ semesterIndex: Int) -> BlockOneCalculator.CourseIdentifier {
    BlockOneCalculator.CourseIdentifier(subjectID, semesterIndex)
}
