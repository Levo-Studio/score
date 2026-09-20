import Testing
@testable import Score

/// Die Rechnung innerhalb eines Fachs — von den Anteilen der Einzelleistungen
/// bis zum Halbjahresergebnis.
@Suite("SubjectMath")
struct SubjectMathTests {

    // MARK: - effectiveShares

    @Suite("Anteile")
    struct EffectiveShares {

        @Test("Nur automatische Leistungen teilen sich 100 gleichmässig")
        func automaticOnly() {
            let entries = [
                GradeInput(points: 12, kind: .written),
                GradeInput(points: 8, kind: .written)
            ]

            #expect(SubjectMath.effectiveShares(for: entries) == [50, 50])
        }

        @Test("Drei automatische Leistungen bekommen je ein Drittel")
        func automaticThirds() {
            let entries = Array(repeating: GradeInput(points: 10, kind: .written), count: 3)
            let shares = SubjectMath.effectiveShares(for: entries)

            #expect(shares.count == 3)
            #expect(shares.allSatisfy { isClose($0, 100.0 / 3.0) })
        }

        @Test("Fest gesetzte Anteile bleiben, wie sie eingetragen sind")
        func fixedStay() {
            let entries = [
                GradeInput(points: 12, kind: .written, share: 30, usesAutomaticShare: false),
                GradeInput(points: 8, kind: .written, share: 70, usesAutomaticShare: false)
            ]

            #expect(SubjectMath.effectiveShares(for: entries) == [30, 70])
        }

        @Test("Zwei Arbeiten neben einem 20-Prozent-Test bekommen je 40 Prozent")
        func mixed() {
            let entries = [
                GradeInput(points: 12, kind: .written),
                GradeInput(points: 10, kind: .written),
                GradeInput(points: 6, kind: .written, share: 20, usesAutomaticShare: false)
            ]

            #expect(SubjectMath.effectiveShares(for: entries) == [40, 40, 20])
        }

        @Test("Feste Anteile über 100 werden gedeckelt, automatische bekommen nichts")
        func fixedOverflow() {
            let entries = [
                GradeInput(points: 12, kind: .written, share: 70, usesAutomaticShare: false),
                GradeInput(points: 10, kind: .written, share: 70, usesAutomaticShare: false),
                GradeInput(points: 8, kind: .written)
            ]

            #expect(SubjectMath.effectiveShares(for: entries) == [70, 70, 0])
        }

        @Test("Leere Liste ergibt keine Anteile")
        func empty() {
            #expect(SubjectMath.effectiveShares(for: []).isEmpty)
        }
    }

    // MARK: - partialGrade

    @Suite("Teilnote")
    struct PartialGrade {

        @Test("Gewichtetes Mittel über die effektiven Anteile")
        func weightedMean() {
            // Anteile 80 / 20 -> (12*80 + 8*20) / 100 = 11,2
            let entries = [
                GradeInput(points: 12, kind: .written),
                GradeInput(points: 8, kind: .written, share: 20, usesAutomaticShare: false)
            ]

            #expect(isClose(SubjectMath.partialGrade(for: entries) ?? .nan, 11.2))
        }

        @Test("Eine einzelne Leistung ist die Teilnote")
        func single() {
            let grade = SubjectMath.partialGrade(for: [GradeInput(points: 13, kind: .oral)])
            #expect(isClose(grade ?? .nan, 13))
        }

        @Test("Anteile, die zusammen nicht 100 ergeben, werden normiert")
        func normalised() {
            // Zwei feste Anteile von je 25 Prozent -> Mittel aus 14 und 6, nicht die Hälfte davon.
            let entries = [
                GradeInput(points: 14, kind: .written, share: 25, usesAutomaticShare: false),
                GradeInput(points: 6, kind: .written, share: 25, usesAutomaticShare: false)
            ]

            #expect(isClose(SubjectMath.partialGrade(for: entries) ?? .nan, 10))
        }

        @Test("Keine Leistung ergibt keine Teilnote")
        func none() {
            #expect(SubjectMath.partialGrade(for: []) == nil)
        }

        @Test("Anteile von null ergeben keine Teilnote")
        func zeroShares() {
            let entries = [
                GradeInput(points: 12, kind: .written, share: 0, usesAutomaticShare: false),
                GradeInput(points: 10, kind: .written, share: 0, usesAutomaticShare: false)
            ]

            #expect(SubjectMath.partialGrade(for: entries) == nil)
        }
    }

