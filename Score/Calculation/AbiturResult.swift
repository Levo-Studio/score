import Foundation

/// Die Gesamtqualifikation: Kursblock plus Prüfungsblock, und die Note, die
/// daraus folgt.
///
/// ## Die Rechnung in drei Zeilen
///
/// ```
/// Kursblock     0 … 600   mindestens 200
/// Prüfungsblock 0 … 300   mindestens 100
/// Gesamt        300 … 900 → Note nach AbiturGradeTable
/// ```
///
/// Mehr ist es nicht. Die ganze Schwierigkeit steckt in den beiden Blöcken selbst
/// — in ``BlockOneCalculator``, wo entschieden wird, welche 40 Kurse eingehen und
/// welche zwei Leistungsfächer doppelt zählen, und in ``BlockTwoCalculator``, wo
/// die fünf Prüfungen vierfach gewertet werden.
///
/// ## Warum es zwei Mindestbedingungen gibt und nicht nur eine
///
/// 200 im Kursblock und 100 im Prüfungsblock sind keine Rundungsdetails, sondern
/// eigene Hürden: wer 590 im Kursblock hat und 90 im Prüfungsblock, kommt auf 680
/// Punkte und wäre nach der Tabelle bei 1,9 — hat das Abitur aber nicht bestanden.
/// Eine App, die in diesem Fall „1,9" anzeigt und sonst nichts, lügt. Deshalb
/// trägt ``Outcome`` die drei Bedingungen einzeln und nicht als ein Ja/Nein.
///
/// ## Hochrechnung, solange Prüfungen fehlen
///
/// Vor dem Abitur gibt es keine Prüfungsergebnisse. Score rechnet trotzdem — mit
/// dem, was da ist — und markiert das Ergebnis über ``Outcome/isProjection``. Die
/// fehlenden Prüfungen gehen dabei **nicht als 0** ein; sie fehlen schlicht, und
/// die Gesamtpunktzahl ist entsprechend niedriger als sie am Ende sein wird.
/// Deshalb steht neben der Hochrechnung immer, worauf sie beruht.
///
/// Quelle: Abiturverordnung Gymnasien der Normalform (AGVO) vom 19. Oktober 2018,
/// §§ 21 f. und Anlage 2; Kultusministerium Baden-Württemberg, „Leitfaden für die
/// gymnasiale Oberstufe".
enum AbiturResult {

    /// Woran ein Abitur scheitern kann.
    ///
    /// Alle drei zugleich sind möglich; deshalb eine Menge und keine Auswahl.
    enum FailedCondition: Sendable, Equatable, Hashable, CaseIterable {
        /// Weniger als 200 Punkte im Kursblock.
        case courseBlockBelowMinimum
        /// Weniger als 100 Punkte im Prüfungsblock.
        case examBlockBelowMinimum
        /// Weniger als 300 Punkte insgesamt.
        case totalBelowMinimum
    }

    /// Das Gesamtergebnis.
    struct Outcome: Sendable, Equatable {
        var courseBlock: BlockOneCalculator.Outcome
        var examBlock: BlockTwoCalculator.Outcome

        /// Das Niveau, auf dem Score noch fehlende Prüfungen ansetzt, 0 bis 15.
        ///
        /// Der Schnitt der schon geprüften Fächer, und solange keines geprüft ist,
        /// das Niveau des Kursblocks. Beides ist dasselbe Prinzip wie im
        /// Kursblock: was fehlt, wird auf dem gezeigten Stand fortgeschrieben und
        /// nicht mit null angesetzt.
        var projectionLevel: Double {
            examBlock.averageResult ?? courseBlock.averagePoints
        }

        /// Die Punktzahl des Prüfungsblocks, wie Score sie erwartet.
        ///
        /// Bei vollständigem Prüfungsblock identisch mit ``BlockTwoCalculator/Outcome/points``.
        var projectedExamBlockPoints: Int {
            min(
                BlockTwoCalculator.maximumPoints,
                examBlock.projectedPoints(assuming: projectionLevel)
            )
        }

        /// Kursblock plus Prüfungsblock, 0 bis 900 — mit hochgerechneten Prüfungen,
        /// solange welche fehlen.
        ///
        /// Das ist die Zahl, die auf dem Bildschirm steht. Was heute schon
        /// feststeht, steht in ``recordedTotalPoints``.
        var totalPoints: Int {
            courseBlock.points + projectedExamBlockPoints
        }

