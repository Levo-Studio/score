import SwiftUI
import Testing
@testable import Score

/// Die Aufschlüsselung, die der Bildschirm anzeigt.
///
/// Die Erwartungswerte sind von Hand ausgerechnet und stehen als Literale im
/// Test. Sie prüfen genau das, was auf dem Bildschirm steht — Punktsumme,
/// Schnitt, Gruppenbilanz, Reihenfolge der Basisfächer und die Linie, ab der es
/// nicht mehr reicht.
@Suite("BlockOneBreakdown")
struct BlockOneBreakdownTests {

    /// Ein Jahrgang mit 48 verfügbaren Kursen — sechs mehr, als Block I fasst.
    ///
    /// Leistungsfächer 13/12/11, Kernfächer 10/9/8, dazu sechs Basisfächer. Nach
    /// den zwölf Kernfach-Kursen bleiben 18 Plätze für die 24 Basisfach-Kurse:
    /// 14, 13, 12 und 11 füllen sechzehn davon, die beiden Zehner aus `bf-e` die
    /// restlichen zwei. Heraus fallen die beiden Dreier aus `bf-e` und alle vier
    /// Kurse von `bf-f`.
    static let presentations: [BlockOneBreakdown.SubjectPresentation] = [
        presentation(subject("lf-a", .leistungsfach, allPoints: 13)),
        presentation(subject("lf-b", .leistungsfach, allPoints: 12)),
        presentation(subject("lf-c", .leistungsfach, allPoints: 11)),

        presentation(subject("kf-a", .kernfach, allPoints: 10)),
        presentation(subject("kf-b", .kernfach, allPoints: 9)),
        presentation(subject("kf-c", .kernfach, allPoints: 8)),

        presentation(subject("bf-f", .basisfach, allPoints: 2)),
        presentation(subject("bf-d", .basisfach, allPoints: 11)),
        presentation(subject("bf-a", .basisfach, allPoints: 14)),
        presentation(subject("bf-e", .basisfach, points: [10, 10, 3, 3])),
        presentation(subject("bf-c", .basisfach, allPoints: 12)),
        presentation(subject("bf-b", .basisfach, allPoints: 13))
    ]

    private static var breakdown: BlockOneBreakdown {
        BlockOneBreakdown(presentations: presentations)
    }

    // MARK: - Die Rechnung oben

    @Test("Die Punktsumme ist die Summe der eingebrachten Kurse")
    func includedPointsTotal() {
        let breakdown = Self.breakdown

        // Leistungsfächer 4 · (13 + 12 + 11) = 144, Kernfächer 4 · (10 + 9 + 8) = 108,
        // Basisfächer 4 · (14 + 13 + 12 + 11) + 10 + 10 = 220.
        #expect(breakdown.includedPointsTotal == 472)
        #expect(breakdown.outcome.includedCount == 42)
    }

    @Test("Schnitt, Block I und Note folgen aus der Punktsumme")
    func averageAndGrade() {
        let breakdown = Self.breakdown

        #expect(isClose(breakdown.outcome.averagePoints, 472.0 / 42.0))
        #expect(breakdown.outcome.blockOnePoints == 472)
        // 17/3 − (472/42)/3
        #expect(isClose(breakdown.outcome.expectedGrade, 17.0 / 3.0 - (472.0 / 42.0) / 3.0))
    }

    // MARK: - Die drei Gruppen

    @Test("Jede Gruppe zeigt, wie viele ihrer Kurse zählen")
    func groups() {
        let groups = Self.breakdown.groups

        #expect(groups.map(\.kind) == [.leistungsfach, .kernfach, .basisfach])
        #expect(groups[0].includedCount == 12)
        #expect(groups[0].excludedCount == 0)
        #expect(groups[1].includedCount == 12)
        #expect(groups[1].excludedCount == 0)
        #expect(groups[2].includedCount == 18)
        #expect(groups[2].recordedCount == 24)
        #expect(groups[2].excludedCount == 6)
    }

    @Test("Die freien Plätze sind die 30 minus die Kernfach-Kurse")
    func optionalSlots() {
        let breakdown = Self.breakdown

        #expect(breakdown.optionalSlotCount == 18)
        #expect(breakdown.optionalCandidateCount == 24)
    }

    // MARK: - Die Reihenfolge der Basisfächer

    @Test("Basisfächer stehen absteigend nach ihrem Schnitt")
    func optionalOrder() {
        #expect(Self.breakdown.optionalSubjects.map(\.id) == ["bf-a", "bf-b", "bf-c", "bf-d", "bf-e", "bf-f"])
    }

    @Test("Die Trennlinie steht hinter dem letzten Fach, das noch etwas einbringt")
    func cutLine() {
        let breakdown = Self.breakdown

        // bf-e bringt zwei seiner vier Kurse ein, bf-f gar keinen mehr.
        #expect(breakdown.optionalCutIndex == 4)
        #expect(breakdown.optionalThreshold == 10)
    }

    @Test("Unter der Trennlinie fällt jeder Kurs heraus")
    func everythingBelowTheCutIsExcluded() throws {
        let breakdown = Self.breakdown
        let cut = try #require(breakdown.optionalCutIndex)
        let below = breakdown.optionalSubjects.dropFirst(cut + 1)
        #expect(below.allSatisfy { $0.includedCount == 0 })
    }

