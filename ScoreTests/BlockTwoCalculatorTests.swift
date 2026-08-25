import Testing
@testable import Score

/// Der Prüfungsblock: fünf Prüfungen, jede vierfach gewertet.
///
/// Alle Erwartungswerte sind von Hand ausgerechnet und stehen als Literale im
/// Test.
@Suite("Prüfungsblock")
struct BlockTwoCalculatorTests {

    /// Drei Leistungsfächer als schriftliche und zwei Basisfächer als mündliche
    /// Prüfungsfächer — die Fächerwahl, aus der die fünf Prüfungen folgen.
    private static func year(
        written: [Int?] = [nil, nil, nil],
        oral: [Int?] = [nil, nil],
        additionalOral: [Int?] = [nil, nil, nil]
    ) -> [SubjectInput] {
        (0..<3).map { index in
            subject(
                "lf-\(index)",
                .leistungsfach,
                allPoints: 10,
                writtenExamPoints: written[index],
                oralExamPoints: additionalOral[index]
            )
        } + (0..<2).map { index in
            subject(
                "bf-\(index)",
                .wahlBasisfach,
                allPoints: 10,
                isOralExam: true,
                oralExamPoints: oral[index]
            )
        }
    }

    // MARK: - Aufbau

    @Test("Aus der Fächerwahl folgen genau fünf Prüfungen")
    func fiveExamsFollowFromTheSubjects() {
        let outcome = BlockTwoCalculator.calculate(for: Self.year())

        #expect(outcome.expectedExamCount == 5)
        #expect(outcome.exams.count == 5)
        // Erst die drei schriftlichen, dann die zwei mündlichen.
        #expect(outcome.exams.map(\.role) == [.written, .written, .written, .oral, .oral])
        #expect(outcome.exams.map(\.id) == ["lf-0", "lf-1", "lf-2", "bf-0", "bf-1"])
    }

    // MARK: - Die vierfache Wertung

    @Test("Jedes Prüfungsergebnis zählt vierfach")
    func everyResultCountsFourfold() {
        let outcome = BlockTwoCalculator.calculate(
            for: Self.year(written: [12, 10, 8], oral: [15, 5])
        )

        #expect(outcome.exams.map(\.points) == [48, 40, 32, 60, 20])
        // 48 + 40 + 32 + 60 + 20 = 200
        #expect(outcome.points == 200)
        #expect(outcome.isComplete)
        #expect(outcome.meetsMinimum)
    }

    @Test("Durchweg 15 Punkte ergeben genau die 300 des Prüfungsblocks")
    func fifteenPointsGiveTheMaximum() {
        let outcome = BlockTwoCalculator.calculate(
            for: Self.year(written: [15, 15, 15], oral: [15, 15])
        )

        #expect(outcome.points == BlockTwoCalculator.maximumPoints)
        #expect(outcome.points == 300)
    }

    @Test("Genau 100 Punkte sind die Mindestbedingung")
    func hundredPointsIsTheMinimum() {
        // Fünfmal 5 Punkte: 5 · 5 · 4 = 100 — auf den Punkt erfüllt.
        let exact = BlockTwoCalculator.calculate(
            for: Self.year(written: [5, 5, 5], oral: [5, 5])
        )
        #expect(exact.points == 100)
        #expect(exact.meetsMinimum)

        // Ein Punkt weniger in einem Fach sind vier Punkte weniger im Block.
        let short = BlockTwoCalculator.calculate(
            for: Self.year(written: [4, 5, 5], oral: [5, 5])
        )
        #expect(short.points == 96)
        #expect(!short.meetsMinimum)
    }

    // MARK: - Der Sonderfall: mündlich zusätzlich zu schriftlich

    @Test("Kommt eine mündliche Prüfung hinzu, zählt sie im Verhältnis 2:1")
    func additionalOralExamCountsOneThird() {
        let outcome = BlockTwoCalculator.calculate(
            for: Self.year(
                written: [12, 10, 8],
                oral: [15, 5],
                additionalOral: [nil, 13, nil]
            )
        )

        let combined = outcome.exams[1]
        #expect(combined.isCombined)
        // (10 · 2 + 13) ÷ 3 = 11,0 — und das mal vier.
        #expect(isClose(try! #require(combined.result), 11))
        #expect(combined.points == 44)

        // Statt 40 stehen dort jetzt 44: 200 + 4 = 204.
        #expect(outcome.points == 204)
    }

