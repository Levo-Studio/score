import Testing
@testable import Score

/// Die Kursauswahl für Block I und der Schnitt, der daraus folgt.
///
/// Alle Erwartungswerte sind von Hand ausgerechnet und stehen als Literale im
/// Test. Wo eine Rechnung nicht offensichtlich ist, steht sie als Kommentar
/// daneben.
@Suite("BlockOneCalculator")
struct BlockOneCalculatorTests {

    // MARK: - Vollständiger Jahrgang

    /// Ein Jahrgang, wie er typischerweise aussieht: drei Leistungsfächer, drei
    /// Pflicht-Basisfächer neben den Leistungsfächern und sechs Wahl-Basisfächer.
    ///
    /// Verfügbar sind 48 Kurse, eingebracht werden 40 — acht Wahl-Basisfach-Kurse
    /// fallen heraus.
    static let fullYear: [SubjectInput] = [
        subject("lf-deutsch", .leistungsfach, allPoints: 12),
        subject("lf-mathematik", .leistungsfach, allPoints: 11),
        subject("lf-biologie", .leistungsfach, allPoints: 13),

        subject("kf-englisch", .pflichtBasisfach, allPoints: 10),
        subject("kf-geschichte", .pflichtBasisfach, allPoints: 9),
        subject("kf-gemeinschaftskunde", .pflichtBasisfach, allPoints: 11),

        subject("bf-physik", .wahlBasisfach, allPoints: 14),
        subject("bf-chemie", .wahlBasisfach, allPoints: 13),
        subject("bf-geografie", .wahlBasisfach, allPoints: 12),
        subject("bf-sport", .wahlBasisfach, allPoints: 11),
        subject("bf-religion", .wahlBasisfach, allPoints: 5),
        subject("bf-musik", .wahlBasisfach, allPoints: 4)
    ]

    @Test("Ein voller Jahrgang bringt genau 40 Kurse ein")
    func fullYearIncludesExactly40() {
        let outcome = BlockOneCalculator.calculate(for: Self.fullYear)

        #expect(outcome.recordedCount == 48)
        #expect(outcome.includedCount == 40)
        #expect(outcome.excludedCourses.count == 8)
    }