        /// Kursblock plus die Prüfungen, die wirklich schon geschrieben sind.
        ///
        /// Vor dem Abitur eine niedrige Zahl und für sich genommen keine gute
        /// Auskunft — aber die einzige, die ohne Annahme auskommt.
        var recordedTotalPoints: Int {
            courseBlock.points + examBlock.points
        }

        /// Die Durchschnittsnote aus der amtlichen Tabelle.
        ///
        /// `nil` heisst „unter 300 Punkten" und damit: so reicht es nicht. Solange
        /// ``isProjection`` gilt, ist auch das eine Hochrechnung.
        var grade: Double? {
            AbiturGradeTable.grade(forTotalPoints: totalPoints)
        }

        /// Ob das Ergebnis eine Hochrechnung ist — weil Prüfungen **oder** Kurse
        /// fehlen.
        ///
        /// Der Prüfungsblock ist der offensichtliche Fall. Der Kursblock ist der
        /// stillere: sein Schnitt wird durch die tatsächliche Zahl der Wertungen
        /// geteilt und auf 40 Kurse gestreckt, damit ein fehlender Kurs nicht als
        /// null zählt. Wer drei Kurse mit je 15 Punkten erfasst hat, steht damit
        /// bei 600 von 600 — und mit vollständigen Prüfungen stünde ohne diese
        /// Prüfung „bestanden, 900 Punkte" auf dem Bildschirm, für einen Jahrgang,
        /// von dem 37 Kurse fehlen. Eine Zahl, die aus wenigen Kursen
        /// fortgeschrieben ist, ist eine Aussicht wie jede andere.
        var isProjection: Bool {
            !examBlock.isComplete || courseBlock.isProjection
        }

        /// Die Bedingungen, die gerade nicht erfüllt sind.
        ///
        /// Gerechnet auf denselben Zahlen wie die angezeigte Note, also mit
        /// hochgerechneten Prüfungen. Sonst stünde vor dem Abitur bei jedem
        /// Schüler „Prüfungsblock unter 100" — richtig, aber nichtssagend.
        ///
        /// Solange ``isProjection`` gilt, ist eine nicht leere Menge eine Warnung
        /// und kein Urteil: erst mit vollständigem Prüfungsblock heisst sie
        /// „nicht bestanden".
        var failedConditions: Set<FailedCondition> {
            var failed: Set<FailedCondition> = []
            if courseBlock.points < BlockOneCalculator.passingPoints {
                failed.insert(.courseBlockBelowMinimum)
            }
            if projectedExamBlockPoints < BlockTwoCalculator.passingPoints {
                failed.insert(.examBlockBelowMinimum)
            }
            if totalPoints < AbiturGradeTable.passingTotal {
                failed.insert(.totalBelowMinimum)
            }
            return failed
        }

        /// Ob das Abitur nach dem heutigen Stand bestanden ist.
        ///
        /// Nur wahr, wenn nichts mehr fehlt **und** alle drei Bedingungen erfüllt
        /// sind. Eine Hochrechnung ist nie „bestanden" — sie ist eine Aussicht.
        var isPassed: Bool {
            !isProjection && failedConditions.isEmpty
        }

        /// Wie viele Punkte bis zur nächstbesseren Note fehlen.
        var pointsToNextGrade: Int? {
            AbiturGradeTable.pointsToNextGrade(fromTotalPoints: totalPoints)
        }
    }

    // MARK: - Rechnung

    /// Rechnet beide Blöcke und setzt sie zusammen.
    static func calculate(for subjects: [SubjectInput]) -> Outcome {
        Outcome(
            courseBlock: BlockOneCalculator.calculate(for: subjects),
            examBlock: BlockTwoCalculator.calculate(for: subjects)
        )
    }

    /// Das leere Ergebnis, mit dem Ansichten starten, bevor Daten da sind.
    static let empty = Outcome(
        courseBlock: BlockOneCalculator.Outcome(
            points: 0,
            averagePoints: 0,
            weightedPointsTotal: 0,
            includedCourses: [],
            doubleWeightedSubjectIDs: [],
            effectiveWeightingCount: 0,
            usesAutomaticDoubleWeighting: true,
            bracketReasons: [:],
            recordedCount: 0
        ),
        examBlock: BlockTwoCalculator.Outcome(
            points: 0,
            exams: [],
            recordedExamCount: 0,
            expectedExamCount: 0
        )
    )
}