    @Test("Ein nicht ganzzahliges Ergebnis wird kaufmännisch gerundet")
    func combinedResultsAreRoundedHalfUp() {
        // (13 · 2 + 14) ÷ 3 = 13,333… → 13 → mal vier 52
        let up = BlockTwoCalculator.Exam(
            id: "lf", role: .written, writtenPoints: 13, oralPoints: 14
        )
        #expect(up.points == 52)

        // (14 · 2 + 13) ÷ 3 = 13,666… → 14 → mal vier 56
        let down = BlockTwoCalculator.Exam(
            id: "lf", role: .written, writtenPoints: 14, oralPoints: 13
        )
        #expect(down.points == 56)

        // Bei 15 und 15 bleibt es bei 15 — die Obergrenze verschiebt sich nicht.
        let top = BlockTwoCalculator.Exam(
            id: "lf", role: .written, writtenPoints: 15, oralPoints: 15
        )
        #expect(top.points == 60)
    }

    @Test("Gerundet wird das Prüfungsergebnis, nicht sein vierfacher Wert")
    func theResultIsRoundedBeforeItIsQuadrupled() {
        // Schriftlich 10, mündlich 11: (20 + 11) ÷ 3 = 10,33… Amtlich steht damit
        // das Prüfungsergebnis 10, und vierfach sind das 40 Punkte. Wer erst
        // vervierfacht und dann rundet, landet bei 41 — einer Punktzahl, die in
        // Block II gar nicht vorkommen kann.
        let exam = BlockTwoCalculator.Exam(
            id: "lf", role: .written, writtenPoints: 10, oralPoints: 11
        )

        #expect(exam.points == 40)

        // Der Beitrag eines Fachs ist immer durch vier teilbar — über alle
        // Kombinationen aus schriftlichem und mündlichem Ergebnis hinweg.
        for written in 0...15 {
            for oral in 0...15 {
                let combined = BlockTwoCalculator.Exam(
                    id: "lf", role: .written, writtenPoints: written, oralPoints: oral
                )
                #expect(try! #require(combined.points) % BlockTwoCalculator.weight == 0)
            }
        }
    }

    @Test("Mehr als fünf Prüfungen sprengen den Block nicht")
    func moreThanFiveExamsStayWithinTheBlock() {
        // Vier Leistungsfächer neben zwei mündlichen Prüfungsfächern: amtlich
        // unmöglich, im Datenbestand nach einem Import oder Sync trotzdem denkbar.
        let subjects = (1...4).map {
            subject("lf-\($0)", .leistungsfach, allPoints: 15, writtenExamPoints: 15)
        } + (1...2).map {
            subject("mp-\($0)", .wahlBasisfach, allPoints: 15, isOralExam: true, oralExamPoints: 15)
        }

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        // Sechs Prüfungen à 60 wären 360 — den Block gibt es nur bis 300.
        #expect(outcome.points == BlockTwoCalculator.maximumPoints)
        #expect(outcome.expectedExamCount == 5)
        #expect(outcome.recordedExamCount == 5)
        #expect(outcome.isComplete)
        #expect(outcome.missingExamCount == 0)
    }

    @Test("Ohne gewählte mündliche Prüfungsfächer bleiben es fünf Prüfungen")
    func unchosenOralExamSubjectsAreStillProjected() {
        // Drei Leistungsfächer, aber noch kein mündliches Prüfungsfach gewählt —
        // der Normalfall in Kursstufe 1 und im grössten Teil von Kursstufe 2.
        let subjects = (1...3).map {
            subject("lf-\($0)", .leistungsfach, allPoints: 10, writtenExamPoints: 12)
        }

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        // Score kennt drei Prüfungen; geprüft wird trotzdem fünfmal.
        #expect(outcome.expectedExamCount == 3)
        #expect(outcome.recordedExamCount == 3)
        #expect(outcome.missingExamCount == 2)
        #expect(outcome.points == 144)
        // 144 + 2 · 48 = 240. Würden nur die drei bekannten Prüfungen
        // fortgeschrieben, bliebe der Block bei 144, die Gesamtpunktzahl käme nie
        // über 780 und die Note fiele um rund eine ganze Stufe.
        #expect(outcome.projectedPoints(assuming: 12) == 240)
        // Vollständig ist der Block trotzdem nicht: es fehlt die Fächerwahl.
        #expect(!outcome.isComplete)
    }

