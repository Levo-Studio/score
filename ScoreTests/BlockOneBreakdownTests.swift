import SwiftUI
import Testing
@testable import Score

/// Die Aufschlüsselung, die der Bildschirm anzeigt.
///
/// Die Erwartungswerte sind von Hand ausgerechnet und stehen als Literale im
/// Test. Sie prüfen genau das, was auf dem Bildschirm steht — Punktsumme,
/// Schnitt, Gruppenbilanz, Reihenfolge der Wahl-Basisfächer und die Linie, ab der es
/// nicht mehr reicht.
@Suite("BlockOneBreakdown")
struct BlockOneBreakdownTests {

    /// Ein Jahrgang mit 46 verfügbaren Kursen — sechs mehr, als eingebracht werden.
    ///
    /// Leistungsfächer 13/12/11, Pflicht-Basisfächer 10/9/8, dazu sechs
    /// Wahl-Basisfächer. Nach den zwölf Leistungsfach- und zwölf
    /// Pflicht-Basisfach-Kursen bleiben 16 Plätze für die 22 Wahl-Basisfach-Kurse:
    /// `bf-a` (4), `bf-b` (4), `bf-c` (2) und `bf-d` (4) füllen vierzehn davon, die
    /// beiden Zehner aus `bf-e` die restlichen zwei. Heraus fallen die beiden
    /// Dreier aus `bf-e` und alle vier Kurse von `bf-f`.
    static let presentations: [BlockOneBreakdown.SubjectPresentation] = [
        presentation(subject("lf-a", .leistungsfach, allPoints: 13)),
        presentation(subject("lf-b", .leistungsfach, allPoints: 12)),
        presentation(subject("lf-c", .leistungsfach, allPoints: 11)),

        presentation(subject("kf-a", .pflichtBasisfach, allPoints: 10)),
        presentation(subject("kf-b", .pflichtBasisfach, allPoints: 9)),
        presentation(subject("kf-c", .pflichtBasisfach, allPoints: 8)),

        presentation(subject("bf-f", .wahlBasisfach, allPoints: 2)),
        presentation(subject("bf-d", .wahlBasisfach, allPoints: 11)),
        presentation(subject("bf-a", .wahlBasisfach, allPoints: 14)),
        presentation(subject("bf-e", .wahlBasisfach, points: [10, 10, 3, 3])),
        presentation(subject("bf-c", .wahlBasisfach, points: [12, 12])),
        presentation(subject("bf-b", .wahlBasisfach, allPoints: 13))
    ]

    private static var breakdown: BlockOneBreakdown {
        BlockOneBreakdown(presentations: presentations)
    }

    // MARK: - Die Rechnung oben

    @Test("Die Punktsumme ist die Summe der eingebrachten Kurse")
    func includedPointsTotal() {
        let breakdown = Self.breakdown

        // Leistungsfächer 4 · (13 + 12 + 11) = 144, Pflicht-Basisfächer
        // 4 · (10 + 9 + 8) = 108, Wahl-Basisfächer 4·14 + 4·13 + 2·12 + 4·11 +
        // 10 + 10 = 196.
        #expect(breakdown.includedPointsTotal == 448)
        #expect(breakdown.outcome.includedCount == 40)
    }

    @Test("Schnitt, Kurspunkte und Note folgen aus der Punktsumme")
    func averageAndGrade() {
        let breakdown = Self.breakdown

        // Doppelt gewertet werden lf-a (13·4 = 52) und lf-b (12·4 = 48):
        // 448 + 100 = 548 auf 48 Wertungen.
        #expect(breakdown.outcome.weightedPointsTotal == 548)
        #expect(breakdown.outcome.effectiveWeightingCount == 48)
        #expect(isClose(breakdown.outcome.averagePoints, 548.0 / 48.0))
        // 548/48 · 40 = 456,66… — aufgerundet.
        #expect(breakdown.outcome.points == 457)

        // Ohne Prüfungen rechnet Score sie auf dem heutigen Stand hoch:
        // 11,4166… · 4 = 45,66… → 46 je Prüfung.
        //
        // Hochgerechnet wird dabei nur, was auch erwartet wird. Dieser Jahrgang
        // hat drei Leistungsfächer und noch kein mündliches Prüfungsfach gewählt;
        // erwartet werden damit drei Prüfungen und nicht fünf. Dreimal 46 sind
        // 138. Die beiden fehlenden mündlichen Prüfungen kommen erst dazu, wenn
        // die Fächer gewählt sind — vorher gibt es sie in den Daten nicht.
        #expect(breakdown.result.isProjection)
        #expect(breakdown.result.projectedExamBlockPoints == 138)
        #expect(breakdown.result.totalPoints == 595)
        // 595 liegt in der Zeile 589–606 der amtlichen Tabelle.
        #expect(breakdown.result.grade == 2.3)
    }