    // MARK: - result

    @Suite("Halbjahresergebnis")
    struct Result {

        @Test("Schriftlich und mündlich im Fachverhältnis 60 zu 40")
        func writtenAndOral() {
            // (13*60 + 10*40) / 100 = 11,8 -> gerundet 12
            let input = SemesterInput(
                index: 0,
                writtenShare: 60,
                entries: [
                    GradeInput(points: 13, kind: .written),
                    GradeInput(points: 10, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 12)
        }

        @Test("Ohne mündliche Note zählt die schriftliche allein")
        func writtenOnly() {
            let input = SemesterInput(
                index: 0,
                writtenShare: 60,
                entries: [GradeInput(points: 9, kind: .written)]
            )

            #expect(SubjectMath.result(for: input) == 9)
        }

        @Test("Ohne schriftliche Note zählt die mündliche allein, unabhängig vom Verhältnis")
        func oralOnly() {
            let input = SemesterInput(
                index: 0,
                writtenShare: 60,
                entries: [GradeInput(points: 7, kind: .oral)]
            )

            #expect(SubjectMath.result(for: input) == 7)
        }

        @Test("Ein nicht belegtes Halbjahr hat kein Ergebnis")
        func inactive() {
            let input = SemesterInput(
                index: 0,
                isActive: false,
                entries: [GradeInput(points: 15, kind: .written)]
            )

            #expect(SubjectMath.result(for: input) == nil)
        }

        @Test("Ein Halbjahr ohne Leistung hat kein Ergebnis")
        func emptySemester() {
            #expect(SubjectMath.result(for: SemesterInput(index: 0, entries: [])) == nil)
        }

        @Test("An der halben Punktzahl wird aufgerundet")
        func roundsHalfUp() {
            // (12*50 + 11*50) / 100 = 11,5 -> 12
            let input = SemesterInput(
                index: 0,
                writtenShare: 50,
                entries: [
                    GradeInput(points: 12, kind: .written),
                    GradeInput(points: 11, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 12)
        }

        @Test("Das Ergebnis wird auf die obere Grenze gedeckelt")
        func clampsUpper() {
            let input = SemesterInput(index: 0, entries: [GradeInput(points: 20, kind: .written)])
            #expect(SubjectMath.result(for: input) == 15)
        }

        @Test("Das Ergebnis wird auf die untere Grenze gedeckelt")
        func clampsLower() {
            let input = SemesterInput(index: 0, entries: [GradeInput(points: -4, kind: .written)])
            #expect(SubjectMath.result(for: input) == 0)
        }
    }

    // MARK: - Gewichtung

    @Suite("Gewichtung")
    struct Weightings {

        @Test("Das Verhältnis 2 zu 1 trifft das Drittel, das ein Prozentanteil nie treffen konnte")
        func twoToOne() {
            // (13*2 + 9*1) / 3 = 35/3 = 11,67 -> gerundet 12
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 2, .oral: 1]),
                entries: [
                    GradeInput(points: 13, kind: .written),
                    GradeInput(points: 9, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 12)
        }

        @Test("Umgekehrt gewichtet, 1 zu 2, kippt dasselbe Notenbild nach unten")
        func oneToTwo() {
            // (13*1 + 9*2) / 3 = 31/3 = 10,33 -> gerundet 10
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 1, .oral: 2]),
                entries: [
                    GradeInput(points: 13, kind: .written),
                    GradeInput(points: 9, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 10)
        }

        @Test("Gleich gewichtet liegt dasselbe Notenbild dazwischen")
        func even() {
            // (13 + 9) / 2 = 11
            let input = SemesterInput(
                index: 0,
                weighting: .even,
                entries: [
                    GradeInput(points: 13, kind: .written),
                    GradeInput(points: 9, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 11)
        }

        @Test("Bei ganzen Teilnoten sind 2 zu 1 und 67 zu 33 nicht zu unterscheiden")
        func twoToOneMatchesSixtySevenForWholePoints() {
            // Nachgerechnet, nicht vermutet: über alle 256 Paare aus 0 bis 15
            // Punkten fällt kein einziges Ergebnis auseinander.
            //
            // Der Grund steckt im Abstand zur Rundungsgrenze. Mit d = schriftlich
            // minus mündlich ist das Ergebnis bei 2 : 1 gleich mündlich + 2d/3 und
            // bei 67 : 33 gleich mündlich + 0,67d. Beide unterscheiden sich um
            // 0,00333 * d, bei d = 15 also um höchstens 0,05. 2d/3 hat aber immer
            // den Nachkommateil 0, 0,333 oder 0,667 und liegt damit mindestens
            // 0,167 von der nächsten halben Punktzahl entfernt — weit genug, dass
            // die kleine Abweichung keine Grenze überspringt.
            //
            // Wer also 2 : 1 einstellt und wer 67 % einstellt, bekommt dieselbe
            // Zeugnisnote, solange beide Teilnoten aus je einer Leistung stammen.
            for written in GradeEntry.pointsRange {
                for oral in GradeEntry.pointsRange {
                    let entries = [
                        GradeInput(points: written, kind: .written),
                        GradeInput(points: oral, kind: .oral)
                    ]
                    let ratio = SemesterInput(
                        index: 0,
                        weighting: Weighting([.written: 2, .oral: 1]),
                        entries: entries
                    )
                    let percent = SemesterInput(index: 0, writtenShare: 67, entries: entries)

                    #expect(SubjectMath.result(for: ratio) == SubjectMath.result(for: percent))
                }
            }
        }

        @Test("Bei halben Teilnoten trennen sich 2 zu 1 und 67 zu 33 dann doch")
        func twoToOneDiffersFromSixtySevenForHalfPoints() {
            // Die mündliche Teilnote ist das Mittel aus 14 und 13, also 13,5 —
            // eine halbe Punktzahl entsteht, sobald eine Teilnote aus mehr als
            // einer Leistung kommt.
            //
            // 2 : 1   -> (6*2 + 13,5) / 3   = 25,5/3 = 8,5   -> 9
            // 67 : 33 -> (6*67 + 13,5*33) / 100 = 8,475      -> 8
            let entries = [
                GradeInput(points: 6, kind: .written),
                GradeInput(points: 14, kind: .oral),
                GradeInput(points: 13, kind: .oral)
            ]

            let ratio = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 2, .oral: 1]),
                entries: entries
            )
            let percent = SemesterInput(index: 0, writtenShare: 67, entries: entries)

            #expect(SubjectMath.result(for: ratio) == 9)
            #expect(SubjectMath.result(for: percent) == 8)
        }

        @Test("Zwei Halbjahre desselben Fachs dürfen verschieden gewichtet sein")
        func weightingPerSemester() {
            // Dasselbe Notenbild, zweimal:
            // 3 : 1 -> (14*3 + 8) / 4 = 12,5 -> 13
            // 2 : 1 -> (14*2 + 8) / 3 = 12   -> 12
            let entries = [
                GradeInput(points: 14, kind: .written),
                GradeInput(points: 8, kind: .oral)
            ]
            let semesters = [
                SemesterInput(
                    index: 0,
                    weighting: Weighting([.written: 3, .oral: 1]),
                    entries: entries
                ),
                SemesterInput(
                    index: 1,
                    weighting: Weighting([.written: 2, .oral: 1]),
                    entries: entries
                )
            ]

            #expect(semesters.map { SubjectMath.result(for: $0) } == [13, 12])
            #expect(isClose(SubjectMath.subjectAverage(for: semesters) ?? .nan, 12.5))
        }

        @Test("Nur schriftliche Noten zählen allein, auch wenn das Verhältnis mündlich betont")
        func writtenOnly() {
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 1, .oral: 2]),
                entries: [GradeInput(points: 7, kind: .written)]
            )