    @Test("Eine sechste Prüfung ohne Ergebnis macht den Block nicht vollständig")
    func aSixthExamWithoutAResultLeavesTheBlockIncomplete() {
        // Vier Leistungsfächer neben zwei mündlichen Prüfungsfächern, und eines
        // der vier ist noch nicht geschrieben: fünf Ergebnisse bei sechs
        // Prüfungen. Der Deckel auf fünf darf die offene Prüfung nicht verdecken.
        let subjects = (1...3).map {
            subject("lf-\($0)", .leistungsfach, allPoints: 15, writtenExamPoints: 15)
        } + [subject("lf-4", .leistungsfach, allPoints: 15)] + (1...2).map {
            subject("mp-\($0)", .wahlBasisfach, allPoints: 15, isOralExam: true, oralExamPoints: 15)
        }

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        #expect(outcome.exams.count == 6)
        #expect(outcome.recordedExamCount == 5)
        #expect(outcome.expectedExamCount == 5)
        #expect(!outcome.isComplete)
    }

    /// Der Deckel darf die offene Prüfung auch in der Hochrechnung nicht
    /// verschlucken.
    @Test("Die offene sechste Prüfung wird fortgeschrieben und nicht als null gezählt")
    func theSixthOpenExamIsProjectedAndNotCountedAsZero() {
        // Wieder sechs Prüfungen mit fünf Ergebnissen, diesmal auf 6 Punkten:
        // erfasst sind 5 · 24 = 120 Punkte.
        let subjects = (1...3).map {
            subject("lf-\($0)", .leistungsfach, allPoints: 6, writtenExamPoints: 6)
        } + [subject("lf-4", .leistungsfach, allPoints: 6)] + (1...2).map {
            subject("mp-\($0)", .wahlBasisfach, allPoints: 6, isOralExam: true, oralExamPoints: 6)
        }

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        #expect(outcome.points == 120)
        // Eine Prüfung steht offen. Stünde hier 0, wäre sie weder erfasst noch
        // fehlend und ginge in der Hochrechnung als null Punkte durch.
        #expect(outcome.missingExamCount == 1)
        #expect(!outcome.isComplete)
        // 120 + 24 = 144 statt 120: Was fehlt, wird auf dem gezeigten Niveau
        // fortgeschrieben. Bei 120 Punkten meldete `failedConditions` zudem einen
        // gerissenen Prüfungsblock, den es nicht gibt.
        #expect(outcome.projectedPoints(assuming: 6) == 144)
    }

    /// Die beiden Zahlen dürfen sich nie widersprechen — sonst fällt eine
    /// Prüfung zwischen ihnen hindurch.
    @Test("Vollständig heisst genau: keine Prüfung fehlt mehr")
    func completenessAndMissingCountAlwaysAgree() {
        let cases: [[SubjectInput]] = [
            Self.year(),
            Self.year(written: [12, nil, nil], oral: [nil, nil]),
            Self.year(written: [12, 10, 8], oral: [15, 5]),
            (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 10, writtenExamPoints: 10) },
            (1...3).map {
                subject("lf-\($0)", .leistungsfach, allPoints: 15, writtenExamPoints: 15)
            } + [subject("lf-4", .leistungsfach, allPoints: 15)] + (1...2).map {
                subject("mp-\($0)", .wahlBasisfach, allPoints: 15, isOralExam: true, oralExamPoints: 15)
            },
            (1...4).map {
                subject("lf-\($0)", .leistungsfach, allPoints: 15, writtenExamPoints: 15)
            } + (1...2).map {
                subject("mp-\($0)", .wahlBasisfach, allPoints: 15, isOralExam: true, oralExamPoints: 15)
            }
        ]