    // MARK: - Die drei Gruppen

    @Test("Jede Gruppe zeigt, wie viele ihrer Kurse zählen")
    func groups() {
        let groups = Self.breakdown.groups

        #expect(groups.map(\.kind) == [.leistungsfach, .pflichtBasisfach, .wahlBasisfach])
        #expect(groups[0].includedCount == 12)
        #expect(groups[0].excludedCount == 0)
        #expect(groups[1].includedCount == 12)
        #expect(groups[1].excludedCount == 0)
        #expect(groups[2].includedCount == 16)
        #expect(groups[2].recordedCount == 22)
        #expect(groups[2].excludedCount == 6)
    }

    @Test("Die freien Plätze sind die 40 minus die nicht klammerbaren Kurse")
    func optionalSlots() {
        let breakdown = Self.breakdown

        #expect(breakdown.optionalSlotCount == 16)
        #expect(breakdown.optionalCandidateCount == 22)
    }

    // MARK: - Die Reihenfolge der Wahl-Basisfächer

    @Test("Wahl-Basisfächer stehen absteigend nach ihrem Schnitt")
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
            .bracketed(points: 3, reason: .automatic),
            .bracketed(points: 3, reason: .automatic)
        ])
    }

    // MARK: - Halbjahre ohne Kurs

    @Test("Nicht belegt und ohne Note sind zwei verschiedene Zustände")
    func missingCourses() {
        let input = SubjectInput(
            id: "bf-lücke",
            kind: .wahlBasisfach,
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
            .bracketed(points: 3, reason: .beyondSubjectLimit),
            .bracketed(points: 3, reason: .beyondSubjectLimit)
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

    @Test("Kurse über der Grenze stehen nicht mehr zur Klammerung an")
    func cappedCoursesAreNoCandidates() {
        let limited = Self.limitedBreakdown

        // 22 erfasste Wahl-Basisfach-Kurse, zwei davon über der Grenze von bf-e.
        #expect(limited.optionalCandidateCount == 20)
        #expect(limited.optionalSlotCount == 16)
        #expect(limited.groups[2].recordedCount == 22)
        #expect(limited.groups[2].includedCount == 16)
    }

    @Test("Was geklammert ist, steht nach Fach und Grund gebündelt da")
    func droppedGroupsCarryTheReason() {
        let groups = Self.limitedBreakdown.droppedGroups

        // Erst die eigene Entscheidung, dann was Score selbst geklammert hat.
        #expect(groups.map(\.subjectID) == ["bf-e", "bf-f"])
        #expect(groups.map(\.reason) == [.beyondSubjectLimit, .automatic])
        #expect(groups[0].courses.map(\.semesterIndex) == [2, 3])
        #expect(groups[0].courseLimit == 2)
        #expect(groups[1].courses.count == 4)
        #expect(Self.limitedBreakdown.hasSubjectLimits)
    }

    @Test("Ohne Grenze klammert alles Score selbst")
    func withoutLimitsEveryDropIsAutomatic() {
        let groups = Self.breakdown.droppedGroups

        #expect(groups.map(\.subjectID) == ["bf-e", "bf-f"])
        #expect(groups.allSatisfy { $0.reason == .automatic })
        #expect(!Self.breakdown.hasSubjectLimits)
        #expect(!Self.breakdown.hasManualBrackets)
    }

    // MARK: - Die drei Klammer-Gründe nebeneinander

    /// Derselbe Jahrgang, aber mit allen drei Gründen zugleich: `bf-e` bringt nur
    /// seine besten zwei ein, in `bf-d` ist ein Halbjahr von Hand geklammert, und
    /// `bf-f` klammert Score selbst weg.
    static let mixedPresentations: [BlockOneBreakdown.SubjectPresentation] = presentations.map {
        switch $0.input.id {
        case "bf-e":
            var input = $0.input
            input.maximumContributedCourses = 2
            return BlockOneBreakdown.SubjectPresentation(name: $0.name, color: $0.color, input: input)
        case "bf-d":
            return presentation(subject("bf-d", .wahlBasisfach, allPoints: 11, bracketed: [3]))
        default:
            return $0
        }
    }

    private static var mixedBreakdown: BlockOneBreakdown {
        BlockOneBreakdown(presentations: mixedPresentations)
    }

    @Test("Alle drei Klammer-Gründe stehen nebeneinander")
    func allThreeReasonsAppear() {
        let groups = Self.mixedBreakdown.droppedGroups

        // Erst die Hand des Nutzers, dann seine Kursgrenze, dann Score selbst.
        #expect(groups.map(\.reason) == [.manual, .beyondSubjectLimit, .automatic])
        #expect(groups[0].subjectID == "bf-d")
        #expect(groups[0].courses.map(\.semesterIndex) == [3])
        #expect(Self.mixedBreakdown.hasManualBrackets)
        #expect(Self.mixedBreakdown.hasSubjectLimits)
    }

    @Test("Ein von Hand geklammerter Kurs trägt seinen eigenen Zustand")
    func manualBracketHasItsOwnState() {
        let entry = Self.mixedBreakdown.optionalSubjects.first { $0.id == "bf-d" }

        #expect(entry?.courses.last?.state == .bracketed(points: 11, reason: .manual))
        // Er tritt auch nicht mehr im Schnitt an, mit dem das Fach dasteht:
        // über ihn ist bereits entschieden.
        #expect(isClose(entry?.competingAverage ?? 0, 11))
        #expect(isClose(entry?.recordedAverage ?? 0, 11))
    }

    // MARK: - Mündliche Prüfungsfächer

    /// Derselbe Jahrgang, aber `bf-f` mit seinen zwei Punkten ist mündliches
    /// Prüfungsfach — und damit anrechnungspflichtig.
    static let oralExamPresentations: [BlockOneBreakdown.SubjectPresentation] = presentations.map {
        guard $0.input.id == "bf-f" else { return $0 }
        return presentation(subject("bf-f", .wahlBasisfach, allPoints: 2, isOralExam: true))
    }

    private static var oralExamBreakdown: BlockOneBreakdown {
        BlockOneBreakdown(presentations: oralExamPresentations)
    }

    @Test("Ein mündliches Prüfungsfach steht nicht bei den klammerbaren Fächern")
    func oralExamSubjectsAreNotBracketable() {
        let breakdown = Self.oralExamBreakdown

        #expect(breakdown.oralExamSubjects.map(\.id) == ["bf-f"])
        #expect(!breakdown.bracketableSubjects.map(\.id).contains("bf-f"))
        // In der Gruppenbilanz zählt es weiter als Wahl-Basisfach — das ist es ja.
        #expect(breakdown.optionalSubjects.count == 6)
        #expect(breakdown.bracketableSubjects.count == 5)
    }

    @Test("Die anrechnungspflichtigen Kurse verkleinern, was offen bleibt")
    func oralExamSubjectsShrinkTheOpenCourses() {
        let breakdown = Self.oralExamBreakdown

        // 12 Leistungsfach-, 12 Pflicht-Basisfach- und 4 Prüfungsfach-Kurse sind 28
        // anrechnungspflichtige; von den 40 bleiben 12 offen.
        #expect(breakdown.optionalSlotCount == 12)
        #expect(breakdown.oralExamSubjects.allSatisfy { $0.includedCount == 4 })
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
