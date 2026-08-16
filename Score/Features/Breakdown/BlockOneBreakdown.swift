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
        /// Von besseren Basisfach-Ergebnissen aus den freien Plätzen verdrängt.
        case excluded(points: Int)
        /// Über der Kursgrenze, die für dieses Fach gesetzt ist. Dieser Kurs ist
        /// nie in den Wettbewerb gegangen — der Grund ist ein anderer, und der
        /// Bildschirm muss ihn anders benennen.
        case beyondLimit(points: Int)
        case notTaken
        case notRecorded

        var points: Int? {
            switch self {
            case .included(let points), .excluded(let points), .beyondLimit(let points): points
            case .notTaken, .notRecorded: nil
            }
        }

        var isIncluded: Bool {
            if case .included = self { return true }
            return false
        }

        /// Erfasst, aber nicht gezählt — gleich aus welchem Grund.
        var isExcluded: Bool {
            switch self {
            case .excluded, .beyondLimit: true
            case .included, .notTaken, .notRecorded: false
            }
        }

        /// Warum dieser Kurs nicht zählt, sofern er erfasst ist und nicht zählt.
        var exclusionReason: ExclusionReason? {
            switch self {
            case .excluded: .outranked
            case .beyondLimit: .beyondSubjectLimit
            case .included, .notTaken, .notRecorded: nil
            }
        }
    }

    /// Warum ein erfasster Kurs nicht in Block I eingeht.
    enum ExclusionReason: Equatable, Hashable {
        /// Es gab bessere Basisfach-Ergebnisse für die freien Plätze.
        case outranked
        /// Das Fach bringt nur eine bestimmte Zahl seiner Ergebnisse ein.
        case beyondSubjectLimit
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

        /// Die gesetzte Kursgrenze dieses Fachs, sofern sie greift.
        let courseLimit: Int?

        var includedCount: Int { courses.count { $0.state.isIncluded } }
        var excludedCount: Int { courses.count { $0.state.isExcluded } }

        /// Wie viele Halbjahre dieses Fachs überhaupt ein Ergebnis haben.
        var recordedCount: Int { courses.count { $0.state.points != nil } }

        /// Der Schnitt über die Halbjahre mit Ergebnis.
        ///
        /// Nach ihm sind die Basisfächer sortiert — er ist die beste Antwort auf
        /// „warum steht dieses Fach weiter unten als jenes".
        var recordedAverage: Double? {
            Self.average(of: courses.compactMap { $0.state.points })
        }

        /// Der Schnitt der Kurse, die tatsächlich um einen Platz antreten.
        ///
        /// Bringt ein Fach nur seine besten zwei ein, ist es mit diesen zwei
        /// stärker, als sein Gesamtschnitt vermuten lässt — und genau so tritt es
        /// gegen die anderen an. Nach diesem Wert ist die Liste sortiert.
        var competingAverage: Double? {
            Self.average(
                of: courses.compactMap { course in
                    course.state.exclusionReason == .beyondSubjectLimit ? nil : course.state.points
                }
            )
        }

        private static func average(of points: [Int]) -> Double? {
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
        /// Wie viele Fächer diese Gruppe stellt — die zweite Zahl in „12 aus drei
        /// Leistungsfächern".
        let subjectCount: Int

        var excludedCount: Int { recordedCount - includedCount }
        var id: SubjectKind { kind }
    }

    /// Ein Fach mit den Kursen, die aus demselben Grund herausfallen.
    ///
    /// Ein Fach kann in beiden Gründen auftauchen: zwei Kurse über der eigenen
    /// Grenze, ein dritter zu schwach für die letzten freien Plätze. Deshalb ist
    /// der Grund Teil der Identität und nicht nur ein Merkmal.
    struct DroppedGroup: Identifiable {
        let subjectID: String
        let name: String
        let color: Color
        let reason: ExclusionReason
        let courses: [Course]

        /// Die Kursgrenze des Fachs — die Zahl, die im Grund genannt wird.
        let courseLimit: Int?

        var id: String { "\(subjectID)-\(reason)" }

        /// Die höchste Punktzahl, die hier herausfällt — die Zahl, an der man
        /// den Abstand zur Grenze abliest.
        var bestPoints: Int? { courses.compactMap { $0.state.points }.max() }
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

    /// Alles, was herausfällt — nach Fach und Grund gebündelt.
    ///
    /// Die Reihenfolge ist die des Bildschirms: erst die Kurse, die eine gesetzte
    /// Kursgrenze ausklammert (die Entscheidung des Nutzers), danach die, denen
    /// bessere Ergebnisse den Platz genommen haben.
    let droppedGroups: [DroppedGroup]

    /// Ob überhaupt ein Fach eine Kursgrenze gesetzt hat.
    var hasSubjectLimits: Bool {
        droppedGroups.contains { $0.reason == .beyondSubjectLimit }
    }

    // MARK: - Aufbau

    init(subjects: [Subject]) {
        self.init(presentations: subjects.map(SubjectPresentation.init))
    }

    init(presentations: [SubjectPresentation]) {
        let inputs = presentations.map(\.input)
        let outcome = BlockOneCalculator.calculate(for: inputs)
        let included = Set(outcome.includedCourses)
        let beyondLimit = outcome.coursesBeyondSubjectLimit
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
                            isBeyondLimit: beyondLimit.contains(identifier),
                            isActive: input.semesters.first { $0.index == index }?.isActive ?? false
                        )
                    )
                },
                courseLimit: input.effectiveCourseLimit
            )
        }

        advancedSubjects = entries.filter { $0.kind == .leistungsfach }
        mandatorySubjects = entries.filter { $0.kind == .pflichtBasisfach }

        // Absteigend nach Schnitt, bei Gleichstand nach Name: die Liste liest sich
        // von „reicht sicher" nach „reicht nicht mehr". Fächer ganz ohne Ergebnis
        // stehen am Ende, sie treten gar nicht erst an.
        optionalSubjects = entries
            .filter { $0.kind == .wahlBasisfach }
            .sorted { left, right in
                let leftAverage = left.competingAverage ?? -1
                let rightAverage = right.competingAverage ?? -1
                if leftAverage != rightAverage { return leftAverage > rightAverage }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }

        groups = [
            Self.group(.leistungsfach, in: advancedSubjects),
            Self.group(.pflichtBasisfach, in: mandatorySubjects),
            Self.group(.wahlBasisfach, in: optionalSubjects)
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

        // Kurse über einer gesetzten Kursgrenze treten gar nicht erst an — sie
        // zählen deshalb auch nicht als Bewerber um die freien Plätze.
        optionalCandidateCount = optionalSubjects.reduce(0) { total, entry in
            total + entry.courses.count {
                $0.state.points != nil && $0.state.exclusionReason != .beyondSubjectLimit
            }
        }

        let mandatoryIncluded = mandatorySubjects.reduce(0) { $0 + $1.includedCount }
        optionalSlotCount = max(0, BlockOneCalculator.nonAdvancedCourseCount - mandatoryIncluded)

        // Erst die Kurse, die eine gesetzte Grenze ausklammert, dann die
        // verdrängten: Der Nutzer soll seine eigene Entscheidung zuerst
        // wiederfinden und danach lesen, was die Rechnung von sich aus streicht.
        droppedGroups = Self.droppedGroups(
            in: advancedSubjects + mandatorySubjects + optionalSubjects
        )
    }

    // MARK: - Hilfen

    private static func state(
        points: Int?,
        isIncluded: Bool,
        isBeyondLimit: Bool,
        isActive: Bool
    ) -> CourseState {
        guard let points else { return isActive ? .notRecorded : .notTaken }
        if isIncluded { return .included(points: points) }
        return isBeyondLimit ? .beyondLimit(points: points) : .excluded(points: points)
    }

    private static func group(_ kind: SubjectKind, in entries: [SubjectEntry]) -> Group {
        Group(
            kind: kind,
            includedCount: entries.reduce(0) { $0 + $1.includedCount },
            recordedCount: entries.reduce(0) { $0 + $1.recordedCount },
            subjectCount: entries.count
        )
    }

    /// Bündelt alle nicht gezählten Kurse nach Fach und Grund.
    private static func droppedGroups(in entries: [SubjectEntry]) -> [DroppedGroup] {
        let reasons: [ExclusionReason] = [.beyondSubjectLimit, .outranked]

        return reasons.flatMap { reason in
            entries.compactMap { entry -> DroppedGroup? in
                let courses = entry.courses.filter { $0.state.exclusionReason == reason }
                guard !courses.isEmpty else { return nil }
                return DroppedGroup(
                    subjectID: entry.id,
                    name: entry.name,
                    color: entry.color,
                    reason: reason,
                    courses: courses,
                    courseLimit: entry.courseLimit
                )
            }
        }
    }
}
