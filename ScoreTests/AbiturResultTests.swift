import Testing
@testable import Score

/// Die Gesamtqualifikation von Anfang bis Ende: Kursblock, Prüfungsblock,
/// Gesamtpunktzahl, Note.
///
/// Der erste Test ist ein **vollständig durchgerechnetes Beispiel**. Jeder
/// Zwischenwert steht im Kommentar, sodass sich das ganze Abitur mit Papier und
/// Bleistift nachprüfen lässt.
@Suite("Gesamtqualifikation")
struct AbiturResultTests {

    // MARK: - Das durchgerechnete Beispiel

    /// Ein vollständiger Jahrgang mit runden Zahlen — genau 40 Kurse, keine
    /// Klammerung, alle fünf Prüfungen geschrieben.
    ///
    /// ## Die Fächer
    ///
    /// | Fach                 | Typ     | Kurse | Punkte je Kurs |
    /// |----------------------|---------|-------|----------------|
    /// | Deutsch              | LF      | 4     | 13             |
    /// | Mathematik           | LF      | 4     | 12             |
    /// | Biologie             | LF      | 4     | 11             |
    /// | Englisch             | PBF     | 4     | 10             |
    /// | Geschichte           | PBF     | 4     | 10             |
    /// | Gemeinschaftskunde   | PBF     | 4     | 10             |
    /// | Physik               | PBF     | 4     | 10             |
    /// | Chemie               | WBF     | 4     | 10             |
    /// | Geografie            | WBF     | 4     | 10             |
    /// | Sport                | WBF     | 4     | 11             |
    ///
    /// Zusammen 40 Kurse — es gibt nichts zu klammern.
    ///
    /// Mündlich geprüft wird in Gemeinschaftskunde und Geografie.
    private static let year: [SubjectInput] = [
        subject("lf-deutsch", .leistungsfach, allPoints: 13, writtenExamPoints: 13),
        subject("lf-mathematik", .leistungsfach, allPoints: 12, writtenExamPoints: 12),
        subject("lf-biologie", .leistungsfach, allPoints: 11, writtenExamPoints: 11),

        subject("pbf-englisch", .pflichtBasisfach, allPoints: 10),
        subject("pbf-geschichte", .pflichtBasisfach, allPoints: 10),
        subject(
            "pbf-gemeinschaftskunde",
            .pflichtBasisfach,
            allPoints: 10,
            isOralExam: true,
            oralExamPoints: 10
        ),
        subject("pbf-physik", .pflichtBasisfach, allPoints: 10),

        subject("wbf-chemie", .wahlBasisfach, allPoints: 10),
        subject(
            "wbf-geografie",
            .wahlBasisfach,
            allPoints: 10,
            isOralExam: true,
            oralExamPoints: 12
        ),
        subject("wbf-sport", .wahlBasisfach, allPoints: 11)
    ]

