import Foundation
import SwiftUI

/// Die Aufschlüsselung von Block I: dieselbe Rechnung wie auf dem Dashboard,
/// aber offen hingeschrieben.
///
/// Der Bildschirm zeigt nichts, was er selbst ausrechnet. Alles kommt aus
/// `BlockOneCalculator.calculate(for:)` — diese Struktur ordnet das Ergebnis nur
/// so, dass man es lesen kann: nach Fachtyp gruppiert, je Fach die vier
/// Halbjahre, und bei den Basisfächern in der Reihenfolge, in der sie um die
/// freien Plätze konkurrieren.
///
/// Sie liegt bewusst neben dem Rechenkern und nicht darin: der Kern beantwortet
/// „welche Kurse zählen", diese Struktur beantwortet „wie erzählt man das".
struct BlockOneBreakdown {

    // MARK: - Bausteine

    /// Wie ein einzelnes Halbjahr in die Rechnung eingeht.
    ///
    /// `notTaken` und `notRecorded` sind zwei verschiedene Dinge und dürfen nie
    /// zu „0 Punkte" verschmelzen: das eine Halbjahr läuft gar nicht, das andere
    /// läuft, hat aber noch keine Note.
    enum CourseState: Equatable {
        case included(points: Int)
        case excluded(points: Int)
        case notTaken
        case notRecorded

        var points: Int? {
            switch self {
            case .included(let points), .excluded(let points): points
            case .notTaken, .notRecorded: nil
            }
        }

        var isIncluded: Bool {
            if case .included = self { return true }
            return false
        }

        var isExcluded: Bool {
            if case .excluded = self { return true }
            return false
        }
    }

    /// Ein Halbjahr eines Fachs, so wie es auf dem Bildschirm steht.
    struct Course: Identifiable {
        let semesterIndex: Int
        let state: CourseState

        var id: Int { semesterIndex }
    }

    /// Ein Fach, wie der Bildschirm es braucht: die Rechenwerte und das, was
    /// man sieht.
    ///
    /// Trennt die Aufschlüsselung vom `@Model` — genau wie `SubjectInput` es für
    /// den Rechenkern tut. Testfälle lassen sich so ohne ModelContainer schreiben.
    struct SubjectPresentation {
        let name: String
        let color: Color
        let input: SubjectInput

        init(name: String, color: Color, input: SubjectInput) {
            self.name = name
            self.color = color
            self.input = input
        }

        init(_ subject: Subject) {
            self.init(name: subject.name, color: subject.color, input: SubjectInput(subject))
        }
    }

    /// Ein Fach mit seinen vier Halbjahren.
    struct SubjectEntry: Identifiable {
        let id: String
        let name: String
        let color: Color
        let kind: SubjectKind
        let courses: [Course]

        var includedCount: Int { courses.count { $0.state.isIncluded } }
        var excludedCount: Int { courses.count { $0.state.isExcluded } }

        /// Der Schnitt über die Halbjahre mit Ergebnis.
        ///
        /// Nach ihm sind die Basisfächer sortiert — er ist die beste Antwort auf
        /// „warum steht dieses Fach weiter unten als jenes".
        var recordedAverage: Double? {
            let points = courses.compactMap { $0.state.points }
            guard !points.isEmpty else { return nil }
            return Double(points.reduce(0, +)) / Double(points.count)
        }
    }

    /// Eine der drei Gruppen, mit der Bilanz ihrer Kurse.
    struct Group: Identifiable {
        let kind: SubjectKind
        /// Wie viele Kurse dieser Gruppe eingebracht werden.
        let includedCount: Int
        /// Wie viele Kurse dieser Gruppe überhaupt ein Ergebnis haben.
        let recordedCount: Int

        var excludedCount: Int { recordedCount - includedCount }
        var id: SubjectKind { kind }
    }

    // MARK: - Werte

    let outcome: BlockOneCalculator.Outcome

    /// Die Punktsumme der eingebrachten Kurse — der Zähler der Rechnung.
    let includedPointsTotal: Int

    /// Die drei Gruppen in der Reihenfolge, in der sie die Plätze belegen.
    let groups: [Group]

    let advancedSubjects: [SubjectEntry]
    let mandatorySubjects: [SubjectEntry]

    /// Die Basisfächer, nach Punktschnitt absteigend — die Reihenfolge, in der
    /// sie um die freien Plätze antreten.
    let optionalSubjects: [SubjectEntry]