    @Test("Die schwächsten Wahl-Basisfach-Kurse werden automatisch geklammert")
    func fullYearDropsWeakestOptionalCourses() {
        let outcome = BlockOneCalculator.calculate(for: Self.fullYear)

        // 40 Kurse minus 12 Leistungs- und 12 Pflicht-Basisfach-Kurse lassen 16 für
        // die Wahl-Basisfächer. Physik, Chemie, Geografie und Sport füllen sie
        // genau aus — Religion und Musik fallen vollständig heraus.
        #expect(outcome.automaticallyBracketedCourses == [
            course("bf-religion", 0),
            course("bf-religion", 1),
            course("bf-religion", 2),
            course("bf-religion", 3),
            course("bf-musik", 0),
            course("bf-musik", 1),
            course("bf-musik", 2),
            course("bf-musik", 3)
        ])
    }

    @Test("Leistungs- und Pflicht-Basisfächer fallen nie heraus")
    func fullYearNeverDropsMandatoryCourses() {
        let outcome = BlockOneCalculator.calculate(for: Self.fullYear)

        let mandatoryIDs = Self.fullYear
            .filter { $0.kind != .wahlBasisfach }
            .flatMap { subject in subject.semesters.map { course(subject.id, $0.index) } }

        #expect(mandatoryIDs.count == 24)
        for identifier in mandatoryIDs {
            #expect(outcome.includedCourses.contains(identifier))
            #expect(!outcome.excludedCourses.contains(identifier))
        }
    }

    @Test("Der Schnitt des vollen Jahrgangs stimmt")
    func fullYearAverage() {
        let outcome = BlockOneCalculator.calculate(for: Self.fullYear)

        // Leistungsfächer     (12+11+13)*4 = 144
        // Pflicht-Basisfächer (10+ 9+11)*4 = 120
        // Wahl-Basisfächer    (14+13+12+11)*4 = 200
        // Summe der 40 Kurse                  = 464
        //
        // Doppelt gewertet werden die beiden stärksten Leistungsfächer: Biologie
        // (13*4 = 52) und Deutsch (12*4 = 48), zusammen 100 zusätzliche Punkte auf
        // acht zusätzlichen Wertungen.
        //
        // 464 + 100 = 564 auf 48 Wertungen = 11,75
        #expect(outcome.weightedPointsTotal == 564)
        #expect(outcome.effectiveWeightingCount == 48)
        #expect(isClose(outcome.averagePoints, 11.75))
        #expect(outcome.doubleWeightedSubjectIDs == ["lf-biologie", "lf-deutsch"])
        #expect(outcome.usesAutomaticDoubleWeighting)
        // 11,75 * 40 = 470
        #expect(outcome.points == 470)
    }

    // MARK: - Die eigentliche Regel

    @Test("Ein schwaches Pflicht-Basisfach wird nicht von einem starken Wahl-Basisfach verdrängt")
    func weakMandatorySubjectSurvives() {
        var subjects = Self.fullYear
        // Geschichte steht auf 3 Punkten — schlechter als jedes Wahl-Basisfach.
        subjects[4] = subject("kf-geschichte", .pflichtBasisfach, allPoints: 3)

        let outcome = BlockOneCalculator.calculate(for: subjects)

        for index in 0..<4 {
            #expect(outcome.includedCourses.contains(course("kf-geschichte", index)))
            #expect(!outcome.excludedCourses.contains(course("kf-geschichte", index)))
        }

        // Gleichzeitig fliegt Musik mit 4 Punkten heraus, obwohl es besser
        // dasteht als Geschichte. Genau das ist der Sinn der Regel: Pflicht-Basisfächer
        // sind gesetzt, Wahl-Basisfächer konkurrieren.
        #expect(outcome.excludedCourses.contains(course("bf-musik", 0)))
        #expect(outcome.includedCourses.contains(course("bf-physik", 0)))
        #expect(outcome.includedCount == 40)
    }

    // MARK: - Zu wenig Kurse

    @Test("In Kursstufe 1 kommen weniger als 40 Kurse zusammen")
    func firstYearHasTooFewCourses() {
        let subjects = [
            subject("lf-deutsch", .leistungsfach, points: [13, 13]),
            subject("lf-mathematik", .leistungsfach, points: [12, 12]),
            subject("lf-biologie", .leistungsfach, points: [11, 11]),

            subject("kf-englisch", .pflichtBasisfach, points: [10, 10]),
            subject("kf-geschichte", .pflichtBasisfach, points: [9, 9]),
            subject("kf-gemeinschaftskunde", .pflichtBasisfach, points: [14, 14]),

            subject("bf-physik", .wahlBasisfach, points: [12, 12]),
            subject("bf-chemie", .wahlBasisfach, points: [8, 8]),
            subject("bf-geografie", .wahlBasisfach, points: [7, 7]),
            subject("bf-sport", .wahlBasisfach, points: [15, 15]),
            subject("bf-religion", .wahlBasisfach, points: [10, 10]),
            subject("bf-musik", .wahlBasisfach, points: [6, 6])
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // 24 Kurse, davon 6 aus Pflicht-Basisfächern — die 24 freien Plätze reichen für
        // alle zwölf Wahl-Basisfach-Kurse. Es fällt nichts heraus.
        #expect(outcome.includedCount == 24)
        #expect(outcome.includedCount < BlockOneCalculator.totalCourseCount)
        #expect(outcome.excludedCourses.isEmpty)

        // (13+12+11 + 10+9+14 + 12+8+7+15+10+6) * 2 = 254 über 24 Kurse.
        // Doppelt gewertet werden Deutsch (13*2 = 26) und Mathematik (12*2 = 24),
        // zusammen 50 auf vier zusätzlichen Wertungen.
        //
        // 254 + 50 = 304 auf 28 Wertungen = 10,857…
        #expect(outcome.weightedPointsTotal == 304)
        #expect(outcome.effectiveWeightingCount == 28)
        #expect(isClose(outcome.averagePoints, 10.8571, tolerance: 0.001))

        // 304/28 * 40 = 434,28… — abgerundet.
        #expect(outcome.points == 434)
    }

    // MARK: - Mehr Pflicht-Basisfächer als Plätze

    @Test("Belegen die Pflicht-Basisfächer alle Plätze, bleibt für Wahl-Basisfächer nichts")
    func mandatorySubjectsFillEverySlot() {
        let advanced = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
        // Acht Pflicht-Basisfächer sind mehr, als die Prüfungsordnung vorsieht — der
        // Rechenkern muss den Fall trotzdem sauber behandeln.
        let mandatory = (1...8).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 10) }
        let optional = (1...2).map { subject("bf-\($0)", .wahlBasisfach, allPoints: 15) }

        let outcome = BlockOneCalculator.calculate(for: advanced + mandatory + optional)

        // 12 Leistungsfach- und 32 Pflicht-Basisfach-Kurse sind schon mehr als die
        // 40: kein freier Platz, alle acht Wahl-Basisfach-Kurse fallen heraus —
        // auch die mit 15 Punkten.
        #expect(outcome.excludedCourses.count == 8)
        for index in 1...2 {
            for semesterIndex in 0..<4 {
                #expect(outcome.excludedCourses.contains(course("bf-\(index)", semesterIndex)))
            }
        }

        // Gesetzte Kurse werden nie gekürzt, deshalb liegt die Zahl der
        // eingebrachten Kurse hier über den nominellen 40.
        #expect(outcome.includedCount == 44)

        // (12*12 + 32*10) = 464 über 44 Kurse. Alle drei Leistungsfächer stehen
        // gleich; bei Gleichstand entscheidet die Fachkennung, also lf-1 und lf-2
        // mit zusammen 96 zusätzlichen Punkten.
        //
        // 464 + 96 = 560 auf 52 Wertungen = 10,769…
        #expect(outcome.doubleWeightedSubjectIDs == ["lf-1", "lf-2"])
        #expect(isClose(outcome.averagePoints, 10.7692, tolerance: 0.001))
        #expect(outcome.points == 431)
    }

    // MARK: - Stabilität

    @Test("Bei Gleichstand an der Klammergrenze bleibt die Auswahl stabil")
    func selectionIsStableOnTies() {
        // 12 Leistungsfach- und 27 Pflicht-Basisfach-Kurse sind 39 nicht
        // klammerbare — von den 40 bleibt genau einer offen.
        let mandatory = (1...6).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 10) }
            + [subject("kf-7", .pflichtBasisfach, points: [10, 10, 10])]
        let optional = [
            subject("bf-alpha", .wahlBasisfach, points: [10, 10]),
            subject("bf-beta", .wahlBasisfach, points: [10])
        ]

        let advanced = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
        let subjects = advanced + mandatory + optional

        let first = BlockOneCalculator.calculate(for: subjects)
        let second = BlockOneCalculator.calculate(for: subjects)

        #expect(first == second)

        // Drei gleich gute Kurse auf einen Platz: es gewinnt die kleinere
        // Fachkennung, bei gleicher Kennung das frühere Halbjahr.
        #expect(first.includedCourses.contains(course("bf-alpha", 0)))
        #expect(first.excludedCourses == [course("bf-alpha", 1), course("bf-beta", 0)])
    }

    // MARK: - Punktsumme und Note

    @Test("Die Punkte des Kursblocks sind der Schnitt je Wertung auf 40 hochgerechnet")
    func coursePointsFromAverage() {
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 11) }
            + (1...2).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 8) }

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // (12*11 + 8*8) = 196 über 20 Kurse. Doppelt zählen lf-1 und lf-2 mit je
        // 44, zusammen 88 auf acht zusätzlichen Wertungen.
        //
        // 196 + 88 = 284 auf 28 Wertungen = 10,142…
        #expect(isClose(outcome.averagePoints, 10.1429, tolerance: 0.001))
        // 284/28 * 40 = 405,71… — aufgerundet.
        #expect(outcome.points == 406)
    }

    @Test("Ohne einen einzigen Punkt bleibt der Kursblock bei null")
    func zeroPointsGiveZeroPoints() {
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 0) }
            + (1...3).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 0) }

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(isClose(outcome.averagePoints, 0))
        #expect(outcome.points == 0)
        #expect(!outcome.meetsMinimum)
    }

    @Test("Durchweg 15 Punkte ergeben genau die 600 des Kursblocks")
    func fifteenPointsGiveTheMaximum() {
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 15) }
            + (1...3).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 15) }

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // 24 Kurse und acht doppelte Wertungen, alle auf 15: der Schnitt je
        // Wertung bleibt 15, ganz gleich wie oft man verdoppelt.
        #expect(isClose(outcome.averagePoints, 15))
        // 15 * 40 = 600 — der Höchstwert des Kursblocks.
        #expect(outcome.points == BlockOneCalculator.maximumPoints)
        #expect(outcome.meetsMinimum)
    }

    // MARK: - Doppelwertung

    @Test("Von sich aus verdoppelt Score die beiden stärksten Leistungsfächer")
    func automaticDoubleWeightingPicksTheStrongest() {
        let subjects = [
            subject("lf-a", .leistungsfach, allPoints: 8),
            subject("lf-b", .leistungsfach, allPoints: 14),
            subject("lf-c", .leistungsfach, allPoints: 11)
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.doubleWeightedSubjectIDs == ["lf-b", "lf-c"])
        #expect(outcome.usesAutomaticDoubleWeighting)

        // (8 + 14 + 11) * 4 = 132 über 12 Kurse, dazu (14 + 11) * 4 = 100.
        // 232 auf 20 Wertungen = 11,6
        #expect(isClose(outcome.averagePoints, 11.6))
    }

    @Test("Genau zwei gesetzte Leistungsfächer übersteuern die automatische Wahl")
    func manualDoubleWeightingWins() {
        let subjects = [
            subject("lf-a", .leistungsfach, allPoints: 8, isDoubleWeighted: true),
            subject("lf-b", .leistungsfach, allPoints: 14),
            subject("lf-c", .leistungsfach, allPoints: 11, isDoubleWeighted: true)
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.doubleWeightedSubjectIDs == ["lf-a", "lf-c"])
        #expect(!outcome.usesAutomaticDoubleWeighting)

        // 132 über 12 Kurse, dazu (8 + 11) * 4 = 76. 208 auf 20 Wertungen = 10,4.
        // Schlechter als die automatische Wahl — und genau so gewollt.
        #expect(isClose(outcome.averagePoints, 10.4))
    }

    @Test("Eine halbe Wahl ist keine Wahl")
    func incompleteManualDoubleWeightingFallsBack() {
        let onlyOne = [
            subject("lf-a", .leistungsfach, allPoints: 8, isDoubleWeighted: true),
            subject("lf-b", .leistungsfach, allPoints: 14),
            subject("lf-c", .leistungsfach, allPoints: 11)
        ]
        // Drei gesetzte Kennzeichen kann ein Sync zwischen zwei Geräten erzeugen.
        let allThree = onlyOne.map { input -> SubjectInput in
            var copy = input
            copy.isDoubleWeighted = true
            return copy
        }

        for subjects in [onlyOne, allThree] {
            let outcome = BlockOneCalculator.calculate(for: subjects)
            #expect(outcome.usesAutomaticDoubleWeighting)
            #expect(outcome.doubleWeightedSubjectIDs == ["lf-b", "lf-c"])
        }
    }

    @Test("Geklammerte Kurse werden auch dann nicht verdoppelt, wenn ihr Fach doppelt zählt")
    func doubleWeightingCountsOnlyIncludedCourses() {
        // Ein Leistungsfach mit nur zwei erfassten Halbjahren: verdoppelt wird,
        // was eingeht, nicht was die Regel nominell vorsieht.
        let subjects = [
            subject("lf-a", .leistungsfach, points: [15, 15]),
            subject("lf-b", .leistungsfach, allPoints: 10),
            subject("lf-c", .leistungsfach, allPoints: 3)
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // lf-b bringt 40 Punkte über vier Kurse, lf-a nur 30 über zwei. Verdoppelt
        // wird die Summe, also gewinnt lf-b — obwohl lf-a den besseren Schnitt hat.
        #expect(outcome.doubleWeightedSubjectIDs == ["lf-a", "lf-b"])

        // 30 + 40 + 12 = 82 über 10 Kurse, dazu 30 + 40 = 70 über sechs weitere.
        #expect(outcome.weightedPointsTotal == 152)
        #expect(outcome.effectiveWeightingCount == 16)
        #expect(isClose(outcome.averagePoints, 9.5))
    }

    // MARK: - Kursgrenze eines Fachs

    /// Drei Leistungsfächer und ein einzelnes Wahl-Basisfach. Plätze sind reichlich da —
    /// was hier herausfällt, fällt allein wegen der Kursgrenze heraus.
    private static func limitScenario(_ limit: Int?) -> [SubjectInput] {
        (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [subject("bf-sport", .wahlBasisfach, points: [4, 15, 9, 7], limit: limit)]
    }

    @Test("Mit Grenze 2 bringt ein Fach seine besten zwei Ergebnisse ein")
    func subjectLimitKeepsBestCourses() {
        let outcome = BlockOneCalculator.calculate(for: Self.limitScenario(2))

        // Sport steht auf 4, 15, 9 und 7 — die besten zwei sind HJ 2 und HJ 3.
        #expect(outcome.includedCourses.contains(course("bf-sport", 1)))
        #expect(outcome.includedCourses.contains(course("bf-sport", 2)))
        #expect(outcome.excludedCourses == [course("bf-sport", 0), course("bf-sport", 3)])
        #expect(outcome.coursesBeyondSubjectLimit == [course("bf-sport", 0), course("bf-sport", 3)])

        // Alle vier Halbjahre sind erfasst, eingebracht werden 12 + 2.
        #expect(outcome.recordedCount == 16)
        #expect(outcome.includedCount == 14)

        // 12 · 12 + 15 + 9 = 168 über 14 Kurse. Doppelt zählen lf-1 und lf-2 mit
        // je 48, zusammen 96 auf acht zusätzlichen Wertungen.
        //
        // 168 + 96 = 264 auf 22 Wertungen = 12,0 Punkte
        #expect(isClose(outcome.averagePoints, 12))
        #expect(outcome.points == 480)
    }

    @Test("Ohne Grenze bleibt alles wie bisher")
    func withoutLimitNothingChanges() {
        let outcome = BlockOneCalculator.calculate(for: Self.limitScenario(nil))

        #expect(outcome.excludedCourses.isEmpty)
        #expect(outcome.coursesBeyondSubjectLimit.isEmpty)
        #expect(outcome.includedCount == 16)

        // 12 · 12 + 4 + 15 + 9 + 7 = 179 über 16 Kurse, dazu 96 aus der
        // Doppelwertung von lf-1 und lf-2: 275 auf 24 Wertungen.
        #expect(isClose(outcome.averagePoints, 275.0 / 24.0))
    }

    @Test("Eine Grenze über der Zahl der Ergebnisse bleibt wirkungslos")
    func limitAboveRecordedCountIsHarmless() {
        let generous = BlockOneCalculator.calculate(for: Self.limitScenario(6))
        let none = BlockOneCalculator.calculate(for: Self.limitScenario(nil))

        #expect(generous.includedCount == none.includedCount)
        #expect(generous.excludedCourses.isEmpty)
        #expect(isClose(generous.averagePoints, none.averagePoints))
    }

    @Test("Bei Gleichstand innerhalb eines Fachs gewinnt das frühere Halbjahr")
    func limitPrefersEarlierSemesterOnTies() {
        let subjects = [subject("bf-musik", .wahlBasisfach, points: [9, 9, 9, 4], limit: 2)]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.includedCourses == [course("bf-musik", 0), course("bf-musik", 1)])
        #expect(outcome.coursesBeyondSubjectLimit == [course("bf-musik", 2), course("bf-musik", 3)])
    }

    @Test("Die Grenze greift vor dem Wettbewerb um die freien Plätze")
    func limitAppliesBeforeCompetition() {
        // 12 Leistungsfach- und 26 Pflicht-Basisfach-Kurse belegen 38 der 40 —
        // es bleiben genau zwei.
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + (1...6).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 10) }
            + [subject("kf-7", .pflichtBasisfach, points: [10, 10])]
            + [
                subject("bf-alpha", .wahlBasisfach, allPoints: 15, limit: 1),
                subject("bf-beta", .wahlBasisfach, allPoints: 8)
            ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // Ohne Grenze nähme Alpha mit zweimal 15 beide Plätze. Mit Grenze 1 bringt
        // es nur einen Kurs mit, der zweite Platz geht an Beta — obwohl Beta
        // schlechter dasteht.
        #expect(outcome.includedCourses.contains(course("bf-alpha", 0)))
        #expect(outcome.includedCourses.contains(course("bf-beta", 0)))
        #expect(outcome.coursesBeyondSubjectLimit == [
            course("bf-alpha", 1), course("bf-alpha", 2), course("bf-alpha", 3)
        ])
        #expect(outcome.excludedCourses.count == 6)

        #expect(outcome.recordedCount == 46)
        #expect(outcome.includedCount == 40)
        // 12 · 12 + 26 · 10 + 15 + 8 = 427 über 40 Kurse, dazu 96 aus der
        // Doppelwertung von lf-1 und lf-2: 523 auf 48 Wertungen.
        #expect(isClose(outcome.averagePoints, 523.0 / 48.0))
        #expect(outcome.points == 436)
    }

    @Test("Leistungsfächer bringen immer alle vier Halbjahre ein")
    func advancedSubjectsIgnoreTheLimit() {
        let subjects = [subject("lf-deutsch", .leistungsfach, points: [15, 3, 3, 3], limit: 1)]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.includedCount == 4)
        #expect(outcome.excludedCourses.isEmpty)
        #expect(outcome.coursesBeyondSubjectLimit.isEmpty)
        // (15 + 3 + 3 + 3) / 4 = 6,0
        #expect(isClose(outcome.averagePoints, 6))
    }

    // MARK: - Randfälle

    @Test("Ohne Fächer kommt ein leeres, aber gültiges Ergebnis heraus")
    func emptyInput() {
        let outcome = BlockOneCalculator.calculate(for: [])

        #expect(outcome.recordedCount == 0)
        #expect(outcome.includedCount == 0)
        #expect(outcome.excludedCourses.isEmpty)
        #expect(isClose(outcome.averagePoints, 0))
        #expect(outcome.points == 0)
        #expect(outcome.doubleWeightedSubjectIDs.isEmpty)
    }

    @Test("Fächer ohne erfasste Leistung sind keine Kurse mit null Punkten")
    func semestersWithoutEntriesAreNoCourses() {
        let subjects = [
            subject("lf-deutsch", .leistungsfach, points: [12, 12]),
            SubjectInput(
                id: "bf-musik",
                kind: .wahlBasisfach,
                semesters: [
                    SemesterInput(index: 0, entries: []),
                    SemesterInput(index: 1, isActive: false, entries: [GradeInput(points: 3, kind: .written)])
                ]
            )
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.recordedCount == 2)
        #expect(outcome.includedCount == 2)
        #expect(isClose(outcome.averagePoints, 12))
    }
}