    @Test("Ein vollständiger Jahrgang, Schritt für Schritt nachgerechnet")
    func workedExample() throws {
        let result = AbiturResult.calculate(for: Self.year)

        // ── Schritt 1: Welche Kurse gehen ein? ───────────────────────────────
        //
        // 40 erfasste Kurse auf 40 Plätze. Es wird nichts geklammert.
        #expect(result.courseBlock.recordedCount == 40)
        #expect(result.courseBlock.includedCount == 40)
        #expect(result.courseBlock.excludedCourses.isEmpty)

        // ── Schritt 2: Die Punktsumme der 40 Kurse ───────────────────────────
        //
        //   Leistungsfächer      4 · (13 + 12 + 11)          = 144
        //   Pflicht-Basisfächer  4 · (10 + 10 + 10 + 10)     = 160
        //   Wahl-Basisfächer     4 · (10 + 10 + 11)          = 124
        //                                                     ─────
        //                                                       428

        // ── Schritt 3: Die Doppelwertung ─────────────────────────────────────
        //
        // Zwei der drei Leistungsfächer zählen doppelt. Score nimmt die beiden
        // stärksten: Deutsch (4 · 13 = 52) und Mathematik (4 · 12 = 48).
        //
        //   428 + 52 + 48 = 528 Punkte über 48 Wertungen
        #expect(result.courseBlock.doubleWeightedSubjectIDs == ["lf-deutsch", "lf-mathematik"])
        #expect(result.courseBlock.usesAutomaticDoubleWeighting)
        #expect(result.courseBlock.weightedPointsTotal == 528)
        #expect(result.courseBlock.effectiveWeightingCount == 48)

        // ── Schritt 4: Der Kursblock ─────────────────────────────────────────
        //
        //   528 ÷ 48 = 11,0 Punkte je Wertung
        //   11,0 × 40 = 440 Punkte
        #expect(isClose(result.courseBlock.averagePoints, 11))
        #expect(result.courseBlock.points == 440)
        #expect(result.courseBlock.meetsMinimum)

        // ── Schritt 5: Der Prüfungsblock ─────────────────────────────────────
        //
        //   Deutsch schriftlich             13 × 4 =  52
        //   Mathematik schriftlich          12 × 4 =  48
        //   Biologie schriftlich            11 × 4 =  44
        //   Gemeinschaftskunde mündlich     10 × 4 =  40
        //   Geografie mündlich              12 × 4 =  48
        //                                            ─────
        //                                              232
        #expect(result.examBlock.exams.map(\.points) == [52, 48, 44, 40, 48])
        #expect(result.examBlock.points == 232)
        #expect(result.examBlock.isComplete)
        #expect(result.examBlock.meetsMinimum)

        // ── Schritt 6: Gesamtpunktzahl und Note ──────────────────────────────
        //
        //   440 + 232 = 672 Punkte
        //
        // 672 liegt in der Zeile 661–678 der amtlichen Tabelle: Note 1,9.
        #expect(!result.isProjection)
        #expect(result.totalPoints == 672)
        #expect(result.recordedTotalPoints == 672)
        #expect(result.grade == 1.9)
        #expect(result.isPassed)
        #expect(result.failedConditions.isEmpty)

        // Bis 679 und damit bis 1,8 fehlen sieben Punkte.
        #expect(result.pointsToNextGrade == 7)
    }

    @Test("Eine zusätzliche mündliche Prüfung verschiebt genau ein Fach")
    func workedExampleWithAdditionalOralExam() {
        // In Mathematik kommt eine mündliche Prüfung mit 15 Punkten hinzu.
        //
        //   (12 × 2 + 15) ÷ 3 = 13,0 → 13 × 4 = 52 statt 48
        //
        // Der Prüfungsblock steigt von 232 auf 236, die Gesamtpunktzahl von 672
        // auf 676. Beide liegen in derselben Zeile: die Note bleibt 1,9.
        var year = Self.year
        year[1].oralExamPoints = 15

        let result = AbiturResult.calculate(for: year)

        #expect(result.examBlock.exams[1].points == 52)
        #expect(result.examBlock.points == 236)
        #expect(result.totalPoints == 676)
        #expect(result.grade == 1.9)

        // Ein Punkt mehr, und es kippt: 677 ist immer noch 1,9, ab 679 steht 1,8.
        #expect(result.pointsToNextGrade == 3)
    }

    // MARK: - Die Höchst- und Mindestwerte

    @Test("Durchweg 15 Punkte ergeben 900 und damit 1,0")
    func perfectYearIsOneZero() {
        let perfect = Self.year.map { input -> SubjectInput in
            var copy = subject(
                input.id,
                input.kind,
                allPoints: 15,
                isOralExam: input.isOralExamSubject
            )
            copy.writtenExamPoints = input.kind == .leistungsfach ? 15 : nil
            copy.oralExamPoints = input.isOralExamSubject ? 15 : nil
            return copy
        }

        let result = AbiturResult.calculate(for: perfect)

        #expect(result.courseBlock.points == 600)
        #expect(result.examBlock.points == 300)
        #expect(result.totalPoints == AbiturGradeTable.maximumTotal)
        #expect(result.grade == 1.0)
        #expect(result.isPassed)
    }