        for subjects in cases {
            let outcome = BlockTwoCalculator.calculate(for: subjects)
            #expect(outcome.isComplete == (outcome.missingExamCount == 0))
            // Und über die amtlichen 300 Punkte hebt die Hochrechnung nie hinaus.
            #expect(outcome.projectedPoints(assuming: 15) <= BlockTwoCalculator.maximumPoints)
        }
    }

    // MARK: - Was noch fehlt

    @Test("Eine fehlende Prüfung ist nicht null Punkte")
    func missingExamsAreNotZero() {
        let outcome = BlockTwoCalculator.calculate(
            for: Self.year(written: [12, nil, nil], oral: [nil, nil])
        )

        #expect(outcome.recordedExamCount == 1)
        #expect(outcome.missingExamCount == 4)
        #expect(!outcome.isComplete)
        // Erfasst ist nur das eine Ergebnis; die anderen fehlen und stehen nicht
        // als 0 in der Summe.
        #expect(outcome.points == 48)
        #expect(isClose(try! #require(outcome.averageResult), 12))
    }

    @Test("Ohne eine einzige Prüfung gibt es keinen Schnitt")
    func withoutAnyExamThereIsNoAverage() {
        let outcome = BlockTwoCalculator.calculate(for: Self.year())

        #expect(outcome.recordedExamCount == 0)
        #expect(outcome.averageResult == nil)
        #expect(outcome.points == 0)
        #expect(!outcome.isComplete)
    }

    @Test("Fehlende Prüfungen werden auf dem angenommenen Niveau fortgeschrieben")
    func missingExamsAreProjected() {
        let outcome = BlockTwoCalculator.calculate(
            for: Self.year(written: [12, nil, nil], oral: [nil, nil])
        )

        // Vier fehlende Prüfungen auf 12 Punkten: 48 + 4 · 48 = 240.
        #expect(outcome.projectedPoints(assuming: 12) == 240)
        // Auf 15 Punkten wären es 48 + 4 · 60 = 288.
        #expect(outcome.projectedPoints(assuming: 15) == 288)
    }

    // MARK: - Randfälle

    @Test("Ohne gewählte Prüfungsfächer ist der Block leer, aber gültig")
    func withoutExamSubjects() {
        let outcome = BlockTwoCalculator.calculate(
            for: [subject("bf-a", .wahlBasisfach, allPoints: 10)]
        )

        #expect(outcome.exams.isEmpty)
        #expect(outcome.expectedExamCount == 0)
        #expect(outcome.points == 0)
        // Null von null Prüfungen ist nicht „vollständig" — es fehlt die Wahl.
        #expect(!outcome.isComplete)
    }

    @Test("Ein Leistungsfach steht nie zugleich in der mündlichen Liste")
    func advancedSubjectsAreNeverOralExamSubjects() {
        // Beide Kennzeichen zugleich kann ein Datensatz von einem anderen Gerät
        // tragen. Geprüft wird trotzdem nur einmal, und zwar schriftlich.
        let subjects = [
            subject("lf-a", .leistungsfach, allPoints: 10, isOralExam: true, writtenExamPoints: 11)
        ]

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        #expect(outcome.exams.count == 1)
        #expect(outcome.exams[0].role == .written)
        #expect(outcome.points == 44)
    }

    // MARK: - Die Nachprüfung allein ist kein Ergebnis

    @Test("Eine Nachprüfung ohne schriftliches Ergebnis zählt nicht")
    func oralRetakeAloneDoesNotCount() {
        // Ein Leistungsfach, in dem nur die mündliche Nachprüfung eingetragen
        // ist. Die Nachprüfung ist ein Zusatz zur schriftlichen Prüfung und nie
        // die Prüfung selbst.
        let subjects = [subject("lf-a", .leistungsfach, allPoints: 10, oralExamPoints: 15)]

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        #expect(outcome.exams.count == 1)
        #expect(outcome.exams[0].result == nil)
        #expect(outcome.exams[0].points == nil)
        #expect(outcome.points == 0)
        #expect(outcome.recordedExamCount == 0)
        #expect(!outcome.isComplete)
    }

    @Test("Fünf Nachprüfungen ohne schriftliche Ergebnisse machen den Block nicht vollständig")
    func fiveOralRetakesDoNotCompleteTheBlock() {
        let subjects = (1...3).map {
            subject("lf-\($0)", .leistungsfach, allPoints: 10, oralExamPoints: 15)
        } + (1...2).map {
            subject("mp-\($0)", .wahlBasisfach, allPoints: 10, isOralExam: true, oralExamPoints: 15)
        }

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        // Nur die beiden echten mündlichen Prüfungen zählen: 2 · 15 · 4 = 120.
        #expect(outcome.points == 120)
        #expect(outcome.recordedExamCount == 2)
        #expect(!outcome.isComplete)
    }

    @Test("Kommt das schriftliche Ergebnis dazu, zählt die Nachprüfung mit")
    func theRetakeCountsOnceTheWrittenResultArrives() {
        let subjects = [
            subject("lf-a", .leistungsfach, allPoints: 10, writtenExamPoints: 12, oralExamPoints: 15)
        ]

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        // (12 · 2 + 15) ÷ 3 = 13, vierfach also 52.
        #expect(outcome.points == 52)
        #expect(outcome.recordedExamCount == 1)
    }

    @Test("Ein liegengebliebenes schriftliches Ergebnis zählt nicht mit")
    func aStaleWrittenResultIsIgnored() {
        // Der Nutzer hat den Fachtyp gewechselt. Das Ergebnis bleibt gespeichert
        // — in die Rechnung geht es nicht ein.
        let subjects = [
            subject("bf-a", .wahlBasisfach, allPoints: 10, writtenExamPoints: 15)
        ]

        let outcome = BlockTwoCalculator.calculate(for: subjects)

        #expect(outcome.exams.isEmpty)
        #expect(outcome.points == 0)
    }
}