// MARK: - Klammern von Hand

/// Die Handklammerung: der Nutzer nimmt einen Kurs selbst heraus.
///
/// Sie steht über der automatischen Auswahl — ein von Hand geklammerter Kurs
/// geht nie ein, auch nicht mit 15 Punkten. Die einzige Grenze sind die
/// Prüfungsfächer, deren Kurse anrechnungspflichtig sind.
@Suite("Klammern von Hand")
struct ManualBracketTests {

    /// Drei Leistungsfächer und zwei Wahl-Basisfächer. Von 40 Kursen sind nur 20
    /// erfasst — es muss also nichts automatisch geklammert werden, und was hier
    /// herausfällt, fällt allein durch die Hand des Nutzers heraus.
    private static func scenario(bracketed: Set<Int>) -> [SubjectInput] {
        (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [
                subject("bf-sport", .wahlBasisfach, points: [15, 4, 9, 7], bracketed: bracketed),
                subject("bf-musik", .wahlBasisfach, allPoints: 8)
            ]
    }

    @Test("Ein von Hand geklammerter Kurs geht nicht ein")
    func manualBracketRemovesTheCourse() {
        let outcome = BlockOneCalculator.calculate(for: Self.scenario(bracketed: [1]))

        #expect(outcome.manuallyBracketedCourses == [course("bf-sport", 1)])
        #expect(!outcome.includedCourses.contains(course("bf-sport", 1)))
        #expect(outcome.recordedCount == 20)
        #expect(outcome.includedCount == 19)

        // 12 · 12 + 15 + 9 + 7 + 4 · 8 = 207 über 19 Kurse, dazu 96 aus der
        // Doppelwertung von lf-1 und lf-2: 303 auf 27 Wertungen.
        #expect(isClose(outcome.averagePoints, 303.0 / 27.0))
    }

    @Test("Auch der beste Kurs geht nicht ein, wenn er geklammert ist")
    func manualBracketBeatsTheBestResult() {
        let outcome = BlockOneCalculator.calculate(for: Self.scenario(bracketed: [0]))

        // 15 Punkte, und trotzdem draussen: die Entscheidung des Nutzers steht
        // über allem, was Score von sich aus täte.
        #expect(outcome.manuallyBracketedCourses == [course("bf-sport", 0)])
        #expect(outcome.includedCount == 19)
        // 12 · 12 + 4 + 9 + 7 + 4 · 8 = 196 über 19 Kurse, dazu 96: 292 auf 27.
        #expect(isClose(outcome.averagePoints, 292.0 / 27.0))
    }

    @Test("Ohne Klammer bleibt alles wie bisher")
    func withoutBracketsNothingChanges() {
        let outcome = BlockOneCalculator.calculate(for: Self.scenario(bracketed: []))

        #expect(outcome.excludedCourses.isEmpty)
        #expect(outcome.includedCount == 20)
    }

    @Test("Mehrere Klammern in einem Fach greifen alle")
    func severalBracketsInOneSubject() {
        let outcome = BlockOneCalculator.calculate(for: Self.scenario(bracketed: [1, 3]))

        #expect(outcome.manuallyBracketedCourses == [
            course("bf-sport", 1), course("bf-sport", 3)
        ])
        #expect(outcome.includedCount == 18)
    }

    @Test("Kurse der Leistungsfächer lassen sich nicht klammern")
    func advancedCoursesCannotBeBracketed() {
        let subjects = [
            subject("lf-deutsch", .leistungsfach, points: [15, 3, 3, 3], bracketed: [1, 2, 3])
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // Die Klammern bleiben wirkungslos: alle vier Halbjahre gehen ein.
        #expect(outcome.excludedCourses.isEmpty)
        #expect(outcome.includedCount == 4)
        #expect(isClose(outcome.averagePoints, 6))
    }

    @Test("Ein Pflicht-Basisfach lässt sich von Hand klammern")
    func mandatoryCoursesCanBeBracketedByHand() {
        // Score selbst klammert an Pflicht-Basisfächern nie — der Nutzer darf es
        // trotzdem, wenn er weiss, dass sein Kurs anders belegt ist.
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [subject("kf-geschichte", .pflichtBasisfach, points: [3, 10, 10, 10], bracketed: [0])]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.manuallyBracketedCourses == [course("kf-geschichte", 0)])
        #expect(outcome.includedCount == 15)
        // 12 · 12 + 3 · 10 = 174 über 15 Kurse, dazu 96: 270 auf 23 Wertungen.
        #expect(isClose(outcome.averagePoints, 270.0 / 23.0))
    }

    @Test("Die Handklammerung greift vor der automatischen")
    func manualBracketsComeFirst() {
        // 12 Leistungsfach- und 26 Pflicht-Basisfach-Kurse lassen zwei der 40 offen.
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + (1...6).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 10) }
            + [subject("kf-7", .pflichtBasisfach, points: [10, 10])]
            + [
                subject("bf-alpha", .wahlBasisfach, allPoints: 15, bracketed: [0, 1]),
                subject("bf-beta", .wahlBasisfach, allPoints: 8)
            ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // Ohne Klammern nähme Alpha mit viermal 15 beide offenen Kurse. Zwei
        // seiner Halbjahre sind aber geklammert, also gehen die beiden anderen
        // ein — und Beta bleibt trotzdem draussen, dafür automatisch.
        #expect(outcome.manuallyBracketedCourses == [
            course("bf-alpha", 0), course("bf-alpha", 1)
        ])
        #expect(outcome.includedCourses.contains(course("bf-alpha", 2)))
        #expect(outcome.includedCourses.contains(course("bf-alpha", 3)))
        #expect(outcome.automaticallyBracketedCourses.count == 4)
        #expect(outcome.includedCount == 40)
        // 12 · 12 + 26 · 10 + 2 · 15 = 434 über 40 Kurse, dazu 96: 530 auf 48.
        #expect(isClose(outcome.averagePoints, 530.0 / 48.0))
    }

    @Test("Jeder geklammerte Kurs trägt genau einen Grund")
    func everyBracketCarriesExactlyOneReason() {
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + (1...7).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 10) }
            + [
                subject("bf-alpha", .wahlBasisfach, allPoints: 14, limit: 1, bracketed: [0]),
                subject("bf-beta", .wahlBasisfach, allPoints: 5)
            ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // Alle drei Gründe kommen vor, und jeder Kurs steht in genau einem.
        #expect(!outcome.manuallyBracketedCourses.isEmpty)
        #expect(!outcome.coursesBeyondSubjectLimit.isEmpty)
        #expect(!outcome.automaticallyBracketedCourses.isEmpty)
        #expect(
            outcome.manuallyBracketedCourses.count
                + outcome.coursesBeyondSubjectLimit.count
                + outcome.automaticallyBracketedCourses.count
                == outcome.excludedCourses.count
        )
        #expect(outcome.includedCount + outcome.excludedCourses.count == outcome.recordedCount)
    }

    @Test("Die Kursgrenze greift vor der Handklammerung")
    func subjectLimitComesBeforeManualBrackets() {
        // Sport steht auf 4, 15, 9 und 7 mit Grenze 2 — die besten zwei sind
        // HJ 2 und HJ 3. HJ 2 ist zusätzlich von Hand geklammert.
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [subject("bf-sport", .wahlBasisfach, points: [4, 15, 9, 7], limit: 2, bracketed: [1])]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.coursesBeyondSubjectLimit == [
            course("bf-sport", 0), course("bf-sport", 3)
        ])
        #expect(outcome.manuallyBracketedCourses == [course("bf-sport", 1)])
        #expect(outcome.includedCourses.contains(course("bf-sport", 2)))
        #expect(outcome.includedCount == 13)
    }

    @Test("Die Klammerung ist bei gleicher Eingabe immer dieselbe")
    func bracketingIsDeterministic() {
        let subjects = Self.scenario(bracketed: [1, 2])

        #expect(
            BlockOneCalculator.calculate(for: subjects)
                == BlockOneCalculator.calculate(for: subjects)
        )
    }
}