    /// Nach welchem Basisfach nichts mehr eingebracht wird.
    ///
    /// Alles ab dem folgenden Fach fällt vollständig heraus. `nil`, wenn es
    /// nichts zu trennen gibt — weil kein Basisfach eingebracht wird oder weil
    /// alle Platz gefunden haben.
    let optionalCutIndex: Int?

    /// Die niedrigste Punktzahl, die es noch in Block I geschafft hat.
    let optionalThreshold: Int?

    /// Wie viele Basisfach-Ergebnisse um die freien Plätze konkurrieren.
    let optionalCandidateCount: Int

    /// Wie viele Plätze nach den Leistungs- und Kernfächern übrig bleiben.
    let optionalSlotCount: Int

    // MARK: - Aufbau

    init(subjects: [Subject]) {
        self.init(presentations: subjects.map(SubjectPresentation.init))
    }

    init(presentations: [SubjectPresentation]) {
        let inputs = presentations.map(\.input)
        let outcome = BlockOneCalculator.calculate(for: inputs)
        let included = Set(outcome.includedCourses)
        let pointsByCourse = Dictionary(
            uniqueKeysWithValues: BlockOneCalculator.availableCourses(in: inputs).map { ($0.id, $0.points) }
        )

        self.outcome = outcome
        self.includedPointsTotal = outcome.includedCourses.reduce(0) { $0 + (pointsByCourse[$1] ?? 0) }

        let entries = presentations.map { presentation in
            let input = presentation.input
            return SubjectEntry(
                id: input.id,
                name: presentation.name,
                color: presentation.color,
                kind: input.kind,
                courses: Semester.allIndices.map { index in
                    let identifier = BlockOneCalculator.CourseIdentifier(
                        subjectID: input.id,
                        semesterIndex: index
                    )
                    return Course(
                        semesterIndex: index,
                        state: Self.state(
                            points: pointsByCourse[identifier],
                            isIncluded: included.contains(identifier),
                            isActive: input.semesters.first { $0.index == index }?.isActive ?? false
                        )
                    )
                }
            )
        }

        advancedSubjects = entries.filter { $0.kind == .leistungsfach }
        mandatorySubjects = entries.filter { $0.kind == .kernfach }

        // Absteigend nach Schnitt, bei Gleichstand nach Name: die Liste liest sich
        // von „reicht sicher" nach „reicht nicht mehr". Fächer ganz ohne Ergebnis
        // stehen am Ende, sie treten gar nicht erst an.
        optionalSubjects = entries
            .filter { $0.kind == .basisfach }
            .sorted { left, right in
                let leftAverage = left.recordedAverage ?? -1
                let rightAverage = right.recordedAverage ?? -1
                if leftAverage != rightAverage { return leftAverage > rightAverage }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }

        groups = [
            Self.group(.leistungsfach, in: advancedSubjects),
            Self.group(.kernfach, in: mandatorySubjects),
            Self.group(.basisfach, in: optionalSubjects)
        ]

        // Die Trennlinie sitzt hinter dem letzten Fach, das noch etwas einbringt.
        // Damit gilt für alles darunter ohne Ausnahme: fällt heraus.
        let lastIncluded = optionalSubjects.lastIndex { $0.includedCount > 0 }
        if let lastIncluded, lastIncluded < optionalSubjects.count - 1 {
            optionalCutIndex = lastIncluded
        } else {
            optionalCutIndex = nil
        }

        optionalThreshold = optionalSubjects
            .flatMap(\.courses)
            .compactMap { $0.state.isIncluded ? $0.state.points : nil }
            .min()

        optionalCandidateCount = optionalSubjects.reduce(0) { total, entry in
            total + entry.courses.count { $0.state.points != nil }
        }

        let mandatoryIncluded = mandatorySubjects.reduce(0) { $0 + $1.includedCount }
        optionalSlotCount = max(0, BlockOneCalculator.nonAdvancedCourseCount - mandatoryIncluded)
    }

    // MARK: - Hilfen

    private static func state(
        points: Int?,
        isIncluded: Bool,
        isActive: Bool
    ) -> CourseState {
        guard let points else { return isActive ? .notRecorded : .notTaken }
        return isIncluded ? .included(points: points) : .excluded(points: points)
    }

    private static func group(_ kind: SubjectKind, in entries: [SubjectEntry]) -> Group {
        Group(
            kind: kind,
            includedCount: entries.reduce(0) { $0 + $1.includedCount },
            recordedCount: entries.reduce(0) { total, entry in
                total + entry.courses.count { $0.state.points != nil }
            }
        )
    }
}
