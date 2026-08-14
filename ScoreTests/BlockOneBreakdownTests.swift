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

    // MARK: - Hilfen

    private static func presentation(_ input: SubjectInput) -> BlockOneBreakdown.SubjectPresentation {
        BlockOneBreakdown.SubjectPresentation(name: input.id, color: .clear, input: input)
    }
}