// MARK: - Mündliche Prüfungsfächer

/// Die beiden mündlichen Prüfungsfächer und was aus ihnen für Block I folgt.
///
/// Die Regel steht in `BlockOneCalculator`: „Unter den anzurechnenden Kursen
/// müssen sein: […] die Kurse in den mündlichen Prüfungsfächern, soweit nicht
/// bereits berücksichtigt." Ihre Halbjahre sind damit anrechnungspflichtig und
/// lassen sich weder von Hand noch automatisch klammern.
@Suite("Mündliche Prüfungsfächer")
struct OralExamSubjectTests {

    /// Ein voller Jahrgang mit einem schwachen Wahl-Basisfach, das Score ohne die
    /// Angabe wegklammern würde: Musik steht auf 4 Punkten.
    private static func scenario(musicIsOralExam: Bool) -> [SubjectInput] {
        [
            subject("lf-deutsch", .leistungsfach, allPoints: 12),
            subject("lf-mathematik", .leistungsfach, allPoints: 11),
            subject("lf-biologie", .leistungsfach, allPoints: 13),

            subject("kf-englisch", .pflichtBasisfach, allPoints: 10),
            subject("kf-geschichte", .pflichtBasisfach, allPoints: 9),
            subject("kf-gemeinschaftskunde", .pflichtBasisfach, allPoints: 11),

            subject("bf-physik", .wahlBasisfach, allPoints: 14),
            subject("bf-chemie", .wahlBasisfach, allPoints: 13),
            subject("bf-geografie", .wahlBasisfach, allPoints: 12),
            subject("bf-sport", .wahlBasisfach, allPoints: 11),
            subject("bf-religion", .wahlBasisfach, allPoints: 5),
            subject("bf-musik", .wahlBasisfach, allPoints: 4, isOralExam: musicIsOralExam)
        ]
    }

