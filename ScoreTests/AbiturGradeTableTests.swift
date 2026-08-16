import Testing
@testable import Score

/// Die amtliche Notentabelle, Zeile für Zeile.
///
/// Die Tabelle ist der Kern der ganzen Rechnung: Kurs- und Prüfungsblock liefern
/// nur eine Zahl, und was aus ihr wird, entscheidet allein Anlage 2 der AGVO.
/// Deshalb wird hier nicht gestichprobt, sondern **jede Stufengrenze von beiden
/// Seiten** geprüft.
@Suite("Notentabelle")
struct AbiturGradeTableTests {

    // MARK: - Aufbau der Tabelle

    @Test("Die Tabelle hat 31 Zeilen, von 1,0 bis 4,0")
    func tableShape() {
        let steps = AbiturGradeTable.steps

        #expect(steps.count == 31)
        #expect(steps.first?.grade == 1.0)
        #expect(steps.last?.grade == 4.0)
        #expect(steps.first?.upperBound == AbiturGradeTable.maximumTotal)
        #expect(steps.last?.lowerBound == AbiturGradeTable.passingTotal)
    }

    @Test("Die Zeilen liegen lückenlos und überschneidungsfrei aneinander")
    func tableIsContiguous() {
        let steps = AbiturGradeTable.steps

        for (index, step) in steps.enumerated() {
            #expect(step.lowerBound <= step.upperBound)

            guard index + 1 < steps.count else { break }
            let next = steps[index + 1]
            // Die nächste Zeile beginnt genau einen Punkt unter dieser.
            #expect(next.upperBound == step.lowerBound - 1)
            // Und sie ist um genau ein Zehntel schlechter.
            #expect(isClose(next.grade, step.grade + 0.1, tolerance: 0.0000001))
        }
    }