    @Test("Genau 300 Punkte sind 4,0 und bestanden, 299 sind es nicht")
    func theExactPassingBoundary() {
        // Kursblock 200, Prüfungsblock 100: beide Mindestbedingungen exakt
        // erfüllt, zusammen genau die 300.
        //
        // 200 Punkte im Kursblock heisst 5,0 Punkte je Wertung — durchweg
        // 5 Punkte. 100 im Prüfungsblock heisst fünfmal 5 Punkte.
        let atTheLine = Self.year.map { input -> SubjectInput in
            var copy = subject(
                input.id,
                input.kind,
                allPoints: 5,
                isOralExam: input.isOralExamSubject
            )
            copy.writtenExamPoints = input.kind == .leistungsfach ? 5 : nil
            copy.oralExamPoints = input.isOralExamSubject ? 5 : nil
            return copy
        }

        let result = AbiturResult.calculate(for: atTheLine)

        #expect(result.courseBlock.points == 200)
        #expect(result.courseBlock.meetsMinimum)
        #expect(result.examBlock.points == 100)
        #expect(result.examBlock.meetsMinimum)
        #expect(result.totalPoints == 300)
        #expect(result.grade == 4.0)
        #expect(result.isPassed)
        #expect(result.failedConditions.isEmpty)
    }

    // MARK: - Die Mindestbedingungen einzeln

    @Test("Ein starker Kursblock rettet einen zu schwachen Prüfungsblock nicht")
    func aStrongCourseBlockDoesNotSaveAWeakExamBlock() {
        // Kursblock 600, Prüfungsblock 96 — zusammen 696 Punkte und nach der
        // Tabelle eine 1,8. Bestanden ist es trotzdem nicht: der Prüfungsblock
        // liegt unter 100.
        let subjects = Self.year.map { input -> SubjectInput in
            var copy = subject(
                input.id,
                input.kind,
                allPoints: 15,
                isOralExam: input.isOralExamSubject
            )
            copy.writtenExamPoints = input.kind == .leistungsfach ? 4 : nil
            copy.oralExamPoints = input.isOralExamSubject ? 4 : nil
            return copy
        }

        let result = AbiturResult.calculate(for: subjects)

        #expect(result.courseBlock.points == 600)
        #expect(result.examBlock.points == 80)
        #expect(result.totalPoints == 680)
        // Die Tabelle nennt eine Note …
        #expect(result.grade == 1.8)
        // … aber bestanden ist es nicht.
        #expect(!result.isPassed)
        #expect(result.failedConditions == [.examBlockBelowMinimum])
    }

    @Test("Ein starker Prüfungsblock rettet einen zu schwachen Kursblock nicht")
    func aStrongExamBlockDoesNotSaveAWeakCourseBlock() {
        // Durchweg 4 Punkte in den Kursen sind 160 im Kursblock — unter 200.
        let subjects = Self.year.map { input -> SubjectInput in
            var copy = subject(
                input.id,
                input.kind,
                allPoints: 4,
                isOralExam: input.isOralExamSubject
            )
            copy.writtenExamPoints = input.kind == .leistungsfach ? 15 : nil
            copy.oralExamPoints = input.isOralExamSubject ? 15 : nil
            return copy
        }

        let result = AbiturResult.calculate(for: subjects)

        #expect(result.courseBlock.points == 160)
        #expect(!result.courseBlock.meetsMinimum)
        #expect(result.examBlock.points == 300)
        #expect(result.totalPoints == 460)
        #expect(!result.isPassed)
        #expect(result.failedConditions == [.courseBlockBelowMinimum])
    }