    @Test("Ein mündliches Prüfungsfach wird nicht automatisch geklammert")
    func oralExamCoursesSurviveTheAutomaticBracketing() {
        let outcome = BlockOneCalculator.calculate(for: Self.scenario(musicIsOralExam: true))

        for index in 0..<4 {
            #expect(outcome.includedCourses.contains(course("bf-musik", index)))
        }
        #expect(outcome.includedCount == 40)
    }

    @Test("Ohne die Angabe rechnet Score zu gut")
    func withoutTheAnswerTheResultIsTooGood() {
        let without = BlockOneCalculator.calculate(for: Self.scenario(musicIsOralExam: false))
        let with = BlockOneCalculator.calculate(for: Self.scenario(musicIsOralExam: true))

        // Ohne die Angabe fliegen alle vier Musik-Kurse mit 4 Punkten heraus und
        // Religion rückt nach — der Schnitt sieht besser aus, als er ist. Genau
        // das war der Fehler, den die Prüfungsfächer beheben.
        #expect(without.averagePoints > with.averagePoints)

        // Mit Angabe sind 28 Kurse anrechnungspflichtig — 12 Leistungsfach-, 12
        // Pflicht-Basisfach- und die vier von Musik —, offen bleiben 12. Die gehen
        // an Physik, Chemie und Geografie:
        // 144 + 120 + 16 + (56 + 52 + 48) = 436 über 40 Kurse.
        //
        // Doppelt zählen Biologie (52) und Deutsch (48): 436 + 100 = 536 auf 48.
        #expect(isClose(with.averagePoints, 536.0 / 48.0))
        #expect(with.points == 447)

        // Ohne Angabe bleiben 16 offen, Musik fliegt ganz heraus und Sport rückt
        // nach: 144 + 120 + (56 + 52 + 48 + 44) = 464, mit Doppelwertung 564.
        #expect(isClose(without.averagePoints, 564.0 / 48.0))
        #expect(without.points == 470)
    }