    @Test("Jede Stufe ausser der besten und der schlechtesten ist 18 Punkte breit")
    func stepsAreEighteenPointsWide() {
        for step in AbiturGradeTable.steps.dropFirst().dropLast() {
            #expect(step.upperBound - step.lowerBound + 1 == 18)
        }

        // Die 1,0 reicht von 823 bis 900 — nach oben ist bei 900 Schluss, nicht
        // nach 18 Punkten.
        #expect(AbiturGradeTable.steps[0].lowerBound == 823)

        // Die 4,0 ist nur der eine Wert 300: darunter ist nicht bestanden,
        // obwohl die Stufenbreite rechnerisch bis 283 reichte.
        #expect(AbiturGradeTable.steps[30] == AbiturGradeTable.Step(
            lowerBound: 300, upperBound: 300, grade: 4.0
        ))
    }

    // MARK: - Die Grenzen, die der Nutzer genannt hat

    @Test("Ab 823 Punkten steht 1,0")
    func oneZeroStartsAt823() {
        #expect(AbiturGradeTable.grade(forTotalPoints: 823) == 1.0)
        #expect(AbiturGradeTable.grade(forTotalPoints: 900) == 1.0)
        // Ein Punkt weniger ist schon 1,1.
        #expect(AbiturGradeTable.grade(forTotalPoints: 822) == 1.1)
    }

    @Test("Die vom Kultusministerium genannten Ankerwerte stimmen")
    func officialAnchors() {
        #expect(AbiturGradeTable.grade(forTotalPoints: 805) == 1.1)
        #expect(AbiturGradeTable.grade(forTotalPoints: 822) == 1.1)
        #expect(AbiturGradeTable.grade(forTotalPoints: 643) == 2.0)
        #expect(AbiturGradeTable.grade(forTotalPoints: 660) == 2.0)
        #expect(AbiturGradeTable.grade(forTotalPoints: 463) == 3.0)
        #expect(AbiturGradeTable.grade(forTotalPoints: 480) == 3.0)
        #expect(AbiturGradeTable.grade(forTotalPoints: 300) == 4.0)
    }

    @Test("Genau 300 Punkte sind 4,0, genau 299 sind nicht bestanden")
    func passingBoundary() {
        #expect(AbiturGradeTable.grade(forTotalPoints: 300) == 4.0)
        #expect(AbiturGradeTable.grade(forTotalPoints: 299) == nil)
        #expect(AbiturGradeTable.grade(forTotalPoints: 0) == nil)
        // 301 ist bereits 3,9 — die 4,0 hat nur diesen einen Wert.
        #expect(AbiturGradeTable.grade(forTotalPoints: 301) == 3.9)
    }

    // MARK: - Jede Stufengrenze von beiden Seiten

    @Test("An jeder Stufengrenze springt die Note um genau ein Zehntel")
    func everyBoundaryFromBothSides() throws {
        for step in AbiturGradeTable.steps {
            // Innerhalb der Zeile steht überall dieselbe Note.
            #expect(AbiturGradeTable.grade(forTotalPoints: step.lowerBound) == step.grade)
            #expect(AbiturGradeTable.grade(forTotalPoints: step.upperBound) == step.grade)

            // Ein Punkt über der Zeile ist die Note um ein Zehntel besser …
            if step.upperBound < AbiturGradeTable.maximumTotal {
                let better = try #require(AbiturGradeTable.grade(forTotalPoints: step.upperBound + 1))
                #expect(isClose(better, step.grade - 0.1, tolerance: 0.0000001))
            }

            // … und ein Punkt darunter um ein Zehntel schlechter, sofern es
            // unterhalb überhaupt noch eine Note gibt.
            let below = AbiturGradeTable.grade(forTotalPoints: step.lowerBound - 1)
            if step.lowerBound > AbiturGradeTable.passingTotal {
                #expect(isClose(try #require(below), step.grade + 0.1, tolerance: 0.0000001))
            } else {
                #expect(below == nil)
            }
        }
    }

    @Test("Jeder Punktwert von 300 bis 900 hat genau eine Note")
    func everyPointValueIsCovered() {
        for points in AbiturGradeTable.passingTotal...AbiturGradeTable.maximumTotal {
            let matches = AbiturGradeTable.steps.count {
                points >= $0.lowerBound && points <= $0.upperBound
            }
            #expect(matches == 1)
        }
    }

    // MARK: - Gegenprobe mit der kursierenden Formel

    @Test("Die Tabelle stimmt mit der Stufenformel überein")
    func tableMatchesTheStepFormula() throws {
        // Gegenprobe in ganzen Zahlen, ohne Gleitkomma: ab 823 steht 1,0, und
        // darunter geht es je 18 Punkte um ein Zehntel abwärts.
        //
        //     Stufe = ⌊(822 − Gesamt) ÷ 18⌋ + 1
        //     Note  = 1,0 + Stufe ÷ 10
        //
        // Genau diese Formel liesse sich auch im Code verwenden. Sie steht hier
        // und nicht dort, weil eine Formel nicht gegen die Verordnung gelesen
        // werden kann — die Tabelle schon.
        for points in AbiturGradeTable.passingTotal...AbiturGradeTable.maximumTotal {
            let expected: Double
            if points >= 823 {
                expected = 1.0
            } else {
                let step = (822 - points) / 18 + 1
                expected = 1.0 + Double(step) / 10
            }

            let fromTable = try #require(AbiturGradeTable.grade(forTotalPoints: points))
            #expect(isClose(fromTable, expected, tolerance: 0.0000001))
        }
    }

    @Test("Die verbreitete Schreibweise mit 5,66 ist falsch")
    func theRoundedConstantIsWrong() {
        // abschluss-bw.de nennt „5,66 − Gesamtpunktzahl : 180". Bei 804 Punkten
        // ergibt das 1,1933 und damit 1,1 — die Tabelle nennt 1,2. 17/3 ist
        // 5,6666…, und die dritte Stelle entscheidet hier.
        let wrong = 5.66 - 804.0 / 180.0
        #expect((wrong * 10).rounded(.down) / 10 == 1.1)
        #expect(AbiturGradeTable.grade(forTotalPoints: 804) == 1.2)
    }

    // MARK: - Abstand zur nächsten Note

    @Test("Bis zur nächstbesseren Note fehlt der Abstand zur Zeilenobergrenze")
    func pointsToNextGrade() {
        // 660 ist die Obergrenze der 2,0 — ein Punkt mehr ist 1,9.
        #expect(AbiturGradeTable.pointsToNextGrade(fromTotalPoints: 660) == 1)
        #expect(AbiturGradeTable.pointsToNextGrade(fromTotalPoints: 643) == 18)
        // Ab 1,0 geht es nicht mehr besser.
        #expect(AbiturGradeTable.pointsToNextGrade(fromTotalPoints: 823) == nil)
        #expect(AbiturGradeTable.pointsToNextGrade(fromTotalPoints: 900) == nil)
        // Unter 300 gibt es keine Note, von der aus man zählen könnte.
        #expect(AbiturGradeTable.pointsToNextGrade(fromTotalPoints: 299) == nil)
    }
}