    @Test("Unter 300 Punkten gibt es keine Note")
    func belowThreeHundredThereIsNoGrade() {
        let subjects = Self.year.map { input -> SubjectInput in
            var copy = subject(
                input.id,
                input.kind,
                allPoints: 3,
                isOralExam: input.isOralExamSubject
            )
            copy.writtenExamPoints = input.kind == .leistungsfach ? 3 : nil
            copy.oralExamPoints = input.isOralExamSubject ? 3 : nil
            return copy
        }

        let result = AbiturResult.calculate(for: subjects)

        // 120 im Kursblock, 60 im Prüfungsblock, zusammen 180.
        #expect(result.totalPoints == 180)
        #expect(result.grade == nil)
        #expect(!result.isPassed)
        #expect(result.failedConditions == [
            .courseBlockBelowMinimum, .examBlockBelowMinimum, .totalBelowMinimum
        ])
    }

    // MARK: - Hochrechnung

    @Test("Ohne Prüfungen ist alles eine Hochrechnung — und keine null")
    func withoutExamsEverythingIsAProjection() {
        let subjects = Self.year.map { input -> SubjectInput in
            var copy = input
            copy.writtenExamPoints = nil
            copy.oralExamPoints = nil
            return copy
        }

        let result = AbiturResult.calculate(for: subjects)

        #expect(result.isProjection)
        #expect(result.examBlock.points == 0)
        #expect(result.examBlock.missingExamCount == 5)

        // Fehlende Prüfungen werden auf dem Niveau des Kursblocks angesetzt:
        // 11,0 Punkte je Wertung, also 11 × 4 = 44 je Prüfung, fünfmal 220.
        #expect(isClose(result.projectionLevel, 11))
        #expect(result.projectedExamBlockPoints == 220)
        #expect(result.totalPoints == 660)
        #expect(result.grade == 2.0)

        // Was heute wirklich feststeht, ist nur der Kursblock.
        #expect(result.recordedTotalPoints == 440)

        // Eine Hochrechnung ist nie „bestanden" — sie ist eine Aussicht.
        #expect(!result.isPassed)
        #expect(result.failedConditions.isEmpty)
    }

    @Test("Sind einzelne Prüfungen da, geben sie das Niveau vor")
    func recordedExamsSetTheProjectionLevel() {
        var subjects = Self.year
        // Nur Deutsch ist geschrieben, mit 15 Punkten.
        subjects[0].writtenExamPoints = 15
        subjects[1].writtenExamPoints = nil
        subjects[2].writtenExamPoints = nil
        subjects[5].oralExamPoints = nil
        subjects[8].oralExamPoints = nil

        let result = AbiturResult.calculate(for: subjects)

        // Der Schnitt der geschriebenen Prüfungen ist 15 — nicht der des
        // Kursblocks. Wer im Abitur besser abschneidet als in den Kursen, soll
        // das auch in der Hochrechnung sehen.
        #expect(isClose(result.projectionLevel, 15))
        // 60 erfasst, dazu vier fehlende zu je 60: 300.
        #expect(result.projectedExamBlockPoints == 300)
        #expect(result.totalPoints == 740)
        #expect(result.grade == 1.5)
    }

    @Test("Die Hochrechnung übersteigt nie die 300 des Prüfungsblocks")
    func theProjectionIsCappedAtThreeHundred() {
        var subjects = Self.year
        for index in subjects.indices {
            subjects[index].writtenExamPoints = nil
            subjects[index].oralExamPoints = nil
        }
        subjects[0].writtenExamPoints = 15

        let result = AbiturResult.calculate(for: subjects)

        #expect(result.projectedExamBlockPoints <= BlockTwoCalculator.maximumPoints)
    }

    // MARK: - Der leere Zustand

    @Test("Das leere Ergebnis ist gültig und ohne Note")
    func emptyResult() {
        let empty = AbiturResult.empty

        #expect(empty.totalPoints == 0)
        #expect(empty.grade == nil)
        #expect(empty.isProjection)
        #expect(!empty.isPassed)
        #expect(AbiturResult.calculate(for: []).totalPoints == 0)
    }
}
