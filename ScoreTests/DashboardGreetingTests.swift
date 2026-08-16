import Testing
@testable import Score

/// Die Staffelung der Begrüssung.
///
/// Geprüft wird nicht der Wortlaut — der darf sich ändern —, sondern dass jede
/// Schwelle genau dort greift, wo sie angeschrieben ist, und dass keine Zeile
/// länger wird, als neben einen Vornamen passt.
@Suite("DashboardGreeting")
struct DashboardGreetingTests {

    /// Genug erfasste Kurse, damit der Schnitt überhaupt etwas aussagt.
    private static let recorded = DashboardGreeting.minimumRecordedCourses

    @Test("Ohne genug erfasste Kurse steht die Einladung, nicht die Bewertung")
    func startBelowMinimum() {
        for count in 0..<DashboardGreeting.minimumRecordedCourses {
            #expect(
                DashboardGreeting.stage(expectedGrade: 1.0, recordedCount: count) == .start,
                "Ein Spitzenschnitt aus \(count) Kursen ist noch keine Leistung"
            )
            #expect(DashboardGreeting.stage(expectedGrade: 3.9, recordedCount: count) == .start)
        }
    }

    @Test("Jede Schwelle greift auf den Punkt")
    func stagesAtTheirBounds() {
        let cases: [(grade: Double, stage: DashboardGreeting.Stage)] = [
            (1.0, .excellent),
            (DashboardGreeting.excellentUpperBound, .excellent),
            (DashboardGreeting.excellentUpperBound + 0.1, .good),
            (DashboardGreeting.goodUpperBound, .good),
            (DashboardGreeting.goodUpperBound + 0.1, .solid),
            (DashboardGreeting.solidUpperBound, .solid),
            (DashboardGreeting.solidUpperBound + 0.1, .onward),
            (4.0, .onward)
        ]

        for expectation in cases {
            #expect(
                DashboardGreeting.stage(
                    expectedGrade: expectation.grade,
                    recordedCount: Self.recorded
                ) == expectation.stage,
                "Schnitt \(expectation.grade) gehört zu \(expectation.stage)"
            )
        }
    }

    /// „Läuft bei dir" ist das Mass — der Vorname hängt hinter der Zeile, und
    /// beides zusammen muss auf einem iPhone in eine Zeile passen.
    @Test("Keine Zeile ist länger als das Mass")
    func linesStayShort() {
        let limit = "Läuft bei dir".count

        for stage in DashboardGreeting.Stage.allCases {
            let line = DashboardGreeting.text(for: stage, firstName: "")
            // Ohne Vornamen bleiben Trennzeichen stehen; gemessen wird die
            // Formulierung davor.
            let phrase = line.prefix { $0 != "," }
            #expect(
                phrase.count <= limit,
                "Die Zeile \(phrase) ist \(phrase.count) Zeichen lang, erlaubt sind \(limit)"
            )
        }
    }

    @Test("Jede Stufe hat eine eigene Zeile")
    func everyStageHasItsOwnLine() {
        let lines = DashboardGreeting.Stage.allCases.map {
            DashboardGreeting.text(for: $0, firstName: "Julius")
        }
        #expect(Set(lines).count == lines.count)
    }
}
