import Foundation
import SwiftUI

/// Die Aufschlüsselung von Block I: dieselbe Rechnung wie auf dem Dashboard,
/// aber offen hingeschrieben.
///
/// Der Bildschirm zeigt nichts, was er selbst ausrechnet. Alles kommt aus
/// `BlockOneCalculator.calculate(for:)` — diese Struktur ordnet das Ergebnis nur
/// so, dass man es lesen kann: nach Fachtyp gruppiert, je Fach die vier
/// Halbjahre, und bei den klammerbaren Fächern in der Reihenfolge, in der Score
/// von unten her klammert.
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
        /// Geklammert — mit dem Grund, aus dem es geschah.
        case bracketed(points: Int, reason: ExclusionReason)
        case notTaken
        case notRecorded

        var points: Int? {
            switch self {
            case .included(let points), .bracketed(let points, _): points
            case .notTaken, .notRecorded: nil
            }
        }

        var isIncluded: Bool {
            if case .included = self { return true }
            return false
        }

        /// Erfasst, aber nicht gezählt — gleich aus welchem Grund.
        var isExcluded: Bool {
            exclusionReason != nil
        }

        /// Warum dieser Kurs nicht zählt, sofern er erfasst ist und nicht zählt.
        var exclusionReason: ExclusionReason? {
            switch self {
            case .bracketed(_, let reason): reason
            case .included, .notTaken, .notRecorded: nil
            }
        }
    }

    /// Warum ein erfasster Kurs nicht in Block I eingeht.
    ///
    /// Dieselben Gründe wie im Rechenkern, hier nur in der Reihenfolge, in
    /// der der Bildschirm sie erzählt: erst die Entscheidungen des Nutzers, dann
    /// die von Score.
    typealias ExclusionReason = BlockOneCalculator.BracketReason

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

        /// Ob dieses Fach eines der beiden mündlichen Prüfungsfächer ist.
        let isOralExamSubject: Bool

        /// Ob sich die Kurse dieses Fachs überhaupt klammern lassen.
        let allowsBracketing: Bool

        var includedCount: Int { courses.count { $0.state.isIncluded } }
        var excludedCount: Int { courses.count { $0.state.isExcluded } }

        /// Wie viele Halbjahre dieses Fachs überhaupt ein Ergebnis haben.
        var recordedCount: Int { courses.count { $0.state.points != nil } }

        /// Der Schnitt über die Halbjahre mit Ergebnis.
        ///
        /// Nach ihm sind die klammerbaren Fächer sortiert — er ist die beste
        /// Antwort auf „warum steht dieses Fach weiter unten als jenes".
        var recordedAverage: Double? {
            Self.average(of: courses.compactMap { $0.state.points })
        }

        /// Der Schnitt der Kurse, die überhaupt noch zur Klammerung anstehen.
        ///
        /// Bringt ein Fach nur seine besten zwei ein, ist es mit diesen zwei
        /// stärker, als sein Gesamtschnitt vermuten lässt — und genau so steht es
        /// da, wenn Score von unten her klammert. Nach diesem Wert ist die Liste
        /// sortiert. Von Hand geklammerte Kurse zählen hier ebenfalls nicht mit:
        /// über sie ist bereits entschieden.
        var competingAverage: Double? {
            Self.average(
                of: courses.compactMap { course in
                    switch course.state.exclusionReason {
                    case .beyondSubjectLimit, .manual, .beyondCourseCap: nil
                    case .automatic, .none: course.state.points
                    }
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
    /// Ein Fach kann in mehreren Gründen auftauchen: zwei Kurse über der eigenen
    /// Grenze, einer von Hand geklammert, ein vierter automatisch. Deshalb ist
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
    }

    /// Eine der fünf Prüfungen, so wie sie auf dem Bildschirm steht.
    struct ExamEntry: Identifiable {
        let subjectID: String
        let name: String
        let color: Color
        let kind: SubjectKind
        let exam: BlockTwoCalculator.Exam

        var id: String { subjectID }

        /// Ob dieses Fach doppelt in den Kursblock zählt.
        let isDoubleWeighted: Bool
    }

    // MARK: - Werte

    /// Das Gesamtergebnis: Kursblock, Prüfungsblock, Gesamtpunktzahl, Note.
    let result: AbiturResult.Outcome

    /// Der Kursblock allein — die Grösse, um die es auf diesem Bildschirm
    /// überwiegend geht.
    var outcome: BlockOneCalculator.Outcome { result.courseBlock }

    /// Die fünf Prüfungen, erst die schriftlichen, dann die mündlichen.
    let exams: [ExamEntry]

    /// Die beiden doppelt gewerteten Leistungsfächer, mit Namen.
    var doubleWeightedSubjects: [SubjectEntry] {
        advancedSubjects.filter { outcome.doubleWeightedSubjectIDs.contains($0.id) }
    }

    /// Die Punktsumme der eingebrachten Kurse — der Zähler der Rechnung.
    let includedPointsTotal: Int

    /// Die drei Gruppen in der Reihenfolge, in der sie Block I füllen.
    let groups: [Group]

    let advancedSubjects: [SubjectEntry]
    let mandatorySubjects: [SubjectEntry]

    /// Die Wahl-Basisfächer, nach Punktschnitt absteigend — die Reihenfolge, in der
    /// Score von unten her klammert.
    let optionalSubjects: [SubjectEntry]

    /// Die mündlichen Prüfungsfächer, in der Reihenfolge der Fächerliste.
    ///
    /// Sie stehen zusätzlich in `mandatorySubjects` beziehungsweise
    /// `optionalSubjects` — hier gebündelt, weil der Bildschirm ihre besondere
    /// Stellung eigens erklärt.
    let oralExamSubjects: [SubjectEntry]

    /// Die Wahl-Basisfächer, an denen Score überhaupt klammern darf.
    ///
    /// Also `optionalSubjects` ohne die mündlichen Prüfungsfächer. An denen ist
    /// nichts zu klammern; sie stehen im Bildschirm bei den festen Fächern.
    /// ``optionalCutIndex`` zählt in diese Liste, nicht in `optionalSubjects`.
    let bracketableSubjects: [SubjectEntry]

    /// Nach welchem klammerbaren Fach nichts mehr eingebracht wird.
    ///
    /// Alles ab dem folgenden Fach ist vollständig geklammert. `nil`, wenn es
    /// nichts zu trennen gibt — weil kein Wahl-Basisfach eingebracht wird oder weil
    /// nichts geklammert werden musste.
    let optionalCutIndex: Int?

    /// Die niedrigste Punktzahl, die es noch in Block I geschafft hat.
    let optionalThreshold: Int?

    /// Wie viele Wahl-Basisfach-Ergebnisse überhaupt noch zur Klammerung anstehen.
    let optionalCandidateCount: Int

    /// Wie viele der 42 Kurse nach den anrechnungspflichtigen noch offen sind.
    let optionalSlotCount: Int

    /// Alles, was geklammert ist — nach Fach und Grund gebündelt.
    ///
    /// Die Reihenfolge ist die des Bildschirms: erst die Entscheidungen des
    /// Nutzers — von Hand geklammert, dann über die eigene Kursgrenze —, danach
    /// das, was Score von sich aus geklammert hat.
    let droppedGroups: [DroppedGroup]

    /// Ob überhaupt ein Fach eine Kursgrenze gesetzt hat.
    var hasSubjectLimits: Bool {
        droppedGroups.contains { $0.reason == .beyondSubjectLimit }
    }

    /// Ob überhaupt ein Kurs von Hand geklammert ist.
    var hasManualBrackets: Bool {
        droppedGroups.contains { $0.reason == .manual }
    }

    // MARK: - Aufbau

    init(subjects: [Subject]) {
        self.init(presentations: subjects.map(SubjectPresentation.init))
    }

    init(presentations: [SubjectPresentation]) {
        let inputs = presentations.map(\.input)
        let result = AbiturResult.calculate(for: inputs)
        let outcome = result.courseBlock
        let included = Set(outcome.includedCourses)
        let reasons = outcome.bracketReasons
        // Zwei Fächer mit derselben Kennung sollte es nicht geben — doppelt
        // eingespielte Datensätze oder ein Sync über zwei Geräte bringen sie
        // trotzdem hervor. `uniqueKeysWithValues` bricht dabei ab und die
        // Aufschlüsselung liesse sich gar nicht mehr öffnen. Der erste Kurs
        // gewinnt, wie zwei Zeilen weiter unten bei den Fächern selbst.
        let pointsByCourse = Dictionary(
            BlockOneCalculator.availableCourses(in: inputs).map { ($0.id, $0.points) },
            uniquingKeysWith: { first, _ in first }
        )

        self.result = result
        self.includedPointsTotal = outcome.includedCourses.reduce(0) { $0 + (pointsByCourse[$1] ?? 0) }

        // Die Prüfungen bekommen Namen und Farbe ihres Fachs. Die Reihenfolge
        // kommt aus dem Rechenkern und wird hier nicht neu erfunden.
        let byIdentifier = Dictionary(
            presentations.map { ($0.input.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        exams = result.examBlock.exams.compactMap { exam in
            guard let presentation = byIdentifier[exam.id] else { return nil }
            return ExamEntry(
                subjectID: exam.id,
                name: presentation.name,
                color: presentation.color,
                kind: presentation.input.kind,
                exam: exam,
                isDoubleWeighted: outcome.doubleWeightedSubjectIDs.contains(exam.id)
            )
        }

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
                            reason: reasons[identifier],
                            isActive: input.semesters.first { $0.index == index }?.isActive ?? false
                        )
                    )
                },
                courseLimit: input.effectiveCourseLimit,
                isOralExamSubject: input.countsAsOralExamSubject,
                allowsBracketing: input.allowsBracketing
            )
        }

        advancedSubjects = entries.filter { $0.kind == .leistungsfach }
        mandatorySubjects = entries.filter { $0.kind == .pflichtBasisfach }
        oralExamSubjects = entries.filter(\.isOralExamSubject)

        // Absteigend nach Schnitt, bei Gleichstand nach Name: die Liste liest sich
        // von „bleibt sicher drin" nach „wird geklammert". Fächer ganz ohne
        // Ergebnis stehen am Ende, bei ihnen ist nichts zu klammern.
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

        bracketableSubjects = optionalSubjects.filter(\.allowsBracketing)

        // Die Trennlinie sitzt hinter dem letzten Fach, das noch etwas einbringt.
        // Damit gilt für alles darunter ohne Ausnahme: vollständig geklammert.
        let lastIncluded = bracketableSubjects.lastIndex { $0.includedCount > 0 }
        if let lastIncluded, lastIncluded < bracketableSubjects.count - 1 {
            optionalCutIndex = lastIncluded
        } else {
            optionalCutIndex = nil
        }

        optionalThreshold = bracketableSubjects
            .flatMap(\.courses)
            .compactMap { $0.state.isIncluded ? $0.state.points : nil }
            .min()

        // Kurse über einer gesetzten Kursgrenze und von Hand geklammerte stehen
        // gar nicht mehr zur Klammerung an — über sie ist entschieden.
        optionalCandidateCount = bracketableSubjects.reduce(0) { total, entry in
            total + entry.courses.count { course in
                guard course.state.points != nil else { return false }
                switch course.state.exclusionReason {
                case .beyondSubjectLimit, .manual, .beyondCourseCap: return false
                case .automatic, .none: return true
                }
            }
        }

        // Was nach den anrechnungspflichtigen Kursen von den 40 übrig ist. Die
        // Zahl kommt aus dem Ergebnis und nicht aus einer zweiten Rechnung: alles
        // Eingebrachte, das nicht aus einem klammerbaren Wahl-Basisfach stammt.
        let protectedIncluded = entries
            .filter { !($0.kind == .wahlBasisfach && $0.allowsBracketing) }
            .reduce(0) { $0 + $1.includedCount }
        optionalSlotCount = max(0, BlockOneCalculator.totalCourseCount - protectedIncluded)

        droppedGroups = Self.droppedGroups(
            in: advancedSubjects + mandatorySubjects + optionalSubjects
        )
    }

    // MARK: - Hilfen

    private static func state(
        points: Int?,
        isIncluded: Bool,
        reason: ExclusionReason?,
        isActive: Bool
    ) -> CourseState {
        guard let points else { return isActive ? .notRecorded : .notTaken }
        if isIncluded { return .included(points: points) }
        // Ohne Grund kann ein erfasster Kurs nicht draussen sein. Sollte es doch
        // je vorkommen, ist „Score hat geklammert" die ehrlichste Auskunft.
        return .bracketed(points: points, reason: reason ?? .automatic)
    }

    private static func group(_ kind: SubjectKind, in entries: [SubjectEntry]) -> Group {
        Group(
            kind: kind,
            includedCount: entries.reduce(0) { $0 + $1.includedCount },
            recordedCount: entries.reduce(0) { $0 + $1.recordedCount },
            subjectCount: entries.count
        )
    }

    /// Bündelt alle geklammerten Kurse nach Fach und Grund.
    private static func droppedGroups(in entries: [SubjectEntry]) -> [DroppedGroup] {
        // Erst die Entscheidungen des Nutzers, dann die von Score: Wer die Liste
        // liest, soll zuerst wiederfinden, was er selbst getan hat.
        let reasons: [ExclusionReason] = [.manual, .beyondSubjectLimit, .beyondCourseCap, .automatic]

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