    @Test("Ein Fach kann teils eingebracht, teils gestrichen sein")
    func splitSubject() {
        let entry = Self.breakdown.optionalSubjects.first { $0.id == "bf-e" }
        let states = entry?.courses.map(\.state)

        #expect(states == [
            .included(points: 10),
            .included(points: 10),
            .excluded(points: 3),
            .excluded(points: 3)
        ])
    }

    // MARK: - Halbjahre ohne Kurs

    @Test("Nicht belegt und ohne Note sind zwei verschiedene Zustände")
    func missingCourses() {
        let input = SubjectInput(
            id: "bf-lücke",
            kind: .basisfach,
            semesters: [
                semester(0, points: 9),
                SemesterInput(index: 1, entries: []),
                SemesterInput(index: 2, isActive: false, entries: [GradeInput(points: 7, kind: .written)])
            ]
        )
        let breakdown = BlockOneBreakdown(presentations: [Self.presentation(input)])
        let states = breakdown.optionalSubjects.first?.courses.map(\.state)

        // Das dritte Halbjahr hat eine erfasste Note, ist aber abgewählt — es
        // bleibt ein nicht belegtes Halbjahr und kein Kurs mit 7 Punkten. Das
        // vierte kommt im Datensatz gar nicht vor.
        #expect(states == [.included(points: 9), .notRecorded, .notTaken, .notTaken])
        #expect(breakdown.includedPointsTotal == 9)
    }

    // MARK: - Kursgrenze eines Fachs

    /// Derselbe Jahrgang, aber `bf-e` bringt nur seine besten zwei Ergebnisse ein.
    ///
    /// Am Ergebnis ändert das nichts — die beiden Dreier von `bf-e` fielen schon
    /// vorher heraus. Was sich ändert, ist der **Grund**: sie sind jetzt über der
    /// eigenen Grenze und nicht mehr von besseren Kursen verdrängt.
    static let limitedPresentations: [BlockOneBreakdown.SubjectPresentation] = presentations.map {
        guard $0.input.id == "bf-e" else { return $0 }
        var input = $0.input
        input.maximumContributedCourses = 2
        return BlockOneBreakdown.SubjectPresentation(name: $0.name, color: $0.color, input: input)
    }

    private static var limitedBreakdown: BlockOneBreakdown {
        BlockOneBreakdown(presentations: limitedPresentations)
    }

    @Test("Kurse über der Kursgrenze tragen einen eigenen Zustand")
    func coursesBeyondTheLimitAreMarked() {
        let entry = Self.limitedBreakdown.optionalSubjects.first { $0.id == "bf-e" }

        #expect(entry?.courses.map(\.state) == [
            .included(points: 10),
            .included(points: 10),
            .beyondLimit(points: 3),
            .beyondLimit(points: 3)
        ])
        #expect(entry?.courseLimit == 2)
    }

    @Test("Die Grenze ändert den Grund, nicht die Rechnung")
    func theLimitChangesTheReasonNotTheResult() {
        let plain = Self.breakdown
        let limited = Self.limitedBreakdown

        #expect(limited.includedPointsTotal == plain.includedPointsTotal)
        #expect(limited.outcome.includedCount == plain.outcome.includedCount)
        #expect(isClose(limited.outcome.averagePoints, plain.outcome.averagePoints))
    }

    @Test("Kurse über der Grenze treten nicht um die freien Plätze an")
    func cappedCoursesAreNoCandidates() {
        let limited = Self.limitedBreakdown

        // 24 erfasste Basisfach-Kurse, zwei davon über der Grenze von bf-e.
        #expect(limited.optionalCandidateCount == 22)
        #expect(limited.optionalSlotCount == 18)
        #expect(limited.groups[2].recordedCount == 24)
        #expect(limited.groups[2].includedCount == 18)
    }

    @Test("Was herausfällt, steht nach Fach und Grund gebündelt da")
    func droppedGroupsCarryTheReason() {
        let groups = Self.limitedBreakdown.droppedGroups

        // Erst die eigene Entscheidung, dann die Verdrängten.
        #expect(groups.map(\.subjectID) == ["bf-e", "bf-f"])
        #expect(groups.map(\.reason) == [.beyondSubjectLimit, .outranked])
        #expect(groups[0].courses.map(\.semesterIndex) == [2, 3])
        #expect(groups[0].courseLimit == 2)
        #expect(groups[1].courses.count == 4)
        #expect(Self.limitedBreakdown.hasSubjectLimits)
    }

    @Test("Ohne Grenze fällt alles aus demselben Grund heraus")
    func withoutLimitsEveryDropIsAnOutranking() {
        let groups = Self.breakdown.droppedGroups

        #expect(groups.map(\.subjectID) == ["bf-e", "bf-f"])
        #expect(groups.allSatisfy { $0.reason == .outranked })
        #expect(!Self.breakdown.hasSubjectLimits)
    }

    @Test("Ein begrenztes Fach tritt mit dem Schnitt seiner besten Kurse an")
    func competingAverageIgnoresCappedCourses() {
        let entry = Self.limitedBreakdown.optionalSubjects.first { $0.id == "bf-e" }

        // Erfasst sind 10, 10, 3 und 3 — antreten tun nur die beiden Zehner.
        #expect(isClose(entry?.recordedAverage ?? 0, 6.5))
        #expect(isClose(entry?.competingAverage ?? 0, 10))
    }

    // MARK: - Gruppen

    @Test("Jede Gruppe nennt, wie viele Fächer sie stellt")
    func groupsCountSubjects() {
        #expect(Self.breakdown.groups.map(\.subjectCount) == [3, 3, 6])
    }

    // MARK: - Hilfen

    private static func presentation(_ input: SubjectInput) -> BlockOneBreakdown.SubjectPresentation {
        BlockOneBreakdown.SubjectPresentation(name: input.id, color: .clear, input: input)
    }
}