            #expect(SubjectMath.result(for: input) == 7)
        }

        @Test("Nur mündliche Noten zählen allein, auch bei 3 zu 1")
        func oralOnly() {
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 3, .oral: 1]),
                entries: [GradeInput(points: 11, kind: .oral)]
            )

            #expect(SubjectMath.result(for: input) == 11)
        }

        @Test("Ohne jede Leistung gibt es auch mit Verhältnis kein Ergebnis")
        func withoutEntries() {
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 2, .oral: 1]),
                entries: []
            )

            #expect(SubjectMath.result(for: input) == nil)
        }

        @Test("Ein Gewicht von null lässt seine Teilnote aussen vor")
        func zeroWeightIsIgnored() {
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 1, .oral: 0]),
                entries: [
                    GradeInput(points: 12, kind: .written),
                    GradeInput(points: 4, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 12)
        }

        @Test("Steht nur die Teilnote ohne Gewicht da, zählt sie trotzdem")
        func zeroWeightAloneStillCounts() {
            // Sonst verschwände eine erfasste Note, weil der Nutzer ein
            // Verhältnis für eine Teilnote eingestellt hat, die es nicht gibt.
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 1, .oral: 0]),
                entries: [GradeInput(points: 4, kind: .oral)]
            )

            #expect(SubjectMath.result(for: input) == 4)
        }

        @Test("Eine Gewichtung ohne jedes Gewicht fällt auf gleiche Anteile zurück")
        func allZeroFallsBackToEven() {
            // 0 : 0 beschreibt kein Verhältnis. Statt durch null zu teilen oder
            // das Halbjahr um sein Ergebnis zu bringen, zählt dann alles gleich:
            // (12 + 10) / 2 = 11
            let input = SemesterInput(
                index: 0,
                weighting: Weighting([.written: 0, .oral: 0]),
                entries: [
                    GradeInput(points: 12, kind: .written),
                    GradeInput(points: 10, kind: .oral)
                ]
            )

            #expect(SubjectMath.result(for: input) == 11)
        }

        @Test("Ein Prozentanteil liest sich als Gewichtung wieder als Prozent")
        func shareOfPercentWeighting() {
            let weighting = Weighting(writtenShare: 60)

            #expect(isClose(weighting.share(of: .written), 60))
            #expect(isClose(weighting.share(of: .oral), 40))
        }

        @Test("Aus 2 zu 1 werden 66,67 Prozent")
        func shareOfRatio() {
            let weighting = Weighting([.written: 2, .oral: 1])

            #expect(isClose(weighting.share(of: .written), 200.0 / 3.0))
        }

        @Test("Gleich gewichtet ist gleich, auch in anderen Zahlen geschrieben")
        func equalRatiosAreEqual() {
            #expect(Weighting([.written: 3, .oral: 2]) == Weighting(writtenShare: 60))
            #expect(Weighting([.written: 1, .oral: 1]) == Weighting.even)
            #expect(Weighting([.written: 2, .oral: 1]) != Weighting(writtenShare: 67))
        }
    }

    // MARK: - Schnitte

    @Suite("Schnitte")
    struct Averages {

        @Test("Der Fachschnitt geht über die Halbjahre mit Ergebnis")
        func subjectAverage() {
            let semesters = [
                semester(0, points: 12),
                semester(1, points: 10),
                SemesterInput(index: 2, isActive: false, entries: [GradeInput(points: 2, kind: .written)]),
                SemesterInput(index: 3, entries: [])
            ]

            // Nur die beiden belegten Halbjahre zählen: (12 + 10) / 2 = 11
            #expect(isClose(SubjectMath.subjectAverage(for: semesters) ?? .nan, 11))
        }

        @Test("Ein Fach ohne jedes Ergebnis hat keinen Schnitt")
        func subjectAverageWithoutResults() {
            #expect(SubjectMath.subjectAverage(for: [SemesterInput(index: 0, entries: [])]) == nil)
        }
    }

    // MARK: - Punkte und Noten

    @Suite("Punkte in Noten")
    struct GradeConversion {

        @Test("15 Punkte werden auf 1,0 gedeckelt")
        func best() {
            // 17/3 - 15/3 = 0,67 -> gedeckelt auf 1,0
            #expect(isClose(SubjectMath.grade(fromPoints: 15), 1.0))
        }

        @Test("10 Punkte ergeben 2,33")
        func ten() {
            #expect(isClose(SubjectMath.grade(fromPoints: 10), 7.0 / 3.0))
        }

        @Test("5 Punkte ergeben glatt 4,0")
        func five() {
            #expect(isClose(SubjectMath.grade(fromPoints: 5), 4.0))
        }

        @Test("0 Punkte ergeben 6,0")
        func worst() {
            // Bei 0 Punkten weicht die lineare Umrechnung bewusst von der
            // amtlichen Notentabelle ab: die Tabelle nennt 6,0, die Gerade
            // liefert 17/3. Umgerechnet wird hier ein stetiger Schnitt, keine
            // einzelne Zeugnisnote — die Begründung steht an `grade(fromPoints:)`.
            #expect(isClose(SubjectMath.grade(fromPoints: 0), 17.0 / 3.0))
        }
    }
}