    @Test("Ein mündliches Prüfungsfach lässt sich nicht von Hand klammern")
    func oralExamCoursesCannotBeBracketedByHand() {
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [
                subject(
                    "bf-musik",
                    .wahlBasisfach,
                    allPoints: 4,
                    bracketed: [0, 1, 2, 3],
                    isOralExam: true
                )
            ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.excludedCourses.isEmpty)
        #expect(outcome.includedCount == 16)
        // 12 · 12 + 4 · 4 = 160 über 16 Kurse, dazu 96: 256 auf 24 Wertungen.
        #expect(isClose(outcome.averagePoints, 256.0 / 24.0))
    }

    @Test("Die Kursgrenze greift bei einem mündlichen Prüfungsfach nicht")
    func oralExamSubjectsIgnoreTheCourseLimit() {
        let subjects = [
            subject("bf-musik", .wahlBasisfach, points: [15, 4, 4, 4], limit: 1, isOralExam: true)
        ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        #expect(outcome.excludedCourses.isEmpty)
        #expect(outcome.includedCount == 4)
        #expect(isClose(outcome.averagePoints, 6.75))
    }

    @Test("Ein mündliches Prüfungsfach verdrängt ein besseres Wahl-Basisfach")
    func oralExamSubjectsTakeTheSpotFromBetterCourses() {
        // 12 Leistungsfach- und 26 Pflicht-Basisfach-Kurse lassen zwei der 40 offen.
        let subjects = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + (1...6).map { subject("kf-\($0)", .pflichtBasisfach, allPoints: 10) }
            + [subject("kf-7", .pflichtBasisfach, points: [10, 10])]
            + [
                subject("bf-musik", .wahlBasisfach, points: [4, 4], isOralExam: true),
                subject("bf-physik", .wahlBasisfach, allPoints: 15)
            ]

        let outcome = BlockOneCalculator.calculate(for: subjects)

        // Musik ist anrechnungspflichtig und geht mit beiden Kursen ein. Für
        // Physik ist danach nichts mehr offen — trotz 15 Punkten.
        #expect(outcome.includedCourses.contains(course("bf-musik", 0)))
        #expect(outcome.includedCourses.contains(course("bf-musik", 1)))
        #expect(outcome.automaticallyBracketedCourses.count == 4)
        #expect(outcome.includedCount == 40)
        // 12 · 12 + 26 · 10 + 2 · 4 = 412 über 40 Kurse, dazu 96: 508 auf 48.
        #expect(isClose(outcome.averagePoints, 508.0 / 48.0))
    }

    @Test("Ein Pflicht-Basisfach als mündliches Prüfungsfach ändert nichts")
    func mandatorySubjectsAreAlreadyCovered() {
        // Punkt 3 der Regel sagt „soweit nicht bereits berücksichtigt" — ein
        // Pflicht-Basisfach ist es schon.
        let plain = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [subject("kf-deutsch", .pflichtBasisfach, allPoints: 5)]
        let flagged = (1...3).map { subject("lf-\($0)", .leistungsfach, allPoints: 12) }
            + [subject("kf-deutsch", .pflichtBasisfach, allPoints: 5, isOralExam: true)]

        #expect(
            BlockOneCalculator.calculate(for: plain).includedCourses
                == BlockOneCalculator.calculate(for: flagged).includedCourses
        )
    }
}
